import CloudKit
import CoreData
import Foundation
import Testing

@testable import NakedPantreeDomain
@testable import NakedPantreePersistence

/// Unit-level coverage for the share-preparation path. See
/// `SharingUITests` for the UI smoke test against
/// `UICloudSharingController` and `StubHouseholdSharingServiceTests`
/// for stub-output assertions. These exercise the parts of the
/// production `CloudHouseholdSharingService` that don't require a
/// real iCloud account to round-trip — primarily, the lookup branch
/// of `prepareShare`, which throws before any CloudKit API call.
///
/// History: this file was trimmed to a compile-time conformance
/// check in apps#99 because the runtime test below hung
/// `NSPersistentCloudKitContainer.performBackgroundTask` for ~28s on
/// the unsigned simulator binary (CK pre-flight requires
/// `com.apple.developer.icloud-services`). apps#101 fixed that by
/// signing the test binary in CI with the same cert + profile the
/// TestFlight workflow uses, so the test below runs again.
@Suite("Household sharing service")
struct HouseholdSharingServiceTests {
    /// Build an `NSPersistentCloudKitContainer` backed by a `/dev/null`
    /// SQLite store *without* a `cloudKitContainerOptions` configured —
    /// the container then behaves as a plain Core Data store and the
    /// lookup branch of `prepareShare` runs end-to-end without a real
    /// iCloud account. (We can't drive `share(_:to:)`'s happy path
    /// from a unit test even with signing — that needs an iCloud
    /// account, which CI doesn't have. See DEVELOPMENT.md §6.)
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
        // default CloudKit options and a CI runner without iCloud
        // can fail to load the store.
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

    @Test("prepareShare throws householdNotFound when row is absent")
    func householdNotFoundError() async throws {
        let container = try Self.makeUnsharedContainer()
        let service = CloudHouseholdSharingService(
            container: container,
            cloudKitContainer: CKContainer(identifier: "iCloud.cc.mnmlst.nakedpantree.test")
        )
        // Random UUID — guaranteed not in the empty store. The lookup
        // throws before any CloudKit API call, so this works without
        // an iCloud account.
        let unknownID = UUID()
        await #expect(throws: HouseholdSharingError.householdNotFound) {
            _ = try await service.prepareShare(for: unknownID)
        }
    }

    @Test("prepareShare lookup → share-call path is queue-safe (#107)")
    func prepareShareCrossQueueSafety() async throws {
        let container = try Self.makeUnsharedContainer()

        // Insert a household so the lookup succeeds and the code reaches
        // the new-share branch (no CKShare exists for this objectID, so
        // existingShare returns nil; the call proceeds to share(_:to:)).
        let householdID = UUID()
        let context = container.viewContext
        let row = NSEntityDescription.insertNewObject(
            forEntityName: "HouseholdEntity",
            into: context
        )
        row.setValue(householdID, forKey: "id")
        row.setValue("Test Pantry", forKey: "name")
        row.setValue(Date(), forKey: "createdAt")
        try context.save()

        let service = CloudHouseholdSharingService(
            container: container,
            cloudKitContainer: CKContainer(identifier: "iCloud.cc.mnmlst.nakedpantree.test")
        )

        // Without iCloud and without `cloudKitContainerOptions`, the
        // `share(_:to:)` call will throw. The point of this test is the
        // path FROM objectID lookup TO share-call does not crash with a
        // multithreading violation (the pre-#107 bug — an NSManagedObject
        // was returned out of `performBackgroundTask` and then accessed
        // off-queue). Either a throw or a successful return both satisfy
        // the regression — what we're guarding against is `EXC_BAD_ACCESS`
        // / `_AllThatIsLeftToUsIsHonor`.
        _ = try? await service.prepareShare(for: householdID)
    }

    @Test("CloudHouseholdSharingService conforms to HouseholdSharingService")
    func conformance() throws {
        // Compile-time assertion — if this fails to type-check the
        // protocol seam is broken.
        let metatype: any HouseholdSharingService.Type = CloudHouseholdSharingService.self
        _ = metatype
    }
}
