import CoreData
import Foundation
import NakedPantreeDomain

/// `ItemRepository` backed by `NSPersistentContainer`. Same Sendable
/// trade-off as `CoreDataHouseholdRepository` — see that file.
///
/// `update(_:)` stamps `updatedAt = Date()` before saving, per the
/// protocol contract. The caller's `updatedAt` is overwritten on the way
/// in. `create(_:)` honors the caller-supplied `updatedAt` so seeded
/// fixture data with deterministic timestamps still works.
public final class CoreDataItemRepository: ItemRepository, @unchecked Sendable {
    private let container: NSPersistentContainer

    public init(container: NSPersistentContainer) {
        self.container = container
    }

    public func items(in locationID: Location.ID) async throws -> [Item] {
        try await container.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ItemEntity")
            request.predicate = NSPredicate(format: "location.id == %@", locationID as CVarArg)
            request.sortDescriptors = [
                NSSortDescriptor(key: "createdAt", ascending: true)
            ]
            return try context.fetch(request).map(Self.makeItem)
        }
    }

    public func item(id: Item.ID) async throws -> Item? {
        try await container.performBackgroundTask { context in
            try Self.fetchItemRow(id: id, in: context).map(Self.makeItem)
        }
    }

    public func allItems(in householdID: Household.ID) async throws -> [Item] {
        try await container.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ItemEntity")
            request.predicate = NSPredicate(
                format: "location.household.id == %@",
                householdID as CVarArg
            )
            request.sortDescriptors = [
                NSSortDescriptor(key: "name", ascending: true)
            ]
            return try context.fetch(request).map(Self.makeItem)
        }
    }

    public func search(_ query: String, in householdID: Household.ID) async throws -> [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        return try await container.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ItemEntity")
            request.predicate = NSPredicate(
                format: "location.household.id == %@ AND name CONTAINS[cd] %@",
                householdID as CVarArg,
                trimmed
            )
            request.sortDescriptors = [
                NSSortDescriptor(key: "name", ascending: true)
            ]
            return try context.fetch(request).map(Self.makeItem)
        }
    }

    public func create(_ item: Item) async throws {
        try await container.performBackgroundTask { context in
            let row = NSEntityDescription.insertNewObject(
                forEntityName: "ItemEntity",
                into: context
            )
            try Self.assignAttributes(item, to: row, stampUpdatedAt: false)
            try Self.attachLocation(item.locationID, to: row, in: context)
            try context.save()
        }
    }

    public func update(_ item: Item) async throws {
        try await container.performBackgroundTask { context in
            let row =
                try Self.fetchItemRow(id: item.id, in: context)
                ?? NSEntityDescription.insertNewObject(
                    forEntityName: "ItemEntity",
                    into: context
                )
            try Self.assignAttributes(item, to: row, stampUpdatedAt: true)
            try Self.attachLocation(item.locationID, to: row, in: context)
            try context.save()
        }
    }

    public func delete(id: Item.ID) async throws {
        try await container.performBackgroundTask { context in
            guard let row = try Self.fetchItemRow(id: id, in: context) else { return }
            context.delete(row)
            try context.save()
        }
    }

    private static func assignAttributes(
        _ item: Item,
        to row: NSManagedObject,
        stampUpdatedAt: Bool
    ) throws {
        row.setValue(item.id, forKey: "id")
        row.setValue(item.name, forKey: "name")
        row.setValue(item.quantity, forKey: "quantity")
        row.setValue(item.unit.rawValue, forKey: "unitRaw")
        row.setValue(item.expiresAt, forKey: "expiresAt")
        row.setValue(item.notes, forKey: "notes")
        row.setValue(item.createdAt, forKey: "createdAt")
        row.setValue(stampUpdatedAt ? Date() : item.updatedAt, forKey: "updatedAt")
    }

    /// Mirrors `CoreDataLocationRepository.attachHousehold` — if the
    /// referenced location row doesn't exist yet, we don't insert a
    /// stub. Items must be created against a real location; the
    /// alternative leaves dangling rows on a typo'd `locationID`.
    private static func attachLocation(
        _ locationID: Location.ID,
        to row: NSManagedObject,
        in context: NSManagedObjectContext
    ) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: "LocationEntity")
        request.predicate = NSPredicate(format: "id == %@", locationID as CVarArg)
        request.fetchLimit = 1
        let location = try context.fetch(request).first
        row.setValue(location, forKey: "location")
    }

    private static func fetchItemRow(
        id: Item.ID,
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "ItemEntity")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private static func makeItem(from row: NSManagedObject) -> Item {
        let locationID =
            (row.value(forKey: "location") as? NSManagedObject)?
            .value(forKey: "id") as? UUID ?? UUID()
        return Item(
            id: row.value(forKey: "id") as? UUID ?? UUID(),
            locationID: locationID,
            name: row.value(forKey: "name") as? String ?? "",
            quantity: row.value(forKey: "quantity") as? Int32 ?? 1,
            unit: Unit(rawValue: row.value(forKey: "unitRaw") as? String ?? "count"),
            expiresAt: row.value(forKey: "expiresAt") as? Date,
            notes: row.value(forKey: "notes") as? String,
            createdAt: row.value(forKey: "createdAt") as? Date ?? Date(),
            updatedAt: row.value(forKey: "updatedAt") as? Date ?? Date()
        )
    }
}
