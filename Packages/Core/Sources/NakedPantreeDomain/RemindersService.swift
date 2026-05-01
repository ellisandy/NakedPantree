import Foundation

/// Issue #155 — service contract for the EventKit-backed Reminders
/// integration. The protocol keeps EventKit out of the App's view
/// layer: views see `RemindersService`, the production binding is the
/// `EventKitRemindersService` adapter in the App target, snapshot /
/// preview / test paths bind the `InMemoryRemindersService` stub.
///
/// The adapter is the only layer that imports EventKit. Everything in
/// `NakedPantreeDomain` is platform-agnostic.
///
/// **Permission model.** `requestAccess()` is called lazily — first
/// time the user taps "Push to Reminders" — not at launch. iOS 17+
/// uses `requestFullAccessToReminders`; we don't expose the granular
/// older API because v1's writes need full access anyway. Denial
/// returns `.denied`; the UI then surfaces a deep link to Settings.
///
/// **Error model.** Each operation throws a `RemindersServiceError`
/// for predictable failures. Unexpected EventKit errors propagate
/// through `.unexpected(underlying:)` so the call site can present
/// the OS-localized description without leaking type details.
public protocol RemindersService: Sendable {
    /// Request the user's permission to read/write Reminders. Resolves
    /// to the post-prompt status — `.granted`, `.denied`, or
    /// `.restricted` (parental controls / MDM). Always safe to call
    /// repeatedly; iOS surfaces the prompt only on the first call.
    func requestAccess() async throws -> RemindersAccessStatus

    /// Lists the user can write into. Filters out read-only calendars
    /// (subscribed lists, etc.) so the picker doesn't offer something
    /// we'll fail to write to. Empty array is valid — the UI prompts
    /// the user to create a list in Reminders first.
    func availableLists() async throws -> [RemindersListSummary]

    /// Snapshot every reminder in the given list, projected through
    /// the adapter's URL-or-notes resolver. The reconciler consumes
    /// the result; the App layer never touches `EKReminder` directly.
    func snapshots(in listID: String) async throws -> [ReminderSnapshot]

    /// Apply a previously-computed plan in `creates → titleUpdates →
    /// completions` order. The adapter writes through to EventKit and
    /// commits in batches sized to whatever EventKit prefers (the
    /// stub commits everything atomically; behavior is observationally
    /// equivalent for reconciliation purposes).
    func apply(_ plan: ReminderPlan, in listID: String) async throws
}

/// Three-state result for `requestAccess()`. Mirrors EventKit's
/// granted / denied / restricted shape without leaking the EventKit
/// types.
public enum RemindersAccessStatus: Sendable, Hashable {
    /// User granted full access. Reads + writes are permitted.
    case granted
    /// User denied (or has previously denied) access. The UI should
    /// surface a deep link to Settings → Naked Pantree → Reminders.
    case denied
    /// MDM / parental controls have blocked access. Same UI fallback
    /// as `.denied` — there's nothing the user can do in-app.
    case restricted
}

/// Errors `RemindersService` operations may throw. Equatable so test
/// `#expect(throws: ...)` can assert specific cases.
public enum RemindersServiceError: Error, Equatable, Sendable {
    /// `requestAccess()` resolved to `.denied` or `.restricted` and
    /// the caller proceeded anyway. The orchestrator catches this and
    /// surfaces the inline "Open Settings" path; the lower layers
    /// shouldn't have to special-case denial in every method.
    case accessNotGranted
    /// `availableLists()` couldn't find a calendar matching the
    /// caller-supplied identifier — list was deleted in Reminders
    /// between selection and apply. The UI re-prompts for a list.
    case listNotFound(id: String)
    /// EventKit raised an error we can't categorize. The
    /// `localizedDescription` is the user-friendly fallback message.
    case unexpected(message: String)
}
