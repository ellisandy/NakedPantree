import CoreData

extension NSPersistentContainer {
    /// `performBackgroundTask` creates fresh contexts whose default merge
    /// policy is `NSErrorMergePolicy` — they don't inherit the policy set
    /// on `viewContext`. This wrapper applies `CoreDataStack.defaultMergePolicy`
    /// before the caller's block runs, which matters once
    /// `NSPersistentCloudKitContainer`'s mirror starts saving to the same
    /// store concurrently with local writes.
    func performBackgroundTaskWithDefaults<T: Sendable>(
        _ block: @Sendable @escaping (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        try await performBackgroundTask { context in
            context.mergePolicy = CoreDataStack.defaultMergePolicy
            return try block(context)
        }
    }
}
