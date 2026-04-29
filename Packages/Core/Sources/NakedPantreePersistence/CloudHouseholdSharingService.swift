import CloudKit
import CoreData
import NakedPantreeDomain
import os

/// Protocol seam over the share-preparation step so SwiftUI surfaces
/// can be exercised without a real iCloud account. The production
/// implementation is `CloudHouseholdSharingService` below; UI tests
/// inject `StubHouseholdSharingService` (in the app target) to drive
/// the Settings → Share Household path on CI without CloudKit.
///
/// Returns CloudKit types directly (`CKShare`, `CKContainer`) — the
/// caller is `UICloudSharingController(preparationHandler:)` which
/// requires both, so abstracting them away just for protocol-purity
/// would force the call site to round-trip back through CloudKit
/// types anyway. The protocol stays in `NakedPantreePersistence`
/// (CloudKit-aware module) for the same reason.
public protocol HouseholdSharingService: Sendable {
    /// Look up an existing share rooted at `householdID`, or create
    /// one if none exists yet. Throws if the household row doesn't
    /// exist or if Core Data / CloudKit can't produce a share.
    func prepareShare(
        for householdID: Household.ID
    ) async throws -> (CKShare, CKContainer)
}

/// Vends a `CKShare` rooted at a `Household` row, plus the `CKContainer`
/// that owns it — exactly what `UICloudSharingController(preparationHandler:)`
/// needs to invite participants. Phase 3.1 is the create + present flow;
/// 3.2 wires up acceptance, 3.3 routes writes between private and shared
/// stores.
///
/// Conforms to `HouseholdSharingService` (above) so SwiftUI can hold
/// `any HouseholdSharingService` and tests can swap in a stub.
public final class CloudHouseholdSharingService: HouseholdSharingService, @unchecked Sendable {
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
        Self.logger.notice("prepareShare start: \(householdID, privacy: .public)")
        // Lookup returns an objectID, not the NSManagedObject itself
        // (issue #107). The previous shape returned an NSManagedObject
        // out of `performBackgroundTask`, leaving its source MOC pinned
        // to a background queue that the caller no longer ran on; any
        // subsequent property access (including the `objectID` read in
        // `existingShare`) was undefined behavior. NSManagedObjectID is
        // documented thread-safe and Sendable-equivalent in practice.
        let objectID = try await householdObjectID(for: householdID)
        Self.logger.notice("got household objectID")

        // `share(_:to:)` returns `(Set<NSManagedObject>, CKShare, CKContainer)`.
        // The third element is the CKContainer the system actually used
        // for the share — even though it has the same identifier as the
        // one we pre-built, `UICloudSharingController` reportedly refuses
        // to render when handed a different `CKContainer` instance than
        // the share was minted in (#90 theory 2). Capture it here for the
        // new-share branch; for the existing-share branch there's no
        // `share(_:to:)` result to extract from, so fall back to the
        // injected `cloudKitContainer`.
        if let existing = try existingShare(matching: objectID) {
            Self.logger.notice("returning existing share")
            existing[CKShare.SystemFieldKey.title] = "Naked Pantree"
            Self.logger.notice("prepareShare complete")
            return (existing, cloudKitContainer)
        }

        Self.logger.notice("calling NSPersistentCloudKitContainer.share")
        // Resolve the object on the viewContext's main queue (Apple's
        // documented sample pattern) and call `share(_:to:)` from the
        // same actor. `share(_:to:)` is internally queue-aware; the
        // only correctness requirement is that the NSManagedObject's
        // source context is alive for the duration of the call.
        // `viewContext` lives for the lifetime of the container, so
        // it is. The `Set<NSManagedObject>` first element of
        // `share(_:to:)`'s return tuple is non-Sendable, so we
        // destructure inside the @MainActor task and return the
        // CKShare + CKContainer (both Sendable).
        let containerRef = container
        let result = try await Task { @MainActor in
            let object = containerRef.viewContext.object(with: objectID)
            let (_, share, resolvedContainer) = try await containerRef.share([object], to: nil)
            return (share, resolvedContainer)
        }.value
        Self.logger.notice("container.share returned a new CKShare")
        let (share, resolvedContainer) = result
        share[CKShare.SystemFieldKey.title] = "Naked Pantree"
        Self.logger.notice("prepareShare complete")
        return (share, resolvedContainer)
    }

    /// Resolves the household domain id to its `NSManagedObjectID` on
    /// a fresh background context. The `NSManagedObject` is consumed
    /// only inside the closure (where it's pinned to the context's
    /// queue), and the `NSManagedObjectID` returned is safe to pass
    /// across queue boundaries.
    private func householdObjectID(
        for householdID: Household.ID
    ) async throws -> NSManagedObjectID {
        try await container.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "HouseholdEntity")
            request.predicate = NSPredicate(format: "id == %@", householdID as CVarArg)
            request.fetchLimit = 1
            guard let object = try context.fetch(request).first else {
                throw HouseholdSharingError.householdNotFound
            }
            return object.objectID
        }
    }

    /// Returns the existing `CKShare` for the given object id, or
    /// `nil` if none exists yet. `fetchShares(matching:)` is the
    /// documented Core Data API for asking "is this row already
    /// shared?" and accepts an `NSManagedObjectID` directly — no
    /// NSManagedObject required.
    private func existingShare(matching objectID: NSManagedObjectID) throws -> CKShare? {
        let shares = try container.fetchShares(matching: [objectID])
        return shares[objectID]
    }
}

public enum HouseholdSharingError: Error {
    case householdNotFound
}
