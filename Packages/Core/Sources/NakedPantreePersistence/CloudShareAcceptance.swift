import CloudKit
import CoreData

/// Wraps `NSPersistentCloudKitContainer.acceptShareInvitations(from:into:completion:)`
/// — the API the recipient calls when they tap an iCloud share invite.
/// Phase 3.2 surfaces this through the app delegate's
/// `application(_:userDidAcceptCloudKitShareWith:)`, which is the
/// canonical hook for SwiftUI apps via `UIApplicationDelegateAdaptor`.
///
/// Records land in the shared store. Phase 3.3 routes new writes to
/// the right store (private vs shared) based on the active household's
/// ownership.
public final class CloudShareAcceptance: @unchecked Sendable {
    private let container: NSPersistentCloudKitContainer

    public init(container: NSPersistentCloudKitContainer) {
        self.container = container
    }

    /// Imports the shared records described by `metadata` into the
    /// container's shared store. Throws if the shared store isn't
    /// loaded (single-store container, in-memory tests) or if Core
    /// Data + CloudKit reject the invitation.
    public func acceptShare(metadata: CKShare.Metadata) async throws {
        guard let sharedStore = CoreDataStack.sharedCloudKitStore(in: container) else {
            throw CloudShareAcceptanceError.sharedStoreUnavailable
        }
        _ = try await container.acceptShareInvitations(
            from: [metadata],
            into: sharedStore
        )
    }
}

public enum CloudShareAcceptanceError: Error {
    case sharedStoreUnavailable
}
