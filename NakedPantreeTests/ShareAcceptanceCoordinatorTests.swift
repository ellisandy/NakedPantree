import CloudKit
import Foundation
import Testing

@testable import NakedPantree
@testable import NakedPantreePersistence

/// Issue #105: contract tests for `ShareAcceptanceCoordinator`. Drives
/// the coordinator's publish-on-throw / clear-on-success / retry
/// machinery through the internal `runFallible(_:)` seam — the public
/// `accept(metadata:)` entry point requires a `CKShare.Metadata`, and
/// `CKShare.Metadata.init()` is marked `unavailable` ("Obtain
/// `CKShareMetadata` from `CKFetchShareMetadataOperation` or
/// platform-specific scene / app delegate callbacks"). Going through
/// `runFallible` lets us pin the contract without runtime tricks to
/// fabricate a metadata.
///
/// `CloudShareAcceptance`'s own throw-path test lives in
/// `CloudShareAcceptanceTests` — it uses an internal seam
/// (`resolveSharedStore`) for the same reason.
@MainActor
@Suite("ShareAcceptanceCoordinator")
struct ShareAcceptanceCoordinatorTests {
    @Test("Happy path — successful operation clears any prior alert state")
    func happyPathClearsAlert() async throws {
        let coordinator = ShareAcceptanceCoordinator(
            service: NoOpShareAcceptanceService()
        )

        var callCount = 0
        await coordinator.runFallible {
            callCount += 1
        }

        #expect(coordinator.lastErrorMessage == nil)
        #expect(callCount == 1)
    }

    @Test("Failure path — error surfaces in lastErrorMessage")
    func failurePublishesError() async throws {
        // Sentinel error per advisor guidance: don't fake a real
        // `CKError.partialFailure` from memory — its userInfo shape is
        // specific and a mis-shaped stand-in produces a test that
        // passes for the wrong reason. The coordinator's contract
        // ("any throw → user-visible message") is what we're pinning.
        let coordinator = ShareAcceptanceCoordinator(
            service: NoOpShareAcceptanceService()
        )

        await coordinator.runFallible {
            throw SentinelTestError.boom
        }

        let message = try #require(coordinator.lastErrorMessage)
        #expect(!message.isEmpty)
    }

    @Test("Sharing-store-unavailable maps to its dedicated copy variant")
    func sharedStoreUnavailableHasItsOwnCopy() async throws {
        // The two failure shapes the coordinator distinguishes are
        // (a) `CloudShareAcceptanceError.sharedStoreUnavailable` —
        // "iCloud isn't ready yet, try again in a moment" — and
        // (b) anything else — generic retry copy. Pin the contract
        // here so a future error-mapping refactor can't silently
        // collapse them into one message.
        let dedicatedCoordinator = ShareAcceptanceCoordinator(
            service: NoOpShareAcceptanceService()
        )
        await dedicatedCoordinator.runFallible {
            throw CloudShareAcceptanceError.sharedStoreUnavailable
        }
        let dedicated = try #require(dedicatedCoordinator.lastErrorMessage)
        #expect(dedicated.contains("iCloud isn't ready yet"))

        let genericCoordinator = ShareAcceptanceCoordinator(
            service: NoOpShareAcceptanceService()
        )
        await genericCoordinator.runFallible {
            throw SentinelTestError.boom
        }
        let generic = try #require(genericCoordinator.lastErrorMessage)
        #expect(!generic.contains("iCloud isn't ready yet"))
    }

    @Test("Retry replays the failed operation; success clears alert state")
    func retryReplaysAndClearsOnSuccess() async throws {
        let coordinator = ShareAcceptanceCoordinator(
            service: NoOpShareAcceptanceService()
        )

        // Counter shared between the operation closure and the test —
        // the closure throws on its first invocation and succeeds on
        // every subsequent one. `actor`-wrap not needed: this test
        // is `@MainActor` so the closure runs serially with the
        // assertions below.
        let counter = CallCounter()
        let operation: @MainActor @Sendable () async throws -> Void = {
            await counter.increment()
            if await counter.count == 1 {
                throw SentinelTestError.boom
            }
        }

        await coordinator.runFallible(operation)
        // First attempt failed — alert is up.
        #expect(coordinator.lastErrorMessage != nil)
        await #expect(counter.count == 1)

        await coordinator.retry()
        // Second attempt succeeded — alert clears.
        #expect(coordinator.lastErrorMessage == nil)
        await #expect(counter.count == 2)
    }

    @Test("dismissError clears state without re-attempting")
    func dismissErrorDoesNotRetry() async throws {
        let coordinator = ShareAcceptanceCoordinator(
            service: NoOpShareAcceptanceService()
        )
        let counter = CallCounter()

        await coordinator.runFallible {
            await counter.increment()
            throw SentinelTestError.boom
        }
        #expect(coordinator.lastErrorMessage != nil)
        await #expect(counter.count == 1)

        coordinator.dismissError()
        #expect(coordinator.lastErrorMessage == nil)

        // After dismiss, a `retry()` is a no-op — no operation to
        // replay. Counter stays at 1.
        await coordinator.retry()
        await #expect(counter.count == 1)
    }
}

// MARK: - Test helpers

/// Actor-wrapped counter so the throwing operation closure (which has
/// to be `@Sendable`) can mutate shared state without a data-race
/// warning. Tests only read the count from the MainActor, so the
/// actor's serial isolation is overkill but keeps the closure
/// declaration trivial.
private actor CallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

private enum SentinelTestError: Error {
    case boom
}
