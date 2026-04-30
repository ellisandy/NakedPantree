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
        try await container.performBackgroundTaskWithDefaults { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ItemEntity")
            request.predicate = NSPredicate(format: "location.id == %@", locationID as CVarArg)
            request.sortDescriptors = [
                NSSortDescriptor(key: "createdAt", ascending: true)
            ]
            return try context.fetch(request).map(Self.makeItem)
        }
    }

    public func item(id: Item.ID) async throws -> Item? {
        try await container.performBackgroundTaskWithDefaults { context in
            try Self.fetchItemRow(id: id, in: context).map(Self.makeItem)
        }
    }

    public func allItems(in householdID: Household.ID) async throws -> [Item] {
        try await container.performBackgroundTaskWithDefaults { context in
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
        return try await container.performBackgroundTaskWithDefaults { context in
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
        try await container.performBackgroundTaskWithDefaults { [container] context in
            let row = NSEntityDescription.insertNewObject(
                forEntityName: "ItemEntity",
                into: context
            )
            try Self.assignAttributes(item, to: row, stampUpdatedAt: false)
            // Set parent first so we can route the new row to the same
            // store the parent location lives in — see
            // `CoreDataLocationRepository.assignToParentStore` for the
            // CloudKit cross-store-relationship rationale.
            let location = try Self.attachLocation(item.locationID, to: row, in: context)
            Self.assignToParentStore(row, parent: location, container: container, in: context)
            try context.save()
        }
    }

    public func update(_ item: Item) async throws {
        try await container.performBackgroundTaskWithDefaults { [container] context in
            let row: NSManagedObject
            let isNew: Bool
            if let existing = try Self.fetchItemRow(id: item.id, in: context) {
                row = existing
                isNew = false
            } else {
                row = NSEntityDescription.insertNewObject(
                    forEntityName: "ItemEntity",
                    into: context
                )
                isNew = true
            }
            try Self.assignAttributes(item, to: row, stampUpdatedAt: true)
            let location = try Self.attachLocation(item.locationID, to: row, in: context)
            if isNew {
                Self.assignToParentStore(
                    row,
                    parent: location,
                    container: container,
                    in: context
                )
            }
            try context.save()
        }
    }

    public func updateQuantity(id: Item.ID, quantity: Int32) async throws {
        // Issue #118: partial update — touch only `quantity` and
        // `updatedAt` on the row. Avoids round-tripping through an
        // `Item` value the caller mutates, which races edit-form
        // saves of `name` / `expiresAt` (the form's just-saved value
        // could be overwritten by a stepper persist that fetched
        // before the form's save landed).
        try await container.performBackgroundTaskWithDefaults { context in
            guard let row = try Self.fetchItemRow(id: id, in: context) else { return }
            row.setValue(quantity, forKey: "quantity")
            row.setValue(Date(), forKey: "updatedAt")
            try context.save()
        }
    }

    public func setNeedsRestocking(id: Item.ID, needsRestocking: Bool) async throws {
        // Issue #16: partial update — touches `needsRestocking` and
        // `updatedAt` only. Mirrors `updateQuantity`'s race-prevention
        // shape: a swipe action or detail toggle flipping a single bool
        // shouldn't read-modify-write a whole `Item` and risk clobbering
        // a concurrent edit-form save of `name` / `expiresAt`.
        try await container.performBackgroundTaskWithDefaults { context in
            guard let row = try Self.fetchItemRow(id: id, in: context) else { return }
            row.setValue(needsRestocking, forKey: "needsRestocking")
            row.setValue(Date(), forKey: "updatedAt")
            try context.save()
        }
    }

    public func needsRestocking(in householdID: Household.ID) async throws -> [Item] {
        // Issue #16: union of explicitly-flagged and implicitly-out-of-stock
        // items in the household. The OR predicate runs at the Core Data
        // layer so the fetch returns only matching rows — no in-memory
        // filtering. Sort by name to match `allItems(in:)`'s order.
        try await container.performBackgroundTaskWithDefaults { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ItemEntity")
            request.predicate = NSPredicate(
                format:
                    "location.household.id == %@ AND (needsRestocking == YES OR quantity == 0)",
                householdID as CVarArg
            )
            request.sortDescriptors = [
                NSSortDescriptor(key: "name", ascending: true)
            ]
            return try context.fetch(request).map(Self.makeItem)
        }
    }

    public func delete(id: Item.ID) async throws {
        try await container.performBackgroundTaskWithDefaults { context in
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
        row.setValue(item.needsRestocking, forKey: "needsRestocking")
        row.setValue(item.createdAt, forKey: "createdAt")
        row.setValue(stampUpdatedAt ? Date() : item.updatedAt, forKey: "updatedAt")
    }

    /// Mirrors `CoreDataLocationRepository.attachHousehold` — if the
    /// referenced location row doesn't exist yet, we don't insert a
    /// stub. Items must be created against a real location; the
    /// alternative leaves dangling rows on a typo'd `locationID`.
    /// Returns the parent location (or `nil` if not found) so the
    /// caller can route the child's store assignment.
    @discardableResult
    private static func attachLocation(
        _ locationID: Location.ID,
        to row: NSManagedObject,
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "LocationEntity")
        request.predicate = NSPredicate(format: "id == %@", locationID as CVarArg)
        request.fetchLimit = 1
        let location = try context.fetch(request).first
        row.setValue(location, forKey: "location")
        return location
    }

    /// Routes a new item to the same store as its parent location —
    /// CloudKit rejects cross-store relationships at save time. Falls
    /// back to the private store on single-store containers (tests).
    private static func assignToParentStore(
        _ row: NSManagedObject,
        parent: NSManagedObject?,
        container: NSPersistentContainer,
        in context: NSManagedObjectContext
    ) {
        if let parentStore = parent?.objectID.persistentStore {
            context.assign(row, to: parentStore)
        } else if let privateStore = CoreDataStack.privateCloudKitStore(in: container) {
            context.assign(row, to: privateStore)
        }
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
            // Issue #16: defaults to `false` for rows persisted before
            // the column existed (CloudKit additive migration — the
            // attribute is optional with `defaultValueString="NO"`).
            needsRestocking: row.value(forKey: "needsRestocking") as? Bool ?? false,
            createdAt: row.value(forKey: "createdAt") as? Date ?? Date(),
            updatedAt: row.value(forKey: "updatedAt") as? Date ?? Date()
        )
    }
}
