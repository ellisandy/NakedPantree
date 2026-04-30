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

    /// Author label stamped onto every background context vended by
    /// `performBackgroundTaskWithDefaults`. The Phase 2.2 remote-change
    /// observer (issue #28) uses this to skip self-emitted notifications:
    /// transactions whose `author == "local"` were our own save and the
    /// form callback already triggered an explicit reload, so the token
    /// should only bump when a transaction with a different author
    /// (CloudKit-mirrored imports leave `author` nil) shows up in
    /// persistent history.
    public static let localTransactionAuthor = "local"

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
    ///
    /// **Issue #106:** the load failure used to call `fatalError`, crashing
    /// the app on every cold start when a user hit a corrupt SQLite or a
    /// failed automatic mapping-model inference (which `shouldMigrate…` +
    /// `shouldInferMappingModel…` can produce on dev-untested edge cases).
    /// Now the function throws `CoreDataStackError.storeLoadFailed`; the
    /// caller (`AppLauncher`) catches and routes the user into a recovery
    /// surface with retry + iCloud-gated reset options.
    public static func cloudKitContainer(
        name: String = "NakedPantree",
        containerIdentifier: String = cloudKitContainerIdentifier
    ) throws -> NSPersistentCloudKitContainer {
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
            throw CoreDataStackError.storeLoadFailed(underlying: loadError)
        }

        container.viewContext.mergePolicy = defaultMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true

        return container
    }

    /// File URLs of the on-disk SQLite stores plus their sidecar files
    /// (`-shm`, `-wal`). Issue #106: `AppLauncher.resetAndRetry` deletes
    /// these before re-attempting load. Exposed `public` so the launcher
    /// (in the app target) can call into it without knowing the
    /// per-store filename convention.
    public static func cloudKitStoreFileURLs(
        name: String = "NakedPantree"
    ) -> [URL] {
        let directory = NSPersistentContainer.defaultDirectoryURL()
        let stems = ["\(name)-private.sqlite", "\(name)-shared.sqlite"]
        let suffixes = ["", "-shm", "-wal"]
        return stems.flatMap { stem in
            suffixes.map { directory.appendingPathComponent(stem + $0) }
        }
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

    /// Creates an ephemeral test container — the SQLite store is bound to
    /// `/dev/null`, so nothing reaches disk. Used for tests and SwiftUI
    /// previews. Each call returns a fresh container with an empty store.
    ///
    /// **Why SQLite at `/dev/null` instead of `NSInMemoryStoreType`:**
    /// `NSPersistentHistoryChangeRequest` (issue #28's
    /// `RemoteChangeMonitor` filtering) is a no-op against in-memory
    /// stores — it returns nil and tests pass spuriously. The
    /// `/dev/null` SQLite trick is Apple's documented test recipe and
    /// has the same "nothing reaches disk" semantics. History tracking
    /// is enabled here so `RemoteChangeMonitorTests` can drive the
    /// real history-fetch code path without needing a CloudKit
    /// container.
    public static func inMemoryContainer(name: String = "NakedPantree") -> NSPersistentContainer {
        let container = NSPersistentContainer(name: name, managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSSQLiteStoreType
        description.url = URL(fileURLWithPath: "/dev/null")
        description.shouldAddStoreAsynchronously = false
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )
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

    /// Errors `cloudKitContainer(...)` can throw. Added in #106 — the
    /// previous failure mode was `fatalError` on store load, crashing
    /// the app with no recovery path. Callers (`AppLauncher`) catch
    /// and route to the recovery surface.
    public enum CoreDataStackError: Error, LocalizedError {
        /// `loadPersistentStores` reported a non-nil error. The wrapped
        /// `Error` is opaque (Core Data domain typically) — surface
        /// `localizedDescription` to users; log the full value for
        /// triage.
        case storeLoadFailed(underlying: Error)

        public var errorDescription: String? {
            switch self {
            case .storeLoadFailed(let underlying):
                return underlying.localizedDescription
            }
        }
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
