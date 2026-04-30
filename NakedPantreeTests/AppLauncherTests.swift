import Foundation
import Testing

@testable import NakedPantree

/// Coverage for the issue #106 store-load failure surface. The previous
/// `fatalError` crashed the app on every launch when Core Data couldn't
/// open its store. The launcher's new shape catches the throw, transitions
/// to `.failed`, and re-runs the builder on retry / reset.
@MainActor
@Suite("AppLauncher")
struct AppLauncherTests {
    @Test("Builder succeeds — state is .ready, no failure surface")
    func builderSuccessReadyState() {
        let stubMonitor = AccountStatusMonitor()
        var deleteCallCount = 0

        let launcher = AppLauncher(
            buildDependencies: { LiveDependencies.makeStub() },
            makeFailureAccountMonitor: { stubMonitor },
            deleteLocalStores: { deleteCallCount += 1 }
        )

        guard case .ready = launcher.state else {
            Issue.record("Expected .ready, got: \(launcher.state)")
            return
        }
        #expect(deleteCallCount == 0, "Reset action must not fire on a happy-path launch.")
    }

    @Test("Builder throws — state is .failed, monitor and description are surfaced")
    func builderFailureCarriesContext() {
        let stubMonitor = AccountStatusMonitor()
        let underlying = LauncherTestError(message: "Stubbed store load failure")

        let launcher = AppLauncher(
            buildDependencies: { throw underlying },
            makeFailureAccountMonitor: { stubMonitor },
            deleteLocalStores: {}
        )

        guard case .failed(let failure) = launcher.state else {
            Issue.record("Expected .failed, got: \(launcher.state)")
            return
        }
        #expect(failure.errorDescription == underlying.localizedDescription)
        // The recovery view reads `.status` off this exact instance, so
        // identity matters — pin it.
        #expect(failure.accountStatusMonitor === stubMonitor)
    }

    @Test("retry() re-runs the builder — failure → success transitions to .ready")
    func retryRecoversAfterTransientFailure() {
        let stubMonitor = AccountStatusMonitor()
        var attemptCount = 0
        // First call throws (transient failure), second call succeeds —
        // models the user tapping Try Again after a brief filesystem
        // hiccup.
        let launcher = AppLauncher(
            buildDependencies: {
                attemptCount += 1
                if attemptCount == 1 {
                    throw LauncherTestError(message: "Transient")
                }
                return LiveDependencies.makeStub()
            },
            makeFailureAccountMonitor: { stubMonitor },
            deleteLocalStores: {}
        )

        guard case .failed = launcher.state else {
            Issue.record("Expected .failed after first attempt, got: \(launcher.state)")
            return
        }

        launcher.retry()

        guard case .ready = launcher.state else {
            Issue.record("Expected .ready after retry, got: \(launcher.state)")
            return
        }
        #expect(attemptCount == 2)
    }

    @Test("resetAndRetry() deletes local stores then re-runs the builder")
    func resetAndRetryDeletesAndRebuilds() {
        let stubMonitor = AccountStatusMonitor()
        var deleteCallCount = 0
        var attemptCount = 0
        // First attempt throws (init); second attempt (post-reset) succeeds.
        let launcher = AppLauncher(
            buildDependencies: {
                attemptCount += 1
                if attemptCount == 1 {
                    throw LauncherTestError(message: "Corrupt store")
                }
                return LiveDependencies.makeStub()
            },
            makeFailureAccountMonitor: { stubMonitor },
            deleteLocalStores: { deleteCallCount += 1 }
        )

        guard case .failed = launcher.state else {
            Issue.record("Expected .failed at init, got: \(launcher.state)")
            return
        }

        launcher.resetAndRetry()

        #expect(deleteCallCount == 1, "Reset must delete local stores exactly once.")
        #expect(attemptCount == 2, "Reset must trigger a fresh build attempt.")
        guard case .ready = launcher.state else {
            Issue.record("Expected .ready after resetAndRetry, got: \(launcher.state)")
            return
        }
    }

    @Test("retry() does NOT call the delete-stores closure")
    func retryDoesNotDelete() {
        var deleteCallCount = 0
        let launcher = AppLauncher(
            buildDependencies: { throw LauncherTestError(message: "Persistent failure") },
            makeFailureAccountMonitor: { AccountStatusMonitor() },
            deleteLocalStores: { deleteCallCount += 1 }
        )
        launcher.retry()
        #expect(
            deleteCallCount == 0,
            "Try Again must never delete user data — only Reset should."
        )
    }

    @Test("After a persistent failure, state stays .failed across retries")
    func persistentFailureStaysFailed() {
        let launcher = AppLauncher(
            buildDependencies: { throw LauncherTestError(message: "Always fails") },
            makeFailureAccountMonitor: { AccountStatusMonitor() },
            deleteLocalStores: {}
        )
        launcher.retry()
        launcher.retry()
        guard case .failed = launcher.state else {
            Issue.record("Expected .failed, got: \(launcher.state)")
            return
        }
    }
}

// MARK: - Test fixtures

private struct LauncherTestError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension LiveDependencies {
    /// Stubbed dependencies for `AppLauncher` tests — the builder
    /// returns this on the success path so the launcher transitions
    /// to `.ready` without standing up a real Core Data stack.
    @MainActor
    fileprivate static func makeStub() -> LiveDependencies {
        LiveDependencies(
            repositories: .makePreview(),
            remoteChangeMonitor: RemoteChangeMonitor(),
            accountStatusMonitor: AccountStatusMonitor(),
            householdSharing: nil,
            shareAcceptanceCoordinator: ShareAcceptanceCoordinator(
                service: NoOpShareAcceptanceService()
            ),
            notificationScheduler: NotificationScheduler(),
            notificationRouting: NotificationRoutingService(),
            notificationSettings: NotificationSettings()
        )
    }
}
