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
            let row = NSEntityDescription.insertNewObject(
                forEntityName: "LocationEntity",
                into: context
            )
            if let privateStore = CoreDataStack.privateCloudKitStore(in: container) {
                context.assign(row, to: privateStore)
            }
            try Self.assignAttributes(location, to: row)
            try Self.attachHousehold(location.householdID, to: row, in: context, container: container)
            try context.save()
        }
    }

    public func update(_ location: Location) async throws {
        try await container.performBackgroundTaskWithDefaults { [container] context in
            let row: NSManagedObject
            if let existing = try Self.fetchLocationRow(id: location.id, in: context) {
                row = existing
            } else {
                row = NSEntityDescription.insertNewObject(
                    forEntityName: "LocationEntity",
                    into: context
                )
                if let privateStore = CoreDataStack.privateCloudKitStore(in: container) {
                    context.assign(row, to: privateStore)
                }
            }
            try Self.assignAttributes(location, to: row)
            try Self.attachHousehold(location.householdID, to: row, in: context, container: container)
            try context.save()
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
    /// caller to sequence them).
    private static func attachHousehold(
        _ householdID: Household.ID,
        to row: NSManagedObject,
        in context: NSManagedObjectContext,
        container: NSPersistentContainer
    ) throws {
        let household =
            try fetchHouseholdRow(id: householdID, in: context)
            ?? insertHouseholdRow(id: householdID, in: context, container: container)
        row.setValue(household, forKey: "household")
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
