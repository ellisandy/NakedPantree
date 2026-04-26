import CloudKit
import CoreData
import Foundation

/// Loads the compiled `NakedPantree` Core Data model from this package's
/// resource bundle and stands up Core Data containers. Phase 1 used a
/// plain `NSPersistentContainer`; Phase 2 introduces
/// `cloudKitContainer(name:)` (the production stack) — see `ARCHITECTURE.md` §5.
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

    /// Default CloudKit container identifier. Must match the
    /// `com.apple.developer.icloud-container-identifiers` entry in
    /// `NakedPantree.entitlements` and the container provisioned in
    /// the developer portal (see issue #23).
    public static let cloudKitContainerIdentifier = "iCloud.cc.mnmlst.nakedpantree"

    /// Creates a disk-backed local-only container — SQLite at the OS-default
    /// location (Application Support / `<name>.sqlite`). Used by tests and
    /// any future tool that needs Core Data without iCloud.
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
        container.viewContext.mergePolicy = defaultMergePolicy
        return container
    }

    /// Creates the production CloudKit-mirrored container with two stores:
    ///
    /// - `private.sqlite` mirrors `CKContainer.privateCloudDatabase`.
    /// - `shared.sqlite`  mirrors `CKContainer.sharedCloudDatabase`. Wired
    ///   in Phase 2 ahead of Phase 3 sharing — no records land here yet.
    ///
    /// History tracking and remote-change notifications are enabled on both
    /// stores: `NSPersistentCloudKitContainer` requires the former to mirror,
    /// and the Phase 2.2 view-refresh observer needs the latter. The merge
    /// policy is set on the coordinator so background contexts inherit it
    /// without each repository having to remember.
    ///
    /// Both stores live in the OS-default Application Support directory.
    public static func cloudKitContainer(
        name: String = "NakedPantree",
        containerIdentifier: String = cloudKitContainerIdentifier
    ) -> NSPersistentCloudKitContainer {
        let container = NSPersistentCloudKitContainer(name: name, managedObjectModel: model)

        let storeDirectory = NSPersistentContainer.defaultDirectoryURL()
        let privateStoreURL = storeDirectory.appendingPathComponent("\(name)-private.sqlite")
        let sharedStoreURL = storeDirectory.appendingPathComponent("\(name)-shared.sqlite")

        let privateDescription = makeDescription(
            url: privateStoreURL,
            containerIdentifier: containerIdentifier,
            scope: .private
        )
        let sharedDescription = makeDescription(
            url: sharedStoreURL,
            containerIdentifier: containerIdentifier,
            scope: .shared
        )

        container.persistentStoreDescriptions = [privateDescription, sharedDescription]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            if let error { loadError = error }
        }
        if let loadError {
            fatalError("CloudKit persistent stores failed to load: \(loadError)")
        }

        container.viewContext.mergePolicy = defaultMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true

        return container
    }

    /// Returns the private CloudKit-backed store on a multi-store container,
    /// or `nil` for single-store containers (tests, previews). Repositories
    /// call `context.assign(_:to:)` with this when inserting new objects so
    /// they land in the user's private database, not the shared one.
    public static func privateCloudKitStore(
        in container: NSPersistentContainer
    ) -> NSPersistentStore? {
        container.persistentStoreCoordinator.persistentStores.first { store in
            store.url?.lastPathComponent.contains("-private.sqlite") == true
        }
    }

    /// Returns the shared CloudKit-backed store on a multi-store container,
    /// or `nil` for single-store containers. `acceptShareInvitations`
    /// from `CloudShareAcceptance` lands shared records here when a
    /// recipient accepts an invite.
    public static func sharedCloudKitStore(
        in container: NSPersistentContainer
    ) -> NSPersistentStore? {
        container.persistentStoreCoordinator.persistentStores.first { store in
            store.url?.lastPathComponent.contains("-shared.sqlite") == true
        }
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
        container.viewContext.mergePolicy = defaultMergePolicy
        return container
    }

    /// Project-standard merge policy. Last write wins, per attribute. See
    /// `ARCHITECTURE.md` §5 conflict resolution for the rationale.
    public static var defaultMergePolicy: NSMergePolicy {
        NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
    }

    private static func makeDescription(
        url: URL,
        containerIdentifier: String,
        scope: CKDatabase.Scope
    ) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        // History tracking is required for CloudKit mirroring; the remote-
        // change key drives the Phase 2.2 view-refresh observer.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )

        let options = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
        options.databaseScope = scope
        description.cloudKitContainerOptions = options
        return description
    }
}
