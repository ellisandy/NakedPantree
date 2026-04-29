import CloudKit
import Foundation
import Testing

@testable import NakedPantree
@testable import NakedPantreeDomain
@testable import NakedPantreePersistence

/// Unit coverage for the test-only stub used by `SharingUITests`. The
/// stub never reaches CloudKit, so its behaviour is deterministic and
/// fully checkable here. If a regression breaks the stub's output
/// shape (e.g. `prepareShare` starts throwing), the UI test will fail
/// for an unrelated reason — these tests catch that earlier.
@Suite("Stub household sharing service")
struct StubHouseholdSharingServiceTests {
    @Test("prepareShare returns a non-nil share titled for the app")
    func returnsTitledShare() async throws {
        let stub = StubHouseholdSharingService()
        let (share, _) = try await stub.prepareShare(for: UUID())
        #expect(
            share[CKShare.SystemFieldKey.title] as? String == "Naked Pantree (UI test)"
        )
    }

    @Test("prepareShare returns a share whose ID lives in the stub zone")
    func sharesLiveInStubZone() async throws {
        let stub = StubHouseholdSharingService()
        let (share, _) = try await stub.prepareShare(for: UUID())
        // CKShare exposes its own `recordID` (not the root's). Both
        // share and root live in the same zone, so checking the share's
        // zone name is a reliable proxy without touching the root record
        // API (which has shifted across iOS versions).
        #expect(share.recordID.zoneID.zoneName == "stub-share-zone")
    }

    @Test("prepareShare returns the test-only CKContainer identifier")
    func returnsTestContainer() async throws {
        let stub = StubHouseholdSharingService()
        let (_, container) = try await stub.prepareShare(for: UUID())
        let expected = StubHouseholdSharingService.stubContainerIdentifier
        #expect(container.containerIdentifier == expected)
    }
}
