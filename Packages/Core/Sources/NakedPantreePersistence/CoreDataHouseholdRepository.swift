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
public final class CoreDataHouseholdRepository: HouseholdRepository, @unchecked Sendable {
    private let container: NSPersistentContainer

    public init(container: NSPersistentContainer) {
        self.container = container
    }

    public func currentHousehold() async throws -> Household {
        try await container.performBackgroundTaskWithDefaults { [container] context in
            if let existing = try Self.fetchHouseholdRow(in: context) {
                return Self.makeHousehold(from: existing)
            }
            let row = NSEntityDescription.insertNewObject(
                forEntityName: "HouseholdEntity",
                into: context
            )
            if let privateStore = CoreDataStack.privateCloudKitStore(in: container) {
                context.assign(row, to: privateStore)
            }
            let household = Household()
            row.setValue(household.id, forKey: "id")
            row.setValue(household.name, forKey: "name")
            row.setValue(household.createdAt, forKey: "createdAt")
            try context.save()
            return household
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

    private static func fetchHouseholdRow(
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "HouseholdEntity")
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
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
