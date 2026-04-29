import Foundation

/// Pure-function home for `RootView.makeRemoteChangeWaiter`'s
/// closure body, lifted out for testability (issue #116).
///
/// **Why this lives at file scope, not on `RootView`:**
/// `RootView` is `@MainActor`-isolated and its body is hard to
/// reach from `@testable import`. Extracting here gives us a
/// pure function that takes its dependencies as closures — a
/// `RemoteChangeMonitor`'s `isObserving` flag, an
/// `AccountStatusMonitor`'s `.available` predicate, and a
/// change-token reader — so tests can drive every gate (no-op
/// monitor, account unavailable, token bump, cancellation) with
/// stubbed values.
///
/// The production closure in `RootView` constructs three closures
/// from its environment monitors and forwards to `wait(...)`.
enum RemoteChangeWaiter {
    /// Wait for the remote-change monitor's token to advance, or
    /// for the surrounding task to be cancelled — whichever comes
    /// first. Returns once one of these gates trips:
    ///
    /// 1. `isObserving()` returns `false` — no-op monitor (preview /
    ///    snapshot / EMPTY_STORE / unit-test-host paths). Returns
    ///    immediately so bootstrap doesn't burn its timeout in
    ///    those configurations where a token bump will never come.
    /// 2. `accountStatusIsAvailable()` returns `false` — iCloud
    ///    isn't reachable, so the CloudKit mirror won't deliver
    ///    notifications. Same fast-fail rationale.
    /// 3. `changeToken()` advances past `initial` — the actual
    ///    "remote change observed" condition.
    /// 4. `Task.isCancelled` becomes `true` — bootstrap's timeout
    ///    fired and is racing us; honour it.
    ///
    /// The polling interval (~75ms) is short enough that the
    /// monitor's 120ms debounce dominates wakeup latency anyway.
    static func wait(
        isObserving: @Sendable () -> Bool,
        accountStatusIsAvailable: @Sendable () async -> Bool,
        changeToken: @Sendable () async -> UUID,
        pollInterval: Duration = .milliseconds(75)
    ) async {
        guard isObserving() else { return }
        guard await accountStatusIsAvailable() else { return }
        let initial = await changeToken()
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                return
            }
            let current = await changeToken()
            if current != initial { return }
        }
    }
}
