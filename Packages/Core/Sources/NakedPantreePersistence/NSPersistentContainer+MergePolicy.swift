import CoreData

extension NSPersistentContainer {
    /// `performBackgroundTask` creates fresh contexts whose default merge
    /// policy is `NSErrorMergePolicy` — they don't inherit the policy set
    /// on `viewContext`. This wrapper applies `CoreDataStack.defaultMergePolicy`
    /// before the caller's block runs, which matters once
    /// `NSPersistentCloudKitContainer`'s mirror starts saving to the same
    /// store concurrently with local writes.
    ///
    /// **Self-emission filtering (issue #28):** every background context is
    /// also stamped with `transactionAuthor = "local"`. The Phase 2.2
    /// `RemoteChangeMonitor` reads persistent history after each
    /// `NSPersistentStoreRemoteChange` notification and filters out
    /// transactions whose author is `"local"` — that's how it tells a
    /// local save (which should not trigger a reload, since the form
    /// callback already kicked one off) apart from a CloudKit-mirrored
    /// import (which has a nil author and should reload).
    func performBackgroundTaskWithDefaults<T: Sendable>(
        _ block: @Sendable @escaping (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        try await performBackgroundTask { context in
            context.mergePolicy = CoreDataStack.defaultMergePolicy
            context.transactionAuthor = CoreDataStack.localTransactionAuthor
            return try block(context)
        }
    }
}
