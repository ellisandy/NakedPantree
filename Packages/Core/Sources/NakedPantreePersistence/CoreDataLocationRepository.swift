import CoreData
import Foundation
import NakedPantreeDomain

/// `LocationRepository` backed by `NSPersistentContainer`. Same Sendable
/// trade-off as `CoreDataHouseholdRepository` — see that file.
public final class CoreDataLocationRepository: LocationRepository, @unchecked Sendable {
    private let container: NSPersistentContainer

    public init(container: NSPersistentContainer) {
        self.container = container
    }

    public func locations(in householdID: Household.ID) async throws -> [Location] {
        try await container.performBackgroundTaskWithDefaults { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "LocationEntity")
            request.predicate = NSPredicate(format: "household.id == %@", householdID as CVarArg)
            request.sortDescriptors = [
                NSSortDescriptor(key: "sortOrder", ascending: true),
                NSSortDescriptor(key: "createdAt", ascending: true),
            ]
            return try context.fetch(request).map(Self.makeLocation)
        }
    }

    public func location(id: Location.ID) async throws -> Location? {
        try await container.performBackgroundTaskWithDefaults { context in
            try Self.fetchLocationRow(id: id, in: context).map(Self.makeLocation)
        }
    }

    public func create(_ location: Location) async throws {
        try await container.performBackgroundTaskWithDefaults { [container] context in
            // Issue #133: per-household name uniqueness. Pre-flight
            // the normalized-name comparison before insertion so we
            // don't have to roll back a half-saved context. `nil`
            // for `excluding` — there's no existing row to skip on
            // create.
            try Self.requireUniqueName(
                location.name,
                in: location.householdID,
                excluding: nil,
                context: context
            )
            let row = NSEntityDescription.insertNewObject(
                forEntityName: "LocationEntity",
                into: context
            )
            try Self.assignAttributes(location, to: row)
            // Set the parent relationship FIRST so the parent's store
            // is known, then assign the new row to that same store.
            // CloudKit rejects cross-store relationships at save time;
            // assigning before attaching the parent is what would have
            // landed a recipient's new locations in their private store
            // even when the parent household is shared.
            let household = try Self.attachHousehold(
                location.householdID,
                to: row,
                in: context,
                container: container
            )
            Self.assignToParentStore(row, parent: household, in: context, container: container)
            try context.save()
        }
    }

    public func update(_ location: Location) async throws {
        try await container.performBackgroundTaskWithDefaults { [container] context in
            // Issue #133: same per-household uniqueness check, but
            // `excluding: location.id` so renaming the row to its own
            // current name (or just changing kind/sortOrder) doesn't
            // collide with itself.
            try Self.requireUniqueName(
                location.name,
                in: location.householdID,
                excluding: location.id,
                context: context
            )
            // Existing rows already live in a store — Core Data saves
            // them there. Only the lazy-insert branch needs routing.
            let row: NSManagedObject
            let isNew: Bool
            if let existing = try Self.fetchLocationRow(id: location.id, in: context) {
                row = existing
                isNew = false
            } else {
                row = NSEntityDescription.insertNewObject(
                    forEntityName: "LocationEntity",
                    into: context
                )
                isNew = true
            }
            try Self.assignAttributes(location, to: row)
            let household = try Self.attachHousehold(
                location.householdID,
                to: row,
                in: context,
                container: container
            )
            if isNew {
                Self.assignToParentStore(
                    row,
                    parent: household,
                    in: context,
                    container: container
                )
            }
            try context.save()
        }
    }

    /// Fetches all locations for the given household, then walks the
    /// in-memory list applying the normalized comparison. The Core
    /// Data layer doesn't have a direct case-insensitive +
    /// whitespace-trimmed predicate that's portable across SQL stores,
    /// so post-fetch filtering keeps the rule consistent with
    /// `InMemoryLocationRepository`. The fetch is bounded to the same
    /// household (typical pantry has a handful of locations), so the
    /// cost is negligible.
    ///
    /// Pre-existing duplicates that landed in the store before #133
    /// went out aren't auto-corrected — this check only blocks new
    /// collisions, which matches the migration policy declared in the
    /// `LocationRepository` doc.
    private static func requireUniqueName(
        _ name: String,
        in householdID: Household.ID,
        excluding selfID: Location.ID?,
        context: NSManagedObjectContext
    ) throws {
        let target = normalizedLocationName(name)
        let request = NSFetchRequest<NSManagedObject>(entityName: "LocationEntity")
        request.predicate = NSPredicate(format: "household.id == %@", householdID as CVarArg)
        let rows = try context.fetch(request)
        for row in rows {
            let rowID = row.value(forKey: "id") as? UUID
            if rowID == selfID { continue }
            let rowName = row.value(forKey: "name") as? String ?? ""
            if normalizedLocationName(rowName) == target {
                throw LocationRepositoryError.duplicateName(name: name)
            }
        }
    }

    public func delete(id: Location.ID) async throws {
        try await container.performBackgroundTaskWithDefaults { context in
            guard let row = try Self.fetchLocationRow(id: id, in: context) else { return }
            context.delete(row)
            try context.save()
        }
    }

    private static func assignAttributes(_ location: Location, to row: NSManagedObject) throws {
        row.setValue(location.id, forKey: "id")
        row.setValue(location.name, forKey: "name")
        row.setValue(location.kind.rawValue, forKey: "kindRaw")
        row.setValue(location.sortOrder, forKey: "sortOrder")
        row.setValue(location.createdAt, forKey: "createdAt")
    }

    /// The `LocationEntity.household` relationship is set to a fault on the
    /// `HouseholdEntity` row that matches `householdID`. The household is
    /// created lazily if no row exists yet — covers the case where a
    /// caller inserts a location before `HouseholdRepository.currentHousehold()`
    /// has been awaited (rare, but cheaper to handle than to require the
    /// caller to sequence them). Returns the parent household so the
    /// caller can route the child's store assignment.
    @discardableResult
    private static func attachHousehold(
        _ householdID: Household.ID,
        to row: NSManagedObject,
        in context: NSManagedObjectContext,
        container: NSPersistentContainer
    ) throws -> NSManagedObject {
        let household =
            try fetchHouseholdRow(id: householdID, in: context)
            ?? insertHouseholdRow(id: householdID, in: context, container: container)
        row.setValue(household, forKey: "household")
        return household
    }

    /// Mirrors the new row to the parent's store so CloudKit can
    /// replicate the relationship within a single store. Falls back to
    /// the private store for single-store containers (tests, previews)
    /// where the parent has no resolvable persistent store yet.
    private static func assignToParentStore(
        _ row: NSManagedObject,
        parent: NSManagedObject,
        in context: NSManagedObjectContext,
        container: NSPersistentContainer
    ) {
        if let parentStore = parent.objectID.persistentStore {
            context.assign(row, to: parentStore)
        } else if let privateStore = CoreDataStack.privateCloudKitStore(in: container) {
            context.assign(row, to: privateStore)
        }
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

    private static func insertHouseholdRow(
        id: Household.ID,
        in context: NSManagedObjectContext,
        container: NSPersistentContainer
    ) -> NSManagedObject {
        let row = NSEntityDescription.insertNewObject(
            forEntityName: "HouseholdEntity",
            into: context
        )
        if let privateStore = CoreDataStack.privateCloudKitStore(in: container) {
            context.assign(row, to: privateStore)
        }
        row.setValue(id, forKey: "id")
        row.setValue("My Pantry", forKey: "name")
        row.setValue(Date(), forKey: "createdAt")
        return row
    }

    private static func fetchLocationRow(
        id: Location.ID,
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "LocationEntity")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private static func makeLocation(from row: NSManagedObject) -> Location {
        let householdID =
            (row.value(forKey: "household") as? NSManagedObject)?
            .value(forKey: "id") as? UUID ?? UUID()
        return Location(
            id: row.value(forKey: "id") as? UUID ?? UUID(),
            householdID: householdID,
            name: row.value(forKey: "name") as? String ?? "",
            kind: LocationKind(rawValue: row.value(forKey: "kindRaw") as? String ?? "pantry"),
            sortOrder: row.value(forKey: "sortOrder") as? Int16 ?? 0,
            createdAt: row.value(forKey: "createdAt") as? Date ?? Date()
        )
    }
}
