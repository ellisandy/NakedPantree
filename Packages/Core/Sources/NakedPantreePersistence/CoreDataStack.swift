import CoreData
import Foundation

/// Loads the compiled `NakedPantree` Core Data model from this package's
/// resource bundle and stands up an `NSPersistentContainer`. Phase 1 is
/// local-only — `NSPersistentCloudKitContainer` arrives in Phase 2 (see
/// `ROADMAP.md` and `ARCHITECTURE.md` §5).
public enum CoreDataStack {
    /// Loaded once and reused — `NSManagedObjectModel` instances are
    /// expensive and Core Data warns when the same model is registered
    /// twice for different stores. `NSManagedObjectModel` is not `Sendable`
    /// in the SDK, but Core Data treats a model as immutable after the
    /// first store opens — `nonisolated(unsafe)` is the documented
    /// workaround for that mismatch.
    nonisolated(unsafe) public static let model: NSManagedObjectModel = {
        guard
            let url = Bundle.module.url(
                forResource: "NakedPantree",
                withExtension: "momd"
            ),
            let model = NSManagedObjectModel(contentsOf: url)
        else {
            fatalError("NakedPantree.momd not found in package bundle")
        }
        return model
    }()

    /// Creates a disk-backed container — SQLite at the OS-default location
    /// (Application Support / `<name>.sqlite`). Lightweight migration is
    /// enabled in advance of Phase 2 and any later schema bumps; until
    /// then there's nothing to migrate.
    public static func persistentContainer(name: String = "NakedPantree") -> NSPersistentContainer {
        let container = NSPersistentContainer(name: name, managedObjectModel: model)
        if let description = container.persistentStoreDescriptions.first {
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            fatalError("Persistent store failed to load: \(loadError)")
        }
        container.viewContext.mergePolicy = NSMergePolicy(
            merge: .mergeByPropertyObjectTrumpMergePolicyType
        )
        return container
    }

    /// Creates an in-memory container — the SQLite store is bound to
    /// `/dev/null`, so nothing reaches disk. Used for tests and SwiftUI
    /// previews. Each call returns a fresh container with an empty store.
    public static func inMemoryContainer(name: String = "NakedPantree") -> NSPersistentContainer {
        let container = NSPersistentContainer(name: name, managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            fatalError("In-memory store failed to load: \(loadError)")
        }
        container.viewContext.mergePolicy = NSMergePolicy(
            merge: .mergeByPropertyObjectTrumpMergePolicyType
        )
        return container
    }
}
