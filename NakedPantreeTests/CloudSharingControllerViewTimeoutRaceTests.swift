import CloudKit
import Foundation
import Testing

@testable import NakedPantree
@testable import NakedPantreeDomain
@testable import NakedPantreePersistence

/// Coverage for `ShareSheetPreparation.prepareShare` — the
/// `withTaskGroup` race that backs the #90 timeout safety net. Pinned
/// against the three race outcomes:
///
/// - Service resolves before timeout → `.success`
/// - Service hangs longer than timeout → `.failure(TimeoutError)`
/// - Service throws before timeout → `.failure(<underlying error>)`
///
/// **Pre-Phase-11 history.** This logic used to live on
/// `CloudSharingControllerView.runPrepareShareWithTimeout`, paired
/// with the now-deprecated `UICloudSharingController(preparationHandler:)`.
/// Issue #90: that init silently fails to invoke its preparation
/// handler on iOS 17+/26, so the race was moved up to
/// `ShareSheetPreparation` and the controller now uses
/// `init(share:container:)` against an already-resolved share. Tests
/// follow the logic; their shape is otherwise unchanged.
///
/// Each test uses a small timeout (~100ms) so the suite finishes
/// fast; the production default of 60s is overridden via the
/// `timeout:` parameter.
@Suite("ShareSheetPreparation timeout race")
struct ShareSheetPreparationTimeoutRaceTests {
    @Test("Service resolves before timeout — returns .success")
    func happyPath() async throws {
        let result = await ShareSheetPreparation.prepareShare(
            for: UUID(),
            using: StubHouseholdSharingService(),
            timeout: .seconds(5)
        )
        switch result {
        case .success:
            break
        case .failure(let error):
            Issue.record("Expected success, got failure: \(error)")
        }
    }

    @Test("Service hangs longer than timeout — returns TimeoutError")
    func timeoutWins() async throws {
        let result = await ShareSheetPreparation.prepareShare(
            for: UUID(),
            using: HangingSharingService(),
            timeout: .milliseconds(100)
        )
        switch result {
        case .success:
            Issue.record("Expected timeout, got success")
        case .failure(let error):
            #expect(
                error is ShareSheetPreparation.TimeoutError,
                "Expected TimeoutError, got: \(type(of: error))"
            )
        }
    }

    @Test("Service throws — returns the underlying error, not a timeout")
    func errorPropagates() async throws {
        let result = await ShareSheetPreparation.prepareShare(
            for: UUID(),
            using: ThrowingSharingService(),
            timeout: .seconds(5)
        )
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
/// the `do/catch` in `prepareShare` converts it to `.failure`, but
/// that result is the *loser* and is discarded by the group's
/// `next()`-then-cancel pattern.
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
