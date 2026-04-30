import CoreData
import Foundation
import Testing

@testable import NakedPantreePersistence

/// Issue #141: regression coverage for the automatic mapping-model
/// inference path that #106 (PR #140) wrapped in a recovery surface.
/// The launcher catches a `loadPersistentStores` throw and routes the
/// user into "Try Again" / "Reset and Retry" — but the cheaper fix is
/// catching the migration regression *before* it ships, which is what
/// this test does.
///
/// **What's pinned:** loading a SQLite seeded against the schema as it
/// existed before #16 (`needsRestocking` not yet on `ItemEntity`)
/// against the **current** `CoreDataStack.model`, with
/// `shouldMigrateStoreAutomatically = true` +
/// `shouldInferMappingModelAutomatically = true`. The test asserts:
///
/// 1. `loadPersistentStores` returns no error — inference produced a
///    valid mapping model from old → current.
/// 2. The seeded `Household → Location → Item` chain survives the
///    migration with relationships intact.
/// 3. `ItemEntity.needsRestocking` reads as `false` post-migration —
///    the additive-Boolean default-fill semantics held.
///
/// **What this test will catch in the future:** any schema change that
/// breaks automatic inference (renames without a custom mapping,
/// destructive entity removal, type-narrowing). When that lands, this
/// test fails locally / in CI; the dev either adds a custom mapping
/// model or accepts that on-device upgrade requires the #106 reset
/// path.
@Suite("CoreData migration")
struct MigrationTests {
    @Test("Pre-#16 SQLite migrates cleanly to current model under inferred mapping")
    func preNeedsRestockingMigratesToCurrent() throws {
        let fixture = try MigrationFixture()
        defer { fixture.cleanup() }

        // Plain `NSPersistentContainer` — no CloudKit options. The
        // contract under test is schema migration, not mirroring;
        // CK options would add entitlement / container-identifier
        // requirements unrelated to inferred mapping. Match the
        // production description's history-tracking shape so the
        // migration doesn't conflate "schema diff" with "history
        // tracking turned on".
        let container = NSPersistentContainer(
            name: "NakedPantree",
            managedObjectModel: CoreDataStack.model
        )
        let description = NSPersistentStoreDescription(url: fixture.storeURL)
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(
            true as NSNumber,
            forKey: NSPersistentHistoryTrackingKey
        )
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        try #require(
            loadError == nil,
            "Migration from pre-#16 model failed: \(loadError?.localizedDescription ?? "<nil>")"
        )

        // Data preservation — the seeded chain reads back through the
        // current model, including the newly-added `needsRestocking`
        // attribute defaulting to `false`.
        let context = container.viewContext

        let itemRequest = NSFetchRequest<NSManagedObject>(entityName: "ItemEntity")
        itemRequest.predicate = NSPredicate(format: "id == %@", fixture.seededItemID as CVarArg)
        let items = try context.fetch(itemRequest)
        let item = try #require(items.first, "Seeded ItemEntity didn't survive migration.")

        #expect(item.value(forKey: "name") as? String == "Sourdough")
        #expect(item.value(forKey: "quantity") as? Int32 == 2)
        #expect(
            (item.value(forKey: "needsRestocking") as? Bool) == false,
            "Migration didn't apply the additive-Boolean default."
        )
        // Issue #153: `restockThreshold` is the second additive
        // attribute layered on top of `needsRestocking`. Optional
        // Integer 32 with no default → nil for pre-#153 rows. Pinning
        // it here keeps the migration test honest about both
        // additive-attribute migrations the user data has gone
        // through.
        #expect(
            (item.value(forKey: "restockThreshold") as? Int32) == nil,
            "Migration didn't leave restockThreshold nil for pre-#153 rows."
        )

        // Relationship intact — the item still resolves to the seeded
        // location, and the location still resolves to the seeded
        // household. Catches relationship-shape inference regressions.
        let location = try #require(
            item.value(forKey: "location") as? NSManagedObject,
            "Item lost its location relationship across migration."
        )
        #expect(location.value(forKey: "id") as? UUID == fixture.seededLocationID)

        let household = try #require(
            location.value(forKey: "household") as? NSManagedObject,
            "Location lost its household relationship across migration."
        )
        #expect(household.value(forKey: "id") as? UUID == fixture.seededHouseholdID)
    }
}
