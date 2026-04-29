import Foundation
import Testing

@testable import NakedPantree

/// Coverage for `RemoteChangeWaiter.wait` — the bootstrap-deferred
/// "wait for the first remote-change tick or bail" closure that
/// `RootView.makeRemoteChangeWaiter` previously held inline (issue
/// #116). A regression in any of the three gates (no-op monitor
/// fast-fail, account-unavailable fast-fail, token-advance return)
/// or the cancellation handling would silently keep the splash
/// screen up past the bootstrap timeout, or worse, never let
/// bootstrap proceed.
@Suite("RemoteChangeWaiter")
struct RemoteChangeWaiterTests {
    @Test("Returns immediately when isObserving() is false (no-op monitor)")
    func notObservingReturnsImmediately() async throws {
        // Both fall-through closures `Issue.record` if invoked —
        // when isObserving returns false, neither should be called.
        await RemoteChangeWaiter.wait(
            isObserving: { false },
            accountStatusIsAvailable: {
                Issue.record("should not be called when not observing")
                return true
            },
            changeToken: {
                Issue.record("should not be called when not observing")
                return UUID()
            }
        )
    }

    @Test("Returns immediately when account status is not .available")
    func unavailableAccountReturnsImmediately() async throws {
        await RemoteChangeWaiter.wait(
            isObserving: { true },
            accountStatusIsAvailable: { false },
            changeToken: {
                Issue.record("should not be called when account is unavailable")
                return UUID()
            }
        )
    }

    @Test("Returns when changeToken advances")
    func tokenAdvanceReturns() async throws {
        // Counter ticks per call. First read = initial; subsequent
        // reads return a different UUID once `bumped == true`.
        let bumped = AtomicBool(false)
        let initial = UUID()
        let bumpedID = UUID()
        // Bump after a short delay so the polling loop sees it.
        Task {
            try? await Task.sleep(for: .milliseconds(20))
            bumped.value = true
        }

        let start = Date()
        await RemoteChangeWaiter.wait(
            isObserving: { true },
            accountStatusIsAvailable: { true },
            changeToken: { bumped.value ? bumpedID : initial },
            pollInterval: .milliseconds(10)
        )
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 1.0, "Waiter should return promptly after the bump.")
    }

    @Test("Returns when the surrounding task is cancelled")
    func cancellationReturns() async throws {
        let waiter = Task {
            await RemoteChangeWaiter.wait(
                isObserving: { true },
                accountStatusIsAvailable: { true },
                // Stable token — without cancellation, this would loop forever.
                changeToken: { UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) },
                pollInterval: .milliseconds(10)
            )
        }
        // Give the waiter a chance to enter the loop.
        try? await Task.sleep(for: .milliseconds(30))
        waiter.cancel()
        // `await waiter.value` returns once the waiter exits. If
        // cancellation isn't honoured, this hangs the test until
        // Swift Testing's per-test timeout kicks in.
        let start = Date()
        await waiter.value
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 1.0, "Cancelled waiter should return promptly.")
    }
}

/// Tiny `Sendable` mutable holder so the closures in
/// `tokenAdvanceReturns` can flip a flag mid-test. Avoiding a full
/// actor since the test logic is straightforward and the lock is
/// trivial.
private final class AtomicBool: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Bool

    init(_ initial: Bool) {
        storage = initial
    }

    var value: Bool {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}
