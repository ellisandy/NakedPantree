import CoreData
import Foundation

@testable import NakedPantreePersistence

/// Test fixture mirroring the production two-store layout
/// (`<name>-private.sqlite` + `<name>-shared.sqlite`) without
/// requiring a real iCloud account. Issue #111.
///
/// Why this exists: `CoreDataStack.cloudKitContainer(...)` (the
/// production stack) sets up two `NSPersistentStoreDescription`s with
/// `cloudKitContainerOptions` configured for `.private` and `.shared`
/// scopes. Repository code (`CoreDataLocationRepository.assignToParentStore`,
/// `CoreDataItemRepository.assignToParentStore`,
/// `CoreDataItemPhotoRepository.assignToParentStore`) and
/// `HouseholdRepository.currentHousehold`'s shared-store-preferred
/// branch all depend on the two stores being distinguishable by URL
/// pattern via `CoreDataStack.privateCloudKitStore(in:)` /
/// `CoreDataStack.sharedCloudKitStore(in:)`. None of that surface
/// area was reachable from the existing single-store
/// `inMemoryContainer()` test fixture.
///
/// Strategy: real SQLite files in a per-instance unique directory
/// under `NSTemporaryDirectory()`. The filenames carry the
/// `-private.sqlite` / `-shared.sqlite` suffixes the production
/// helpers key off, so a fixture-backed `NSPersistentCloudKitContainer`
/// looks identical to the production stack from the repositories'
/// point of view. `cloudKitContainerOptions` is left `nil` so the
/// framework doesn't try to mirror against a non-existent iCloud
/// account; locally-saved data still routes correctly between
/// stores.
///
/// Cleanup happens via `cleanup()` (call from a Swift Testing
/// `@Test`'s `defer` or a tear-down block) or implicitly at process
/// exit if the test runner crashes — `NSTemporaryDirectory()` is
/// system-cleared.
final class MultiStoreFixture {
    let container: NSPersistentCloudKitContainer
    private let baseDirectory: URL

    init(name: String = "NakedPantree") throws {
        let unique = UUID().uuidString
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nakedpantree-multi-store-\(unique)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        self.baseDirectory = directory

        let privateURL = directory.appendingPathComponent("\(name)-private.sqlite")
        let sharedURL = directory.appendingPathComponent("\(name)-shared.sqlite")

        let container = NSPersistentCloudKitContainer(
            name: name,
            managedObjectModel: CoreDataStack.model
        )
        container.persistentStoreDescriptions = [
            Self.makeDescription(url: privateURL),
            Self.makeDescription(url: sharedURL),
        ]

        var loadErrors: [Error] = []
        container.loadPersistentStores { _, error in
            if let error { loadErrors.append(error) }
        }
        if let firstError = loadErrors.first {
            throw firstError
        }

        container.viewContext.mergePolicy = CoreDataStack.defaultMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
        self.container = container
    }

    /// Removes the fixture's per-instance directory. Idempotent.
    /// Call from a `defer` block at the top of each test that uses
    /// the fixture so files don't accumulate across runs.
    func cleanup() {
        try? FileManager.default.removeItem(at: baseDirectory)
    }

    /// `NSPersistentStoreDescription` configured the same way the
    /// production stack does (`CoreDataStack.makeDescription(...)`),
    /// minus `cloudKitContainerOptions` — the test fixture is
    /// local-only.
    private static func makeDescription(url: URL) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.shouldAddStoreAsynchronously = false
        description.setOption(
            true as NSNumber,
            forKey: NSPersistentHistoryTrackingKey
        )
        description.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )
        return description
    }
}
