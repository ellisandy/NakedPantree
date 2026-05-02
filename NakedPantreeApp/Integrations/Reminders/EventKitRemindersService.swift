import EventKit
import Foundation
import NakedPantreeDomain
import os

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

    /// Issue #162 diagnostic log. Tagged with subsystem
    /// `cc.mnmlst.nakedpantree` and category `reminders` so a single
    /// Console.app filter — `subsystem:cc.mnmlst.nakedpantree
    /// category:reminders` — captures the full picker-empty-state
    /// trace. Lifetime: keep until #162 closes; then trim to whatever
    /// is genuinely load-bearing.
    private static let logger = Logger(
        subsystem: "cc.mnmlst.nakedpantree",
        category: "reminders"
    )

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
        let preStatus = EKEventStore.authorizationStatus(for: .reminder).rawValue
        Self.logger.notice(
            "requestAccess: pre-grant authorizationStatus=\(preStatus, privacy: .public)"
        )
        do {
            let granted = try await store.requestFullAccessToReminders()
            let postStatus = EKEventStore.authorizationStatus(for: .reminder).rawValue
            Self.logger.notice(
                // swiftlint:disable:next line_length
                "requestAccess: granted=\(granted, privacy: .public) postStatus=\(postStatus, privacy: .public)"
            )
            if granted {
                // TestFlight build 58 bug: `EKEventStore` caches its
                // source list at construction time. Our store is
                // built at `LiveDependencies` boot, before TCC is
                // granted. After the first-time grant the cache
                // still reads as empty, so `calendars(for: .reminder)`
                // returns `[]` and the picker renders "No Reminders
                // lists" even though the user has lists. Apple
                // documents `reset()` as the way to invalidate cached
                // state after an authorization change; calling it on
                // every grant is safe (no-op when the store was
                // already in sync) and removes the order-of-init
                // pitfall. See `EKEventStore.reset()` headerdoc.
                store.reset()
                Self.logger.notice("requestAccess: store.reset() called")
            }
            return granted ? .granted : .denied
        } catch {
            // EventKit can throw if the user has previously denied —
            // present that as `.denied` (the UI flow is identical) and
            // let the caller's `.denied` branch surface the deep link
            // to Settings.
            Self.logger.error(
                "requestAccess: threw — \(error.localizedDescription, privacy: .public)"
            )
            return .denied
        }
    }

    func availableLists() async throws -> [RemindersListSummary] {
        Self.logger.notice("availableLists: entry")
        do {
            try requireAccess()
        } catch {
            Self.logger.error("availableLists: requireAccess threw — bailing")
            throw error
        }
        // Issue #162 cold-cache mitigation. The user reported tapping
        // "Pick a list" right after granting permission and seeing the
        // picker render with zero lists, then a few minutes later
        // re-tapping and seeing all eight. EKEventStore's iCloud
        // sources are populated asynchronously; on a fresh grant the
        // first read of `calendars(for: .reminder)` returns an empty
        // array even though the user demonstrably has lists.
        //
        // Apple ships two relevant hooks:
        //
        // - `refreshSourcesIfNecessary()` — initiates a sync if one is
        //   due. No-op when the cache is already warm.
        // - `EKEventStoreChangedNotification` — fires when the store's
        //   data changes, including after a permission grant or a
        //   completed sync.
        //
        // Strategy: refresh, read, and if empty wait up to 10s for
        // the change notification then re-read. 10s is the hard cap —
        // anything longer reads as "broken" and the user's instinct
        // is to tap again, which lands them in a worse state. The
        // Settings row presents a spinner during the wait so the
        // gap doesn't feel silent.
        store.refreshSourcesIfNecessary()
        var calendars = store.calendars(for: .reminder)
        if calendars.isEmpty {
            Self.logger.notice(
                "availableLists: cold-cache, awaiting EKEventStoreChanged (10s cap)"
            )
            await Self.waitForStoreChangeOrTimeout(seconds: 10)
            calendars = store.calendars(for: .reminder)
            let postWaitCount = calendars.count
            Self.logger.notice(
                "availableLists: post-wait calendars.count=\(postWaitCount, privacy: .public)"
            )
        }
        let sources = store.sources
        Self.logger.notice(
            // swiftlint:disable:next line_length
            "availableLists: sources.count=\(sources.count, privacy: .public) calendars.count=\(calendars.count, privacy: .public)"
        )
        for (index, source) in sources.enumerated() {
            Self.logger.notice(
                // swiftlint:disable:next line_length
                "availableLists: source[\(index, privacy: .public)] title='\(source.title, privacy: .public)' sourceType=\(source.sourceType.rawValue, privacy: .public)"
            )
        }
        for (index, calendar) in calendars.enumerated() {
            Self.logger.notice(
                // swiftlint:disable:next line_length
                "availableLists: calendar[\(index, privacy: .public)] title='\(calendar.title, privacy: .public)' allowsContentModifications=\(calendar.allowsContentModifications, privacy: .public) sourceTitle='\(calendar.source?.title ?? "<nil>", privacy: .public)' sourceType=\(calendar.source?.sourceType.rawValue ?? -1, privacy: .public)"
            )
        }
        let writable = calendars.filter { $0.allowsContentModifications }
        Self.logger.notice(
            "availableLists: writable.count=\(writable.count, privacy: .public)"
        )
        return writable.map { calendar in
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
        Self.logger.notice(
            "apply: creates.count=\(plan.creates.count, privacy: .public)"
        )
        for (index, create) in plan.creates.enumerated() {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = calendar
            reminder.title = create.payload.title
            reminder.notes = create.payload.notes
            reminder.url = create.payload.url
            // Diag (post-#168): pin what we *wrote* so the fetch-side
            // log can confirm round-trip vs sync-strip vs display-suppress.
            let writtenURL = reminder.url?.absoluteString ?? "<nil>"
            Self.logger.notice(
                // swiftlint:disable:next line_length
                "apply: create[\(index, privacy: .public)] title='\(reminder.title ?? "<nil>", privacy: .public)' url-pre-save='\(writtenURL, privacy: .public)'"
            )
            try save(reminder)
            let postSaveURL = reminder.url?.absoluteString ?? "<nil>"
            Self.logger.notice(
                // swiftlint:disable:next line_length
                "apply: create[\(index, privacy: .public)] saved id='\(reminder.calendarItemIdentifier, privacy: .public)' url-post-save='\(postSaveURL, privacy: .public)'"
            )
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
        Self.logger.notice(
            "requireAccess: status=\(status.rawValue, privacy: .public)"
        )
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
    ///
    /// **Diag (post-#168).** The user installed the build with the
    /// `nakedpantree://` scheme registered and reported the URL field
    /// in Apple's Reminders.app still rendered blank on a freshly
    /// pushed reminder. Three branches that could explain the empty
    /// chip:
    /// - (a) we never wrote `reminder.url` at all
    /// - (b) we wrote it; iCloud sync stripped it
    /// - (c) we wrote it; it's still there; Reminders.app refuses to
    ///   render non-http URLs as a chip
    ///
    /// Logging each fetched reminder's url, notes-prefix, and title
    /// answers (a) vs (b)/(c) directly — if the log shows a
    /// `nakedpantree://item/<UUID>` value, we wrote it AND it
    /// survived; the empty chip is then a Reminders.app display
    /// quirk and the fix is a different scheme (universal link, etc.).
    /// If the log shows `<nil>`, we either never wrote it or sync
    /// dropped it; we'd then add write-side logging in `apply` to
    /// disambiguate.
    private func fetchSnapshots(
        matching predicate: NSPredicate
    ) async throws -> [ReminderSnapshot] {
        try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { results in
                guard let results else {
                    Self.logger.notice("fetchSnapshots: results=nil")
                    continuation.resume(returning: [])
                    return
                }
                Self.logger.notice(
                    "fetchSnapshots: results.count=\(results.count, privacy: .public)"
                )
                let snapshots = results.enumerated().map { index, reminder in
                    let urlString = reminder.url?.absoluteString ?? "<nil>"
                    // Notes can be long; cap to 100 chars so the log
                    // doesn't blow up on hand-edited reminders.
                    let notes = reminder.notes ?? "<nil>"
                    let notesPreview: String
                    if notes.count > 100 {
                        notesPreview = String(notes.prefix(100)) + "…"
                    } else {
                        notesPreview = notes
                    }
                    let title = reminder.title ?? "<nil>"
                    Self.logger.notice(
                        // swiftlint:disable:next line_length
                        "fetchSnapshots: row[\(index, privacy: .public)] title='\(title, privacy: .public)' url='\(urlString, privacy: .public)' notes='\(notesPreview, privacy: .public)'"
                    )
                    return ReminderSnapshot(
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

    /// Issue #162 — block until EventKit posts an
    /// `EKEventStoreChangedNotification` or `seconds` elapse,
    /// whichever comes first. Used by `availableLists()` to wait out
    /// the iCloud cold-cache window after a fresh permission grant.
    ///
    /// Implementation: an `AsyncStream` wraps a one-shot block-based
    /// observer; the stream's `onTermination` removes the observer so
    /// neither the change-wait task nor the timeout task can leak it.
    /// A task group races the two; whichever finishes first cancels
    /// the other. `static` so the closure passed to
    /// `addObserver(forName:object:queue:using:)` doesn't capture
    /// `self` (the class is `@unchecked Sendable` and the observer
    /// callback runs on whatever queue NotificationCenter chooses —
    /// keeping `self` out of the closure removes that contract).
    ///
    /// **Why the `ObserverBox` class:** `NSObjectProtocol` (the type
    /// `addObserver` returns) isn't `Sendable`. To carry the observer
    /// reference into the `@Sendable onTermination` closure we wrap
    /// it in a tiny `@unchecked Sendable` box. The box is written
    /// exactly once (synchronously, inside the `AsyncStream`
    /// initializer) and read exactly once (in `onTermination`, which
    /// fires after the stream terminates) — no concurrent access, so
    /// `@unchecked` is honest here.
    private static func waitForStoreChangeOrTimeout(
        seconds: TimeInterval
    ) async {
        let timeoutNanos = UInt64(seconds * 1_000_000_000)
        let center = NotificationCenter.default
        let box = ObserverBox()

        let stream = AsyncStream<Void> { continuation in
            box.observer = center.addObserver(
                forName: .EKEventStoreChanged,
                object: nil,
                queue: nil
            ) { _ in
                continuation.yield(())
            }
            continuation.onTermination = { [box] _ in
                if let observer = box.observer {
                    center.removeObserver(observer)
                }
            }
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in stream {
                    return
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanos)
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    /// See `waitForStoreChangeOrTimeout` — just a reference cell so
    /// the non-Sendable `NSObjectProtocol` can transit a `@Sendable`
    /// closure boundary without spurious warnings.
    private final class ObserverBox: @unchecked Sendable {
        var observer: NSObjectProtocol?
    }
}
