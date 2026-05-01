import EventKit
import Foundation
import NakedPantreeDomain

/// Issue #155 — production binding for `RemindersService`. The only
/// file in the codebase that imports EventKit. App-target placement
/// (not Domain) so `NakedPantreeDomain` stays platform-agnostic and
/// the unit tests don't drag EventKit's framework dependencies in.
///
/// **URL-or-notes resolver.** Apple developer forums report that
/// `EKReminder.url` may not survive iCloud sync (still unanswered as
/// of iOS 18 — see `RemindersURLRoundTripSpike`). The reconciler
/// handles this by keying off `nakedPantreeID: UUID?` on every
/// `ReminderSnapshot`; the resolution itself happens here, in
/// `snapshots(in:)`, via `ReminderTag.resolveItemID(url:notes:)`.
/// URL primary, notes-sentinel fallback. Belt-and-suspenders.
///
/// **Concurrency.** EventKit's `EKEventStore` is an `NSObject`
/// subclass and not `Sendable`. We wrap it inside a `final class`
/// declared `@unchecked Sendable` because:
///
/// - The store is created once per `LiveDependencies` build, owned
///   by the `LiveDependencies` value, and never mutated after init.
/// - All access to the store goes through the `RemindersService`
///   methods, which serialize work via `withCheckedContinuation` —
///   no shared mutable state crosses actor boundaries.
///
/// **EventKit error surface.** Predictable failures (denial, missing
/// list) surface as typed `RemindersServiceError` cases. Apple-side
/// failures bubble up as `.unexpected(message:)` with a localized
/// message the UI can present verbatim.
final class EventKitRemindersService: RemindersService, @unchecked Sendable {
    private let store: EKEventStore

    /// Construct against a shared `EKEventStore`. Production builds
    /// pass `EKEventStore()`; tests can pass a stub subclass if they
    /// need to (none of our current tests do — the reconciler tests
    /// use `InMemoryRemindersService` instead).
    init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    // MARK: RemindersService

    func requestAccess() async throws -> RemindersAccessStatus {
        // iOS 17+ uses `requestFullAccessToReminders`; v1 needs full
        // access (we read existing reminders to dedupe and write new
        // ones). The older write-only API would force a different
        // reconciliation path — not worth it for the v1 surface.
        do {
            let granted = try await store.requestFullAccessToReminders()
            return granted ? .granted : .denied
        } catch {
            // EventKit can throw if the user has previously denied —
            // present that as `.denied` (the UI flow is identical) and
            // let the caller's `.denied` branch surface the deep link
            // to Settings.
            return .denied
        }
    }

    func availableLists() async throws -> [RemindersListSummary] {
        try requireAccess()
        let calendars = store.calendars(for: .reminder)
        return
            calendars
            // Subscribed / read-only calendars surface in EventKit but
            // throw on save. Filtering them here means the picker
            // only offers lists we can actually write into.
            .filter { $0.allowsContentModifications }
            .map { calendar in
                RemindersListSummary(
                    id: calendar.calendarIdentifier,
                    title: calendar.title
                )
            }
    }

    func snapshots(in listID: String) async throws -> [ReminderSnapshot] {
        try requireAccess()
        let calendar = try requireCalendar(id: listID)
        let predicate = store.predicateForReminders(in: [calendar])
        return try await fetchSnapshots(matching: predicate)
    }

    func apply(_ plan: ReminderPlan, in listID: String) async throws {
        try requireAccess()
        let calendar = try requireCalendar(id: listID)

        // Creates don't need a pre-fetch — we just allocate fresh
        // `EKReminder`s and save. Doing them up front (outside the
        // mutation closure) keeps the dependent-fetch path tight.
        for create in plan.creates {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = calendar
            reminder.title = create.payload.title
            reminder.notes = create.payload.notes
            reminder.url = create.payload.url
            try save(reminder)
        }

        // Updates + completions both target existing rows by
        // `calendarItemIdentifier`. EventKit has no by-id lookup; we
        // walk the predicate result. Mutating + saving happens inside
        // the fetch callback so the non-Sendable `EKReminder` never
        // crosses the actor boundary back to the caller — fixes a
        // Swift 6 strict-concurrency data-race warning.
        if plan.titleUpdates.isEmpty && plan.completions.isEmpty {
            return
        }
        try await applyMutations(plan, in: calendar)
    }

    // MARK: Helpers

    private func requireAccess() throws {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .fullAccess, .writeOnly:
            return
        case .denied, .restricted, .notDetermined:
            throw RemindersServiceError.accessNotGranted
        @unknown default:
            throw RemindersServiceError.accessNotGranted
        }
    }

    private func requireCalendar(id: String) throws -> EKCalendar {
        guard let calendar = store.calendar(withIdentifier: id) else {
            throw RemindersServiceError.listNotFound(id: id)
        }
        return calendar
    }

    /// Fetch every reminder matching `predicate` and project to
    /// Sendable snapshots inside the completion closure — `EKReminder`
    /// is not `Sendable`, so we extract the values we care about
    /// before the continuation crosses actor boundaries.
    private func fetchSnapshots(
        matching predicate: NSPredicate
    ) async throws -> [ReminderSnapshot] {
        try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { results in
                guard let results else {
                    continuation.resume(returning: [])
                    return
                }
                let snapshots = results.map { reminder in
                    ReminderSnapshot(
                        calendarItemIdentifier: reminder.calendarItemIdentifier,
                        nakedPantreeID: ReminderTag.resolveItemID(
                            url: reminder.url,
                            notes: reminder.notes
                        ),
                        title: reminder.title ?? "",
                        isCompleted: reminder.isCompleted
                    )
                }
                continuation.resume(returning: snapshots)
            }
        }
    }

    /// Apply title-updates and mark-completed ops inside a single
    /// `fetchReminders` callback so non-Sendable `EKReminder`
    /// references never cross the continuation boundary. Returns
    /// after every save has been attempted; the first save that
    /// throws short-circuits via the resumed continuation.
    private func applyMutations(
        _ plan: ReminderPlan,
        in calendar: EKCalendar
    ) async throws {
        let predicate = store.predicateForReminders(in: [calendar])
        // Snapshot the store reference inside the closure rather
        // than capturing it implicitly — the closure is `@Sendable`
        // and we need a stable reference for the save call.
        let store = self.store
        typealias VoidContinuation = CheckedContinuation<Void, any Error>
        try await withCheckedThrowingContinuation { (continuation: VoidContinuation) in
            store.fetchReminders(matching: predicate) { results in
                guard let results else {
                    continuation.resume(returning: ())
                    return
                }
                var byID: [String: EKReminder] = [:]
                for reminder in results {
                    byID[reminder.calendarItemIdentifier] = reminder
                }
                do {
                    for update in plan.titleUpdates {
                        // Row was deleted in Reminders between snapshot
                        // + apply. Skip — the next push's reconciler
                        // will queue a fresh create.
                        guard let reminder = byID[update.calendarItemIdentifier]
                        else { continue }
                        reminder.title = update.newTitle
                        try store.save(reminder, commit: true)
                    }
                    for completion in plan.completions {
                        guard let reminder = byID[completion.calendarItemIdentifier]
                        else { continue }
                        reminder.isCompleted = true
                        try store.save(reminder, commit: true)
                    }
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(
                        throwing: RemindersServiceError.unexpected(
                            message: error.localizedDescription
                        )
                    )
                }
            }
        }
    }

    private func save(_ reminder: EKReminder) throws {
        do {
            try store.save(reminder, commit: true)
        } catch {
            throw RemindersServiceError.unexpected(
                message: error.localizedDescription
            )
        }
    }
}
