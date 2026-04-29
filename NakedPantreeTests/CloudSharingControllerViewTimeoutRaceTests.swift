import CloudKit
import Foundation
import Testing

@testable import NakedPantree
@testable import NakedPantreeDomain
@testable import NakedPantreePersistence

/// Coverage for `CloudSharingControllerView.runPrepareShareWithTimeout` —
/// the `withTaskGroup` race that backs the #90 timeout safety net. A
/// regression here would silently break the "blank sheet eventually
/// surfaces an error" guarantee, so the race wins on three axes are
/// each pinned down:
///
/// - Service resolves before timeout → `.success`
/// - Service hangs longer than timeout → `.failure(SharingTimeoutError)`
/// - Service throws before timeout → `.failure(<underlying error>)`
///
/// Each test uses a small timeout (~100ms) so the suite finishes
/// fast; the production default of 60s is overridden via the
/// `timeout:` parameter.
@Suite("CloudSharingControllerView timeout race")
struct CloudSharingControllerViewTimeoutRaceTests {
    @Test("Service resolves before timeout — returns .success")
    @MainActor
    func happyPath() async throws {
        let view = CloudSharingControllerView(
            householdID: UUID(),
            sharing: StubHouseholdSharingService(),
            onCompletion: {}
        )
        let result = await view.runPrepareShareWithTimeout(timeout: .seconds(5))
        switch result {
        case .success:
            break
        case .failure(let error):
            Issue.record("Expected success, got failure: \(error)")
        }
    }

    @Test("Service hangs longer than timeout — returns SharingTimeoutError")
    @MainActor
    func timeoutWins() async throws {
        let view = CloudSharingControllerView(
            householdID: UUID(),
            sharing: HangingSharingService(),
            onCompletion: {}
        )
        let result = await view.runPrepareShareWithTimeout(timeout: .milliseconds(100))
        switch result {
        case .success:
            Issue.record("Expected timeout, got success")
        case .failure(let error):
            #expect(
                error is CloudSharingControllerView.SharingTimeoutError,
                "Expected SharingTimeoutError, got: \(type(of: error))"
            )
        }
    }

    @Test("Service throws — returns the underlying error, not a timeout")
    @MainActor
    func errorPropagates() async throws {
        let view = CloudSharingControllerView(
            householdID: UUID(),
            sharing: ThrowingSharingService(),
            onCompletion: {}
        )
        let result = await view.runPrepareShareWithTimeout(timeout: .seconds(5))
        switch result {
        case .success:
            Issue.record("Expected failure, got success")
        case .failure(let error):
            #expect(
                error is RaceTestSharingError,
                "Expected RaceTestSharingError, got: \(type(of: error))"
            )
        }
    }
}

// MARK: - Test stubs

/// Stub that hangs forever via cancellable `Task.sleep`. The
/// surrounding `withTaskGroup.cancelAll()` will cancel this task once
/// the timeout sibling wins — `Task.sleep` throws `CancellationError`,
/// the `do/catch` in `runPrepareShareWithTimeout` converts it to
/// `.failure(CancellationError)`, but that result is the *loser* and
/// is discarded by the group's `next()`-then-cancel pattern.
private struct HangingSharingService: HouseholdSharingService {
    func prepareShare(
        for householdID: UUID
    ) async throws -> (CKShare, CKContainer) {
        try await Task.sleep(for: .seconds(60))
        // Unreachable on cancellation — but Swift requires a return
        // path. Constructing junk here is fine; we never actually
        // emit it.
        let zoneID = CKRecordZone.ID(
            zoneName: "unreachable",
            ownerName: CKCurrentUserDefaultName
        )
        let recordID = CKRecord.ID(
            recordName: "unreachable",
            zoneID: zoneID
        )
        let record = CKRecord(recordType: "Unreachable", recordID: recordID)
        return (
            CKShare(rootRecord: record),
            CKContainer(identifier: "iCloud.unreachable")
        )
    }
}

/// Distinct error type so the assertion can `is`-check it precisely
/// rather than matching any error.
private struct RaceTestSharingError: Error {}

private struct ThrowingSharingService: HouseholdSharingService {
    func prepareShare(
        for householdID: UUID
    ) async throws -> (CKShare, CKContainer) {
        throw RaceTestSharingError()
    }
}
