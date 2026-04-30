import CoreData
import Foundation

@testable import NakedPantreePersistence

/// Test fixture that seeds an on-disk SQLite store against an older,
/// hand-built schema so a migration regression test can re-open it
/// against the current `CoreDataStack.model` and assert that automatic
/// inferred mapping still works. Issue #141.
///
/// **Why hand-built rather than shipping an `.xcdatamodeld` resource:**
/// the iOS test bundle's resource pipeline picks up `.xcdatamodeld`
/// directories, but cross-bundle `.momd` lookup gets brittle once the
/// test target also has to round-trip through `xcodegen` regeneration —
/// the issue's spec explicitly allows "a manually-built minimal
/// pre-current model" for this reason. Programmatic construction keeps
/// the fixture self-documenting (the schema diff is visible inline) and
/// hermetic (no build-system surprises).
///
/// **Why "pre-needs-restocking" specifically:** that's the most recent
/// production schema change (#16, PR #145). Pinning migration from a
/// schema that real users had on disk before #145 shipped exercises the
/// exact additive-Boolean-attribute path that automatic inference
/// handles — and is the path #106's `CoreDataStackError.storeLoadFailed`
/// surface would route around if a future schema change ever broke
/// inference.
///
/// Cleanup happens via `cleanup()` (call from a Swift Testing `@Test`'s
/// `defer` block). Mirrors the `MultiStoreFixture` cleanup contract.
final class MigrationFixture {
    /// File URL of the seeded SQLite store. Hand this to a fresh
    /// `NSPersistentContainer` configured with the **current**
    /// `CoreDataStack.model` to drive the migration under test.
    let storeURL: URL

    /// IDs of the seeded fixture rows so the test can fetch them back
    /// post-migration without scanning. The chain is
    /// `Household → Location → Item` so the migration touches
    /// relationships, not just isolated attributes — the bug class
    /// this test guards against (inference can't handle a relationship
    /// change) needs relationships in the SQLite to surface.
    let seededHouseholdID: UUID
    let seededLocationID: UUID
    let seededItemID: UUID

    private let baseDirectory: URL

    init(name: String = "NakedPantree") throws {
        let unique = UUID().uuidString
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nakedpantree-migration-\(unique)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        self.baseDirectory = directory
        self.storeURL = directory.appendingPathComponent("\(name).sqlite")

        let householdID = UUID()
        let locationID = UUID()
        let itemID = UUID()
        self.seededHouseholdID = householdID
        self.seededLocationID = locationID
        self.seededItemID = itemID

        // Open a container against the OLD model, seed the chain, then
        // tear the container down. Closure-scoped so the coordinator
        // and store are released before the test re-opens the same
        // SQLite URL with the current model — a still-live coordinator
        // on the same path produces "store already in use" errors that
        // masquerade as migration failures.
        try Self.seed(
            storeURL: storeURL,
            name: name,
            householdID: householdID,
            locationID: locationID,
            itemID: itemID
        )
    }

    /// Removes the fixture's per-instance directory. Idempotent. Call
    /// from a `defer` block at the top of each test that uses the
    /// fixture so files don't accumulate across runs.
    func cleanup() {
        try? FileManager.default.removeItem(at: baseDirectory)
    }

    private static func seed(
        storeURL: URL,
        name: String,
        householdID: UUID,
        locationID: UUID,
        itemID: UUID
    ) throws {
        let model = makePreNeedsRestockingModel()
        let container = NSPersistentContainer(name: name, managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldAddStoreAsynchronously = false
        // Match production history-tracking — turning history on later
        // is itself a store-shape change, and we want the migration
        // under test to be exclusively about the model schema diff.
        description.setOption(
            true as NSNumber,
            forKey: NSPersistentHistoryTrackingKey
        )
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let error = loadError {
            throw error
        }

        let context = container.viewContext
        let now = Date()

        let household = NSEntityDescription.insertNewObject(
            forEntityName: "HouseholdEntity",
            into: context
        )
        household.setValue(householdID, forKey: "id")
        household.setValue("Migration Pantry", forKey: "name")
        household.setValue(now, forKey: "createdAt")

        let location = NSEntityDescription.insertNewObject(
            forEntityName: "LocationEntity",
            into: context
        )
        location.setValue(locationID, forKey: "id")
        location.setValue("Kitchen", forKey: "name")
        location.setValue("pantry", forKey: "kindRaw")
        location.setValue(Int16(0), forKey: "sortOrder")
        location.setValue(now, forKey: "createdAt")
        location.setValue(household, forKey: "household")

        let item = NSEntityDescription.insertNewObject(
            forEntityName: "ItemEntity",
            into: context
        )
        item.setValue(itemID, forKey: "id")
        item.setValue("Sourdough", forKey: "name")
        item.setValue("Top shelf", forKey: "notes")
        item.setValue(Int32(2), forKey: "quantity")
        item.setValue("count", forKey: "unitRaw")
        item.setValue(now, forKey: "createdAt")
        item.setValue(now, forKey: "updatedAt")
        item.setValue(location, forKey: "location")

        try context.save()
        // Force the coordinator to release the SQLite handle before
        // the next call site re-opens it with the current model.
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }

    /// Builds the schema as it existed in production before #16
    /// (PR #145) added `ItemEntity.needsRestocking`. Every other
    /// attribute and relationship matches the current
    /// `CoreDataStack.model` exactly so the inferred mapping has only
    /// one diff to handle.
    ///
    /// Implementation note: relationships are wired in two passes —
    /// build all the entities and attributes first, then attach
    /// relationships and inverses. `NSRelationshipDescription`
    /// requires both endpoints to exist before `inverseRelationship`
    /// can be set.
    static func makePreNeedsRestockingModel() -> NSManagedObjectModel {
        let household = makeHouseholdEntity()
        let location = makeLocationEntity()
        let item = makeItemEntity()
        let photo = makeItemPhotoEntity()

        wireRelationship(
            toMany: "locations",
            on: household,
            inverse: "household",
            on: location
        )
        wireRelationship(
            toMany: "items",
            on: location,
            inverse: "location",
            on: item
        )
        wireRelationship(
            toMany: "photos",
            on: item,
            inverse: "item",
            on: photo
        )

        let model = NSManagedObjectModel()
        model.entities = [household, location, item, photo]
        return model
    }

    private static func makeHouseholdEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "HouseholdEntity"
        entity.managedObjectClassName = "HouseholdEntity"
        entity.properties = [
            optionalAttribute(name: "createdAt", type: .dateAttributeType),
            optionalAttribute(name: "id", type: .UUIDAttributeType),
            optionalAttribute(
                name: "name",
                type: .stringAttributeType,
                defaultValue: "My Pantry"
            ),
        ]
        return entity
    }

