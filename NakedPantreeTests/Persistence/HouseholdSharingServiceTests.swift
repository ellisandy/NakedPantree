import CloudKit
import CoreData
import Foundation
import Testing

@testable import NakedPantreeDomain
@testable import NakedPantreePersistence

/// Unit-level coverage for the share-preparation path. Phase 3 sharing
/// shipped without any automated coverage — see `SharingUITests` for
/// the UI-level smoke test. These exercise the parts of
/// `CloudHouseholdSharingService` that don't require an actual iCloud
/// account, plus the `StubHouseholdSharingService` used by the UI test.
@Suite("Household sharing service")
struct HouseholdSharingServiceTests {
    /// Build an `NSPersistentCloudKitContainer` backed by a `/dev/null`
    /// SQLite store *without* a `cloudKitContainerOptions` configured —
    /// the container then behaves as a plain Core Data store and the
    /// lookup branch of `prepareShare` runs end-to-end without the
    /// CloudKit machinery. (We can't drive `share(_:to:)` happy-path
    /// from a unit test — that needs a real iCloud account.)
    private static func makeUnsharedContainer() throws -> NSPersistentCloudKitContainer {
        let container = NSPersistentCloudKitContainer(
            name: "NakedPantree",
            managedObjectModel: CoreDataStack.model
        )
        let description = NSPersistentStoreDescription()
        description.type = NSSQLiteStoreType
        description.url = URL(fileURLWithPath: "/dev/null")
        description.shouldAddStoreAsynchronously = false
        // Explicitly nil — without this the description picks up the
        // default CloudKit options and the test simulator (no iCloud)
        // fails to load the store.
        description.cloudKitContainerOptions = nil
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            throw loadError
        }
        container.viewContext.mergePolicy = CoreDataStack.defaultMergePolicy
        return container
    }

    private static func insertHousehold(
        id: UUID,
        into container: NSPersistentContainer
    ) throws {
        let context = container.viewContext
        let row = NSEntityDescription.insertNewObject(
            forEntityName: "HouseholdEntity",
            into: context
        )
        row.setValue(id, forKey: "id")
        row.setValue("Test Pantry", forKey: "name")
        row.setValue(Date(), forKey: "createdAt")
        try context.save()
    }

    @Test("prepareShare throws householdNotFound when row is absent")
    func householdNotFoundError() async throws {
        let container = try Self.makeUnsharedContainer()
        let service = CloudHouseholdSharingService(
            container: container,
            cloudKitContainer: CKContainer(identifier: "iCloud.cc.mnmlst.nakedpantree.test")
        )
        // Random UUID — guaranteed not in the empty store.
        let unknownID = UUID()
        await #expect(throws: HouseholdSharingError.householdNotFound) {
            _ = try await service.prepareShare(for: unknownID)
        }
    }

    @Test("CloudHouseholdSharingService conforms to HouseholdSharingService")
    func conformance() throws {
        let container = try Self.makeUnsharedContainer()
        let service = CloudHouseholdSharingService(
            container: container,
            cloudKitContainer: CKContainer(identifier: "iCloud.cc.mnmlst.nakedpantree.test")
        )
        // Compile-time assertion — if this fails to type-check the
        // protocol seam is broken.
        let _: any HouseholdSharingService = service
    }
}
