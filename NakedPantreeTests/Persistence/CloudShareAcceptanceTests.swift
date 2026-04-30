import CloudKit
import CoreData
import Foundation
import Testing

@testable import NakedPantreePersistence

/// Issue #105: pin the documented failure-mode contract on
/// `CloudShareAcceptance` that the production app relies on.
///
/// **What we test here**: the `sharedStoreUnavailable` branch — the
/// only `CloudShareAcceptance` code path reachable in CI without an
/// iCloud account. The happy path and CK-side failures (network,
/// revoked invite, partial-failure import) require a live iCloud
/// account to drive `acceptShareInvitations(from:into:)` and so live
/// in `ShareAcceptanceCoordinatorTests` against a stub conformer
/// instead.
///
/// The test calls into `resolveSharedStore()` (`internal` for exactly
/// this reason) rather than `acceptShare(metadata:)` — that lets the
/// throw be exercised without constructing a `CKShare.Metadata`, which
/// has no public initializer for tests to reach.
@Suite("CloudShareAcceptance")
struct CloudShareAcceptanceTests {
    /// Builds a single-store SQLite container backed by `/dev/null` —
    /// matches the pattern in `HouseholdSharingServiceTests`. Returns
    /// without attaching `cloudKitContainerOptions`, so the container
    /// has neither a `-private.sqlite` nor a `-shared.sqlite` URL and
    /// `CoreDataStack.sharedCloudKitStore(in:)` returns nil. This is
    /// the exact code path that fires when `CloudShareAcceptance` is
    /// constructed in a test or preview surface that didn't load a
    /// shared store — the contract under test is "throw, don't
    /// silently accept".
    private static func makeSingleStoreContainer() throws -> NSPersistentCloudKitContainer {
        let container = NSPersistentCloudKitContainer(
            name: "NakedPantree",
            managedObjectModel: CoreDataStack.model
        )
        let description = NSPersistentStoreDescription()
        description.type = NSSQLiteStoreType
        description.url = URL(fileURLWithPath: "/dev/null")
        description.shouldAddStoreAsynchronously = false
        description.cloudKitContainerOptions = nil
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            throw loadError
        }
        return container
    }

    @Test("resolveSharedStore throws sharedStoreUnavailable on a single-store container")
    func sharedStoreUnavailable() throws {
        let container = try Self.makeSingleStoreContainer()
        let acceptance = CloudShareAcceptance(container: container)
        // The single-store container has no `-shared.sqlite` URL, so
        // `sharedCloudKitStore(in:)` returns nil and the gate throws.
        // Tests that drive the happy path live in
        // `ShareAcceptanceCoordinatorTests` — Apple's
        // `acceptShareInvitations(from:into:)` requires an actual
        // iCloud account, which CI doesn't have.
        #expect(throws: CloudShareAcceptanceError.sharedStoreUnavailable) {
            _ = try acceptance.resolveSharedStore()
        }
    }

    @Test("CloudShareAcceptance conforms to ShareAcceptanceService")
    func conformance() {
        // Compile-time check: if the protocol seam breaks, this test
        // fails to type-check. Mirrors the pattern in
        // `HouseholdSharingServiceTests.conformance`.
        let metatype: any ShareAcceptanceService.Type = CloudShareAcceptance.self
        _ = metatype
    }
}
