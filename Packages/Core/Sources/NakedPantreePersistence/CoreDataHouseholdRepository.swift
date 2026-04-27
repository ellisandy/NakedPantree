import CoreData
import Foundation
import NakedPantreeDomain

/// `HouseholdRepository` backed by `NSPersistentContainer`. All work runs
/// inside `performBackgroundTask`, never letting an `NSManagedObject` cross
/// the async boundary — repositories surface only domain value types.
///
/// `NSPersistentContainer` is not `Sendable` in the SDK; we mark this class
/// `@unchecked Sendable` because the container is only ever reached from
/// inside `performBackgroundTask`, which serializes access on its own
/// queue. See `CoreDataStack.swift` for the same trade-off on the model.
///
/// **Phase 3 sharing:** `currentHousehold()` prefers a household from the
/// shared store over one in the private store, so a recipient who accepts
/// a share lands on the shared household directly.
/// `ensurePrivateHousehold()` is the explicit private-only variant.
public final class CoreDataHouseholdRepository: HouseholdRepository, @unchecked Sendable {
    private let container: NSPersistentContainer

    public init(container: NSPersistentContainer) {
        self.container = container
    }

    public func currentHousehold() async throws -> Household {
        try await container.performBackgroundTaskWithDefaults { [container] context in
            // Prefer a shared-store household — if the user accepted an
            // invite, that's the one they want to see.
            if let sharedStore = CoreDataStack.sharedCloudKitStore(in: container),
                let shared = try Self.fetchHouseholdRow(
                    inStore: sharedStore,
                    in: context
                )
            {
                return Self.makeHousehold(from: shared)
            }
            // Fall back to the private household, creating one on
            // first launch.
            return try Self.fetchOrCreatePrivateHousehold(
                in: context,
                container: container
            )
        }
    }

    public func ensurePrivateHousehold() async throws -> Household {
        try await container.performBackgroundTaskWithDefaults { [container] context in
            try Self.fetchOrCreatePrivateHousehold(
                in: context,
                container: container
            )
        }
    }

    public func existingPrivateHousehold() async throws -> Household? {
        try await container.performBackgroundTaskWithDefaults { [container] context in
            let privateStore = CoreDataStack.privateCloudKitStore(in: container)
            if let privateStore,
                let existing = try Self.fetchHouseholdRow(inStore: privateStore, in: context)
            {
                return Self.makeHousehold(from: existing)
            } else if privateStore == nil,
                let existing = try Self.fetchHouseholdRow(in: context)
            {
                // Single-store containers (in-memory tests) — no store
                // scoping, mirror `fetchOrCreatePrivateHousehold`'s fallback.
                return Self.makeHousehold(from: existing)
            }
            return nil
        }
    }

    public func update(_ household: Household) async throws {
        try await container.performBackgroundTaskWithDefaults { [container] context in
            let row: NSManagedObject
            if let existing = try Self.fetchHouseholdRow(id: household.id, in: context) {
                row = existing
            } else {
                row = NSEntityDescription.insertNewObject(
                    forEntityName: "HouseholdEntity",
                    into: context
                )
                if let privateStore = CoreDataStack.privateCloudKitStore(in: container) {
                    context.assign(row, to: privateStore)
                }
            }
            row.setValue(household.id, forKey: "id")
            row.setValue(household.name, forKey: "name")
            row.setValue(household.createdAt, forKey: "createdAt")
            try context.save()
        }
    }

    private static func fetchOrCreatePrivateHousehold(
        in context: NSManagedObjectContext,
        container: NSPersistentContainer
    ) throws -> Household {
        let privateStore = CoreDataStack.privateCloudKitStore(in: container)
        if let privateStore,
            let existing = try fetchHouseholdRow(inStore: privateStore, in: context)
        {
            return makeHousehold(from: existing)
        } else if privateStore == nil,
            let existing = try fetchHouseholdRow(in: context)
        {
            // Single-store containers (in-memory tests) — no store
            // scoping, just return whatever's there.
            return makeHousehold(from: existing)
        }
        let row = NSEntityDescription.insertNewObject(
            forEntityName: "HouseholdEntity",
            into: context
        )
        if let privateStore {
            context.assign(row, to: privateStore)
        }
        let household = Household()
        row.setValue(household.id, forKey: "id")
        row.setValue(household.name, forKey: "name")
        row.setValue(household.createdAt, forKey: "createdAt")
        try context.save()
        return household
    }

    /// Unscoped fetch — used by single-store containers (tests / previews)
    /// where there's no private vs shared distinction.
    private static func fetchHouseholdRow(
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "HouseholdEntity")
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return try context.fetch(request).first
    }

    /// Store-scoped fetch — `affectedStores` limits the query to a
    /// single `NSPersistentStore` so we don't accidentally return a
    /// shared household from a "private only" path or vice versa.
    private static func fetchHouseholdRow(
        inStore store: NSPersistentStore,
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "HouseholdEntity")
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        request.affectedStores = [store]
        return try context.fetch(request).first
    }

    private static func fetchHouseholdRow(
        id: Household.ID,
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "HouseholdEntity")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private static func makeHousehold(from row: NSManagedObject) -> Household {
        Household(
            id: row.value(forKey: "id") as? UUID ?? UUID(),
            name: row.value(forKey: "name") as? String ?? "My Pantry",
            createdAt: row.value(forKey: "createdAt") as? Date ?? Date()
        )
    }
}
