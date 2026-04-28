import CloudKit
import CoreData
import NakedPantreeDomain
import os

/// Vends a `CKShare` rooted at a `Household` row, plus the `CKContainer`
/// that owns it — exactly what `UICloudSharingController(preparationHandler:)`
/// needs to invite participants. Phase 3.1 is the create + present flow;
/// 3.2 wires up acceptance, 3.3 routes writes between private and shared
/// stores.
///
/// **Why this isn't behind a Domain protocol:** `CKShare` and
/// `CKContainer` are CloudKit types — useless to a hypothetical macOS
/// CLI consumer that doesn't sync. Lifting behind a protocol now would
/// be premature indirection. If a non-iOS surface ever needs to invite
/// participants, that's the moment to abstract.
public final class CloudHouseholdSharingService: @unchecked Sendable {
    private let container: NSPersistentCloudKitContainer
    private let cloudKitContainer: CKContainer

    /// Step-by-step trace of `prepareShare` — visible via Console.app
    /// filtered by subsystem `cc.mnmlst.nakedpantree`, category
    /// `sharing`. Added while diagnosing #90 (blank Share Household
    /// sheet on TestFlight). Keep until that issue is fully closed
    /// and the failure mode is documented in DEVELOPMENT.md §7; then
    /// trim back to whatever turned out to be load-bearing.
    private static let logger = Logger(
        subsystem: "cc.mnmlst.nakedpantree",
        category: "sharing"
    )

    public init(
        container: NSPersistentCloudKitContainer,
        cloudKitContainer: CKContainer
    ) {
        self.container = container
        self.cloudKitContainer = cloudKitContainer
    }

    /// Look up an existing share rooted at `householdID`, or create one
    /// if none exists yet. Returns the `CKShare` plus the originating
    /// `CKContainer` so the caller can hand both to
    /// `UICloudSharingController`.
    ///
    /// Throws if the household row doesn't exist or if Core Data can't
    /// produce a share (e.g. the user isn't signed into iCloud — which
    /// the account-status banner already covers, but the throw is the
    /// last line of defense).
    public func prepareShare(
        for householdID: Household.ID
    ) async throws -> (CKShare, CKContainer) {
        Self.logger.info("prepareShare start: \(householdID, privacy: .public)")
        let object = try await householdManagedObject(for: householdID)
        Self.logger.info("got household managed object")
        let share: CKShare
        if let existing = try existingShare(for: object) {
            Self.logger.info("returning existing share")
            share = existing
        } else {
            Self.logger.info("calling NSPersistentCloudKitContainer.share")
            // `share(_:to:)` returns `(Set<NSManagedObject>, CKShare, CKContainer)`.
            // We only want the share — the modified objects are already
            // persisted by the API, and the container is the same one
            // the caller injected.
            let result = try await container.share([object], to: nil)
            Self.logger.info("container.share returned a new CKShare")
            share = result.1
        }
        share[CKShare.SystemFieldKey.title] = "Naked Pantree"
        Self.logger.info("prepareShare complete")
        return (share, cloudKitContainer)
    }

    /// Resolves the household domain id to its `NSManagedObject` on a
    /// fresh background context. Lookup-only — the object is read on
    /// the background queue and the resulting `objectID` is what
    /// `share(_:to:)` consumes.
    private func householdManagedObject(
        for householdID: Household.ID
    ) async throws -> NSManagedObject {
        try await container.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "HouseholdEntity")
            request.predicate = NSPredicate(format: "id == %@", householdID as CVarArg)
            request.fetchLimit = 1
            guard let object = try context.fetch(request).first else {
                throw HouseholdSharingError.householdNotFound
            }
            return object
        }
    }

    /// Returns the existing `CKShare` for `object`, or `nil` if none
    /// exists yet. `fetchShares(matching:)` is the documented Core Data
    /// API for asking "is this row already shared?"
    private func existingShare(for object: NSManagedObject) throws -> CKShare? {
        let shares = try container.fetchShares(matching: [object.objectID])
        return shares[object.objectID]
    }
}

public enum HouseholdSharingError: Error {
    case householdNotFound
}