    private static func makeLocationEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "LocationEntity"
        entity.managedObjectClassName = "LocationEntity"
        entity.properties = [
            optionalAttribute(name: "createdAt", type: .dateAttributeType),
            optionalAttribute(name: "id", type: .UUIDAttributeType),
            optionalAttribute(
                name: "kindRaw",
                type: .stringAttributeType,
                defaultValue: "pantry"
            ),
            optionalAttribute(name: "name", type: .stringAttributeType),
            optionalAttribute(
                name: "sortOrder",
                type: .integer16AttributeType,
                defaultValue: Int16(0)
            ),
        ]
        return entity
    }

    private static func makeItemEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "ItemEntity"
        entity.managedObjectClassName = "ItemEntity"
        entity.properties = [
            optionalAttribute(name: "createdAt", type: .dateAttributeType),
            optionalAttribute(name: "expiresAt", type: .dateAttributeType),
            optionalAttribute(name: "id", type: .UUIDAttributeType),
            optionalAttribute(name: "name", type: .stringAttributeType),
            optionalAttribute(name: "notes", type: .stringAttributeType),
            optionalAttribute(
                name: "quantity",
                type: .integer32AttributeType,
                defaultValue: Int32(1)
            ),
            optionalAttribute(
                name: "unitRaw",
                type: .stringAttributeType,
                defaultValue: "count"
            ),
            optionalAttribute(name: "updatedAt", type: .dateAttributeType),
        ]
        return entity
    }

    private static func makeItemPhotoEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "ItemPhotoEntity"
        entity.managedObjectClassName = "ItemPhotoEntity"
        entity.properties = [
            optionalAttribute(name: "caption", type: .stringAttributeType),
            optionalAttribute(name: "createdAt", type: .dateAttributeType),
            optionalAttribute(name: "id", type: .UUIDAttributeType),
            optionalAttribute(name: "imageData", type: .binaryDataAttributeType),
            optionalAttribute(
                name: "sortOrder",
                type: .integer16AttributeType,
                defaultValue: Int16(0)
            ),
            optionalAttribute(name: "thumbnailData", type: .binaryDataAttributeType),
        ]
        return entity
    }

    /// Wires a paired to-many / to-one relationship between two
    /// entities and appends both halves to their respective
    /// `properties` arrays. `NSRelationshipDescription.maxCount = 0`
    /// is the framework convention for "to-many"; `1` is "to-one".
    /// Production model uses `cascade` on the to-many side and
    /// `nullify` on the to-one inverse — same conventions here.
    private static func wireRelationship(
        toMany manyName: String,
        on parent: NSEntityDescription,
        inverse oneName: String,
        on child: NSEntityDescription
    ) {
        let toMany = NSRelationshipDescription()
        toMany.name = manyName
        toMany.destinationEntity = child
        toMany.minCount = 0
        toMany.maxCount = 0
        toMany.deleteRule = .cascadeDeleteRule
        toMany.isOptional = true

        let toOne = NSRelationshipDescription()
        toOne.name = oneName
        toOne.destinationEntity = parent
        toOne.minCount = 0
        toOne.maxCount = 1
        toOne.deleteRule = .nullifyDeleteRule
        toOne.isOptional = true

        toMany.inverseRelationship = toOne
        toOne.inverseRelationship = toMany
        parent.properties.append(toMany)
        child.properties.append(toOne)
    }

    private static func optionalAttribute(
        name: String,
        type: NSAttributeType,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = true
        if let defaultValue {
            attribute.defaultValue = defaultValue
        }
        return attribute
    }
}
