import CloudKit
import CoreData

/// Protocol seam over the share-acceptance step. Mirrors
/// `HouseholdSharingService` (the matching protocol over share
/// preparation) so app-layer callers can hold `any ShareAcceptanceService`
/// and unit tests can substitute a stub conformer without touching
/// CloudKit. Issue #105.
public protocol ShareAcceptanceService: Sendable {
    /// Imports the shared records described by `metadata` into the
    /// container's shared store. Implementations throw on the
    /// shared-store-unavailable case (single-store containers, tests)
    /// and on Core Data + CloudKit-level rejection (network issues,
    /// revoked invites, partial-failure imports).
    func acceptShare(metadata: CKShare.Metadata) async throws
}

/// Wraps `NSPersistentCloudKitContainer.acceptShareInvitations(from:into:completion:)`
/// — the API the recipient calls when they tap an iCloud share invite.
/// Phase 3.2 surfaces this through the app delegate's
/// `application(_:userDidAcceptCloudKitShareWith:)`, which is the
/// canonical hook for SwiftUI apps via `UIApplicationDelegateAdaptor`.
///
/// Records land in the shared store. Phase 3.3 routes new writes to
/// the right store (private vs shared) based on the active household's
/// ownership.
///
/// Conforms to `ShareAcceptanceService` (issue #105) so the app-layer
/// `ShareAcceptanceCoordinator` can hold `any ShareAcceptanceService`
/// and tests can drop in a stub.
public final class CloudShareAcceptance: ShareAcceptanceService, @unchecked Sendable {
    private let container: NSPersistentCloudKitContainer

    public init(container: NSPersistentCloudKitContainer) {
        self.container = container
    }

    /// Imports the shared records described by `metadata` into the
    /// container's shared store. Throws if the shared store isn't
    /// loaded (single-store container, in-memory tests) or if Core
    /// Data + CloudKit reject the invitation.
    public func acceptShare(metadata: CKShare.Metadata) async throws {
        let sharedStore = try resolveSharedStore()
        _ = try await container.acceptShareInvitations(
            from: [metadata],
            into: sharedStore
        )
    }

    /// `internal` so `CloudShareAcceptanceTests` can pin the
    /// shared-store-unavailable contract without needing to construct a
    /// `CKShare.Metadata` (which has no public initializer for tests
    /// to reach). Issue #105: splitting the gate from the
    /// `acceptShareInvitations` call makes the failure-path tests
    /// purely about Core Data wiring rather than CloudKit, which is
    /// the only branch we can drive in CI without an iCloud account.
    internal func resolveSharedStore() throws -> NSPersistentStore {
        guard let store = CoreDataStack.sharedCloudKitStore(in: container) else {
            throw CloudShareAcceptanceError.sharedStoreUnavailable
        }
        return store
    }
}

public enum CloudShareAcceptanceError: Error {
    case sharedStoreUnavailable
}
