import CloudKit
import NakedPantreeDomain
import NakedPantreePersistence

/// Test-only `HouseholdSharingService` that returns a synthetic
/// `CKShare` and `CKContainer` without contacting iCloud. Wired in
/// `NakedPantreeApp.init` when the `STUB_SHARING=1` launch environment
/// variable is set — exclusively used by `SharingUITests`.
///
/// **Why it lives in the app target, not a test target:** UI tests
/// run against the production app process, so the stub has to be
/// linked into the app binary. The runtime gate (`STUB_SHARING`) keeps
/// it inert in TestFlight / App Store builds — `NakedPantreeApp.init`
/// only ever asks for `StubHouseholdSharingService()` when the env
/// var is present, which only happens via XCUIApplication.launchEnvironment.
///
/// **Why a synthetic share rather than a thrown error:** the literal
/// #90 symptom is a *blank sheet*. The test asserts the sheet
/// renders SwiftUI's UICloudSharingController-bridge, which means the
/// preparation handler has to receive a non-nil share. Apple's
/// `CKShare(rootRecord:)` builds a valid in-memory share object
/// without storing it in iCloud — UICloudSharingController will try
/// to render its participant UI and either succeed (showing controls
/// the test can assert on) or surface an error UI (also assertable).
/// A throwing stub would short-circuit the preparation handler before
/// the UI path under test runs.
struct StubHouseholdSharingService: HouseholdSharingService {
    /// Container identifier used by the synthetic `CKContainer`. The
    /// `.test` suffix avoids any chance of accidental cross-talk with
    /// the production container if a CI runner ever ends up signed
    /// into iCloud — a misconfigured container ID returns errors at
    /// the CK layer rather than mutating real data.
    static let stubContainerIdentifier = "iCloud.cc.mnmlst.nakedpantree.test"

    func prepareShare(
        for householdID: Household.ID
    ) async throws -> (CKShare, CKContainer) {
        let zoneID = CKRecordZone.ID(
            zoneName: "stub-share-zone",
            ownerName: CKCurrentUserDefaultName
        )
        let recordID = CKRecord.ID(
            recordName: "household-\(householdID.uuidString)",
            zoneID: zoneID
        )
        let rootRecord = CKRecord(recordType: "HouseholdEntity", recordID: recordID)
        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = "Naked Pantree (UI test)"
        let container = CKContainer(identifier: Self.stubContainerIdentifier)
        return (share, container)
    }
}
