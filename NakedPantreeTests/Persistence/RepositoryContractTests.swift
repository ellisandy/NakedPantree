// swiftlint:disable file_length
import CoreData
import Foundation
import Testing

@testable import NakedPantreeDomain
@testable import NakedPantreePersistence

/// Each test is parameterized over a `Factory` so the same contract runs
/// against the in-memory mock and the Core Data implementation. Per Phase 1
/// exit criteria in `ROADMAP.md`: "Repository protocol tests pass with both
/// the Core Data implementation and an in-memory mock."
struct RepositoryBundle: Sendable {
    let household: any HouseholdRepository
    let location: any LocationRepository
    let item: any ItemRepository
    let photo: any ItemPhotoRepository
}

struct RepositoryFactory: Sendable, CustomStringConvertible {
    let label: String
    let make: @Sendable () -> RepositoryBundle

    var description: String { label }

    static let all: [RepositoryFactory] = [
        RepositoryFactory(label: "InMemory") {
            let location = InMemoryLocationRepository()
            let item = InMemoryItemRepository(
                locationLookup: { [weak location] id in
                    try await location?.location(id: id)
                }
            )
            return RepositoryBundle(
                household: InMemoryHouseholdRepository(),
                location: location,
                item: item,
                photo: InMemoryItemPhotoRepository()
            )
        },
        RepositoryFactory(label: "CoreData") {
            let container = CoreDataStack.inMemoryContainer()
            return RepositoryBundle(
                household: CoreDataHouseholdRepository(container: container),
                location: CoreDataLocationRepository(container: container),
                item: CoreDataItemRepository(container: container),
                photo: CoreDataItemPhotoRepository(container: container)
            )
        },
    ]
}

@Suite("HouseholdRepository contract")
struct HouseholdRepositoryContractTests {
    @Test(
        "currentHousehold creates a default household on first call",
        arguments: RepositoryFactory.all)
    func bootstrapsDefaultHousehold(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let first = try await household.currentHousehold()
        #expect(first.name == "My Pantry")
    }

    @Test(
        "currentHousehold is idempotent — same row on every call",
        arguments: RepositoryFactory.all)
    func currentHouseholdIsIdempotent(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let first = try await household.currentHousehold()
        let second = try await household.currentHousehold()
        #expect(first.id == second.id)
        #expect(first.createdAt == second.createdAt)
    }

    @Test(
        "update persists a renamed household",
        arguments: RepositoryFactory.all)
    func updatePersists(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        var current = try await household.currentHousehold()
        current.name = "Rev's Place"
        try await household.update(current)

        let refetched = try await household.currentHousehold()
        #expect(refetched.id == current.id)
        #expect(refetched.name == "Rev's Place")
    }

    @Test(
        "ensurePrivateHousehold matches currentHousehold on single-store containers",
        arguments: RepositoryFactory.all)
    func ensurePrivateHouseholdIsIdempotent(factory: RepositoryFactory) async throws {
        // Single-store containers (in-memory + the test-only Core Data
        // inMemoryContainer) have no shared store, so the private-only
        // path resolves to the same household as `currentHousehold()`.
        // Multi-store divergence is verified on real devices per
        // `DEVELOPMENT.md` §5b.
        let bundle = factory.make()
        let household = bundle.household
        let priv = try await household.ensurePrivateHousehold()
        let again = try await household.ensurePrivateHousehold()
        let current = try await household.currentHousehold()
        #expect(priv.id == again.id)
        #expect(priv.id == current.id)
        #expect(priv.name == "My Pantry")
    }

    @Test(
        "existingPrivateHousehold returns nil before any household exists, then matches once seeded",
        arguments: RepositoryFactory.all)
    func existingPrivateHouseholdPeekIsNonCreating(factory: RepositoryFactory) async throws {
        // Phase 8.2 / issue #67: `BootstrapService` peeks before it
        // commits, so the contract is "no household → nil; existing
        // household → that row." A regression that auto-creates here
        // would silently re-introduce the duplicate-on-fresh-install
        // bug because bootstrap would always see a row on its first
        // peek.
        let bundle = factory.make()
        let household = bundle.household

        let preCreate = try await household.existingPrivateHousehold()
        #expect(preCreate == nil)

        let created = try await household.ensurePrivateHousehold()
        let postCreate = try await household.existingPrivateHousehold()
        #expect(postCreate?.id == created.id)
    }
}

@Suite("LocationRepository contract")
struct LocationRepositoryContractTests {
    @Test(
        "create + locations(in:) returns the created location",
        arguments: RepositoryFactory.all)
    func createAndList(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let house = try await household.currentHousehold()
        let kitchen = Location(householdID: house.id, name: "Kitchen Pantry")
        try await locationRepo.create(kitchen)

        let fetched = try await locationRepo.locations(in: house.id)
        #expect(fetched.count == 1)
        #expect(fetched.first?.id == kitchen.id)
        #expect(fetched.first?.name == "Kitchen Pantry")
        #expect(fetched.first?.kind == .pantry)
    }

    @Test(
        "locations(in:) sorts by sortOrder then createdAt",
        arguments: RepositoryFactory.all)
    func sortingByOrderThenDate(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let house = try await household.currentHousehold()
        let now = Date()

        let garageFreezer = Location(
            householdID: house.id,
            name: "Garage Freezer",
            kind: .freezer,
            sortOrder: 1,
            createdAt: now
        )
        let kitchenPantry = Location(
            householdID: house.id,
            name: "Kitchen Pantry",
            kind: .pantry,
            sortOrder: 0,
            createdAt: now.addingTimeInterval(60)
        )
        let barnShelf = Location(
            householdID: house.id,
            name: "Barn Shelf",
            kind: .other,
            sortOrder: 0,
            createdAt: now
        )
        try await locationRepo.create(garageFreezer)
        try await locationRepo.create(kitchenPantry)
        try await locationRepo.create(barnShelf)

        let fetched = try await locationRepo.locations(in: house.id)
        #expect(fetched.map(\.id) == [barnShelf.id, kitchenPantry.id, garageFreezer.id])
    }

    @Test(
        "locations(in:) is scoped — other households are filtered out",
        arguments: RepositoryFactory.all)
    func scopedByHousehold(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let mine = try await household.currentHousehold()
        let elsewhere = Household(name: "Mom's Pantry")

        try await locationRepo.create(Location(householdID: mine.id, name: "Kitchen"))
        try await locationRepo.create(Location(householdID: elsewhere.id, name: "Mom's Kitchen"))

        let fetched = try await locationRepo.locations(in: mine.id)
        #expect(fetched.map(\.name) == ["Kitchen"])
    }

    @Test(
        "update changes the persisted name and kind",
        arguments: RepositoryFactory.all)
    func updateChangesAttributes(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let house = try await household.currentHousehold()
        var pantry = Location(householdID: house.id, name: "Kitchen", kind: .pantry)
        try await locationRepo.create(pantry)

        pantry.name = "Kitchen Pantry"
        pantry.kind = .dryGoods
        try await locationRepo.update(pantry)

        let fetched = try await locationRepo.location(id: pantry.id)
        #expect(fetched?.name == "Kitchen Pantry")
        #expect(fetched?.kind == .dryGoods)
    }

    @Test(
        "delete removes the row",
        arguments: RepositoryFactory.all)
    func deleteRemovesRow(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let house = try await household.currentHousehold()
        let kitchen = Location(householdID: house.id, name: "Kitchen")
        try await locationRepo.create(kitchen)

        try await locationRepo.delete(id: kitchen.id)
        #expect(try await locationRepo.location(id: kitchen.id) == nil)
        #expect(try await locationRepo.locations(in: house.id).isEmpty)
    }

    @Test(
        "location(id:) returns nil for an unknown id",
        arguments: RepositoryFactory.all)
    func locationByUnknownIDIsNil(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let locationRepo = bundle.location
        let unknown = try await locationRepo.location(id: UUID())
        #expect(unknown == nil)
    }

    // MARK: - Issue #133 — per-household name uniqueness

    @Test(
        "create with an exact-duplicate name throws duplicateName",
        arguments: RepositoryFactory.all)
    func createDuplicateExactThrows(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let house = try await household.currentHousehold()
        try await locationRepo.create(Location(householdID: house.id, name: "Kitchen Pantry"))

        await #expect(throws: LocationRepositoryError.duplicateName(name: "Kitchen Pantry")) {
            try await locationRepo.create(
                Location(householdID: house.id, name: "Kitchen Pantry")
            )
        }
    }

    @Test(
        "create with a case-different duplicate name throws duplicateName",
        arguments: RepositoryFactory.all)
    func createDuplicateCaseInsensitiveThrows(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let house = try await household.currentHousehold()
        try await locationRepo.create(Location(householdID: house.id, name: "Kitchen Pantry"))

        await #expect(throws: LocationRepositoryError.self) {
            try await locationRepo.create(
                Location(householdID: house.id, name: "kitchen pantry")
            )
        }
    }

    @Test(
        "create with whitespace-padded duplicate name throws duplicateName",
        arguments: RepositoryFactory.all)
    func createDuplicateWhitespaceThrows(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let house = try await household.currentHousehold()
        try await locationRepo.create(Location(householdID: house.id, name: "Kitchen Pantry"))

        await #expect(throws: LocationRepositoryError.self) {
            try await locationRepo.create(
                Location(householdID: house.id, name: "  KITCHEN PANTRY  ")
            )
        }
    }

    @Test(
        "update renaming into another location's name throws duplicateName",
        arguments: RepositoryFactory.all)
    func updateRenameIntoDuplicateThrows(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let house = try await household.currentHousehold()
        let kitchen = Location(householdID: house.id, name: "Kitchen")
        let pantry = Location(householdID: house.id, name: "Pantry")
        try await locationRepo.create(kitchen)
        try await locationRepo.create(pantry)

        var renamed = pantry
        renamed.name = "kitchen"
        await #expect(throws: LocationRepositoryError.self) {
            try await locationRepo.update(renamed)
        }
    }

    @Test(
        "update keeping the row's own current name succeeds (no false self-collision)",
        arguments: RepositoryFactory.all)
    func updateKeepingOwnNameSucceeds(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let house = try await household.currentHousehold()
        let kitchen = Location(householdID: house.id, name: "Kitchen", kind: .pantry)
        try await locationRepo.create(kitchen)

        // Rename the row to its own current name (case-insensitive
        // match against itself); kind change is the "real" edit. The
        // repository must not flag this as a duplicate.
        var updated = kitchen
        updated.name = "  KITCHEN  "
        updated.kind = .fridge
        try await locationRepo.update(updated)

        let reloaded = try #require(try await locationRepo.location(id: kitchen.id))
        #expect(reloaded.kind == .fridge)
    }

    @Test(
        "two different households can each have a same-named location",
        arguments: RepositoryFactory.all)
    func differentHouseholdsAllowSameName(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let locationRepo = bundle.location
        let firstHousehold = UUID()
        let secondHousehold = UUID()
        try await locationRepo.create(
            Location(householdID: firstHousehold, name: "Kitchen Pantry")
        )
        // Same name, different household — no collision.
        try await locationRepo.create(
            Location(householdID: secondHousehold, name: "Kitchen Pantry")
        )

        let firstLocations = try await locationRepo.locations(in: firstHousehold)
        let secondLocations = try await locationRepo.locations(in: secondHousehold)
        #expect(firstLocations.count == 1)
        #expect(secondLocations.count == 1)
    }
}

@Suite("ItemRepository contract")
struct ItemRepositoryContractTests {
    @Test(
        "create + items(in:) returns the created item",
        arguments: RepositoryFactory.all)
    func createAndList(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let itemRepo = bundle.item
        let house = try await household.currentHousehold()
        let kitchen = Location(householdID: house.id, name: "Kitchen")
        try await locationRepo.create(kitchen)

        let tomatoes = Item(
            locationID: kitchen.id, name: "Tomatoes", quantity: 3, unit: .count
        )
        try await itemRepo.create(tomatoes)

        let fetched = try await itemRepo.items(in: kitchen.id)
        #expect(fetched.count == 1)
        #expect(fetched.first?.id == tomatoes.id)
        #expect(fetched.first?.name == "Tomatoes")
        #expect(fetched.first?.quantity == 3)
        #expect(fetched.first?.unit == .count)
    }

    @Test(
        "items(in:) is scoped — items in other locations are filtered out",
        arguments: RepositoryFactory.all)
    func scopedByLocation(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let itemRepo = bundle.item
        let house = try await household.currentHousehold()
        let pantry = Location(householdID: house.id, name: "Kitchen")
        let freezer = Location(householdID: house.id, name: "Garage Freezer", kind: .freezer)
        try await locationRepo.create(pantry)
        try await locationRepo.create(freezer)

        try await itemRepo.create(Item(locationID: pantry.id, name: "Rice"))
        try await itemRepo.create(Item(locationID: freezer.id, name: "Ice Cream"))

        let pantryItems = try await itemRepo.items(in: pantry.id)
        #expect(pantryItems.map(\.name) == ["Rice"])
    }

    @Test(
        "update stamps updatedAt and overwrites the caller's value",
        arguments: RepositoryFactory.all)
    func updateStampsTimestamp(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let itemRepo = bundle.item
        let house = try await household.currentHousehold()
        let kitchen = Location(householdID: house.id, name: "Kitchen")
        try await locationRepo.create(kitchen)

        let originalDate = Date(timeIntervalSince1970: 1)
        var item = Item(
            locationID: kitchen.id,
            name: "Bread",
            createdAt: originalDate,
            updatedAt: originalDate
        )
        try await itemRepo.create(item)

        item.name = "Sourdough"
        item.updatedAt = Date(timeIntervalSince1970: 2)  // caller value to be overwritten
        try await itemRepo.update(item)

        let after = try #require(try await itemRepo.item(id: item.id))
        #expect(after.name == "Sourdough")
        #expect(after.createdAt == originalDate)
        #expect(after.updatedAt > Date(timeIntervalSince1970: 2))
    }

    /// Issue #134: an `update` whose item carries a different
    /// `locationID` reassigns the item to that location. Pins the
    /// repository contract that `ItemFormSaveCoordinator` relies on
    /// to power the move-on-edit UX. CoreData mutates the
    /// `location` relationship via `attachLocation`; the in-memory
    /// repo replaces the row by id.
    @Test(
        "update with a new locationID moves the item between locations (#134)",
        arguments: RepositoryFactory.all)
    func updateReassignsLocation(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let itemRepo = bundle.item
        let house = try await household.currentHousehold()
        let pantry = Location(householdID: house.id, name: "Pantry")
        let freezer = Location(householdID: house.id, name: "Garage Freezer", kind: .freezer)
        try await locationRepo.create(pantry)
        try await locationRepo.create(freezer)

        var chili = Item(locationID: pantry.id, name: "Chili", quantity: 1, unit: .count)
        try await itemRepo.create(chili)

        // Sanity-check the create landed in pantry; the move test
        // depends on starting state being correct.
        let beforePantry = try await itemRepo.items(in: pantry.id)
        #expect(beforePantry.map(\.id) == [chili.id])

        chili.locationID = freezer.id
        try await itemRepo.update(chili)

        // After the move: the item shows up under freezer and is
        // gone from pantry. Both halves matter — a half-finished
        // implementation that copies the row instead of moving
        // would leave duplicates at the old location.
        let afterPantry = try await itemRepo.items(in: pantry.id)
        let afterFreezer = try await itemRepo.items(in: freezer.id)
        #expect(afterPantry.isEmpty, "Item should no longer appear under the old location.")
        #expect(afterFreezer.map(\.id) == [chili.id])

        // Identity / history preserved: same id, same createdAt.
        let fetched = try #require(try await itemRepo.item(id: chili.id))
        #expect(fetched.id == chili.id)
        #expect(fetched.locationID == freezer.id)
        #expect(fetched.createdAt == chili.createdAt)
    }

    @Test(
        "updateQuantity changes only quantity, leaves name and expiresAt untouched (#118)",
        arguments: RepositoryFactory.all)
    func updateQuantityIsPartial(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let itemRepo = bundle.item
        let house = try await household.currentHousehold()
        let kitchen = Location(householdID: house.id, name: "Kitchen")
        try await locationRepo.create(kitchen)

        let expiry = Date(timeIntervalSince1970: 1_000_000)
        let item = Item(
            locationID: kitchen.id,
            name: "Yogurt",
            quantity: 1,
            unit: .count,
            expiresAt: expiry,
            notes: "Plain greek"
        )
        try await itemRepo.create(item)

        // Issue #118: updateQuantity must NOT touch name / expiresAt /
        // notes / unit / locationID. The original race was a stepper
        // persist overwriting these fields after a form save.
        try await itemRepo.updateQuantity(id: item.id, quantity: 7)

        let after = try #require(try await itemRepo.item(id: item.id))
        #expect(after.quantity == 7)
        #expect(after.name == "Yogurt")
        #expect(after.expiresAt == expiry)
        #expect(after.notes == "Plain greek")
        #expect(after.unit == .count)
        #expect(after.locationID == kitchen.id)
    }

    @Test(
        "updateQuantity is a no-op when the item id doesn't exist",
        arguments: RepositoryFactory.all)
    func updateQuantityMissingIDIsNoOp(factory: RepositoryFactory) async throws {
        let itemRepo = factory.make().item
        // Random UUID — not in the empty repo. Should silently no-op,
        // matching `update(_:)`'s missing-row semantics.
        try await itemRepo.updateQuantity(id: UUID(), quantity: 99)
    }

    @Test(
        "updateQuantity stamps updatedAt",
        arguments: RepositoryFactory.all)
    func updateQuantityStampsTimestamp(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let itemRepo = bundle.item
        let house = try await household.currentHousehold()
        let kitchen = Location(householdID: house.id, name: "Kitchen")
        try await locationRepo.create(kitchen)

        let originalDate = Date(timeIntervalSince1970: 1)
        let item = Item(
            locationID: kitchen.id,
            name: "Sourdough",
            createdAt: originalDate,
            updatedAt: originalDate
        )
        try await itemRepo.create(item)

        try await itemRepo.updateQuantity(id: item.id, quantity: 5)

        let after = try #require(try await itemRepo.item(id: item.id))
        #expect(after.createdAt == originalDate)
        #expect(after.updatedAt > originalDate)
    }

    @Test(
        "search matches case-insensitively and trims empty queries",
        arguments: RepositoryFactory.all)
    func searchMatchesAndTrims(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let itemRepo = bundle.item
        let house = try await household.currentHousehold()
        let kitchen = Location(householdID: house.id, name: "Kitchen")
        try await locationRepo.create(kitchen)

        try await itemRepo.create(Item(locationID: kitchen.id, name: "Cherry tomatoes"))
        try await itemRepo.create(Item(locationID: kitchen.id, name: "Tomato paste"))
        try await itemRepo.create(Item(locationID: kitchen.id, name: "Rice"))

        let hits = try await itemRepo.search("toma", in: house.id)
        #expect(Set(hits.map(\.name)) == ["Cherry tomatoes", "Tomato paste"])

        let empty = try await itemRepo.search("   ", in: house.id)
        #expect(empty.isEmpty)
    }

    @Test(
        "search returns matches from every location in the household",
        arguments: RepositoryFactory.all)
    func searchSpansAllLocations(factory: RepositoryFactory) async throws {
        // Phase 6.2b acceptance: the sidebar search surface filters
        // across every location in the household. The repository call
        // is the same `search(_:in:)` AllItemsView used; this test
        // pins the cross-location guarantee that surface depends on.
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let itemRepo = bundle.item
        let house = try await household.currentHousehold()
        let pantry = Location(householdID: house.id, name: "Kitchen Pantry")
        let freezer = Location(householdID: house.id, name: "Garage Freezer", kind: .freezer)
        try await locationRepo.create(pantry)
        try await locationRepo.create(freezer)

        try await itemRepo.create(Item(locationID: pantry.id, name: "Pantry Tomatoes"))
        try await itemRepo.create(Item(locationID: freezer.id, name: "Freezer Tomatoes"))
        try await itemRepo.create(Item(locationID: pantry.id, name: "Bread"))

        let hits = try await itemRepo.search("tomato", in: house.id)
        #expect(Set(hits.map(\.name)) == ["Pantry Tomatoes", "Freezer Tomatoes"])
    }

    @Test(
        "search is scoped to the household, not the location",
        arguments: RepositoryFactory.all)
    func searchScopedToHousehold(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let itemRepo = bundle.item
        let mine = try await household.currentHousehold()
        let elsewhere = Household(name: "Mom's Pantry")
        let myKitchen = Location(householdID: mine.id, name: "Kitchen")
        let momsKitchen = Location(householdID: elsewhere.id, name: "Mom's Kitchen")
        try await locationRepo.create(myKitchen)
        try await locationRepo.create(momsKitchen)

        try await itemRepo.create(Item(locationID: myKitchen.id, name: "My Tomatoes"))
        try await itemRepo.create(Item(locationID: momsKitchen.id, name: "Mom's Tomatoes"))

        let hits = try await itemRepo.search("tomato", in: mine.id)
        #expect(hits.map(\.name) == ["My Tomatoes"])
    }

    @Test(
        "delete removes the item",
        arguments: RepositoryFactory.all)
    func deleteRemovesItem(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let itemRepo = bundle.item
        let house = try await household.currentHousehold()
        let kitchen = Location(householdID: house.id, name: "Kitchen")
        try await locationRepo.create(kitchen)
        let bread = Item(locationID: kitchen.id, name: "Bread")
        try await itemRepo.create(bread)

        try await itemRepo.delete(id: bread.id)
        #expect(try await itemRepo.item(id: bread.id) == nil)
        #expect(try await itemRepo.items(in: kitchen.id).isEmpty)
    }

    @Test(
        "item(id:) returns nil for an unknown id",
        arguments: RepositoryFactory.all)
    func itemByUnknownIDIsNil(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let itemRepo = bundle.item
        let unknown = try await itemRepo.item(id: UUID())
        #expect(unknown == nil)
    }

    @Test(
        "allItems(in:) returns every item across every location, sorted by name",
        arguments: RepositoryFactory.all)
    func allItemsInHousehold(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let itemRepo = bundle.item

        let house = try await household.currentHousehold()
        let pantry = Location(householdID: house.id, name: "Kitchen")
        let freezer = Location(householdID: house.id, name: "Garage Freezer", kind: .freezer)
        try await locationRepo.create(pantry)
        try await locationRepo.create(freezer)

        try await itemRepo.create(Item(locationID: pantry.id, name: "Tomatoes"))
        try await itemRepo.create(Item(locationID: freezer.id, name: "Ice Cream"))
        try await itemRepo.create(Item(locationID: pantry.id, name: "Bread"))

        let all = try await itemRepo.allItems(in: house.id)
        #expect(all.map(\.name) == ["Bread", "Ice Cream", "Tomatoes"])
    }

    @Test(
        "allItems(in:) is scoped — items in other households are filtered out",
        arguments: RepositoryFactory.all)
    func allItemsScopedByHousehold(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let itemRepo = bundle.item

        let mine = try await household.currentHousehold()
        let elsewhere = Household(name: "Mom's Pantry")
        let myKitchen = Location(householdID: mine.id, name: "Kitchen")
        let momsKitchen = Location(householdID: elsewhere.id, name: "Mom's Kitchen")
        try await locationRepo.create(myKitchen)
        try await locationRepo.create(momsKitchen)
        try await itemRepo.create(Item(locationID: myKitchen.id, name: "My Bread"))
        try await itemRepo.create(Item(locationID: momsKitchen.id, name: "Mom's Bread"))

        let all = try await itemRepo.allItems(in: mine.id)
        #expect(all.map(\.name) == ["My Bread"])
    }
}

/// Issue #16: smart-list contract for items that need restocking. Lives
/// in its own suite (rather than nested in `ItemRepositoryContractTests`)
/// because adding it inline pushed that struct past
/// SwiftLint's `type_body_length` ceiling, and these tests cohere
/// around a single feature anyway.
@Suite("ItemRepository needs-restocking contract")
struct ItemRepositoryNeedsRestockingContractTests {
    @Test(
        "create + item(id:) round-trips needsRestocking",
        arguments: RepositoryFactory.all)
    func needsRestockingRoundTrips(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let itemRepo = bundle.item
        let house = try await household.currentHousehold()
        let kitchen = Location(householdID: house.id, name: "Kitchen")
        try await locationRepo.create(kitchen)

        // Default false branch.
        let bread = Item(locationID: kitchen.id, name: "Bread")
        try await itemRepo.create(bread)
        let breadFetched = try #require(try await itemRepo.item(id: bread.id))
        #expect(breadFetched.needsRestocking == false)

        // Explicit true branch.
        let coffee = Item(locationID: kitchen.id, name: "Coffee", needsRestocking: true)
        try await itemRepo.create(coffee)
        let coffeeFetched = try #require(try await itemRepo.item(id: coffee.id))
        #expect(coffeeFetched.needsRestocking == true)
    }

    @Test(
        "setNeedsRestocking flips only that flag — quantity / name / expiresAt untouched",
        arguments: RepositoryFactory.all)
    func setNeedsRestockingIsPartial(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let itemRepo = bundle.item
        let house = try await household.currentHousehold()
        let kitchen = Location(householdID: house.id, name: "Kitchen")
        try await locationRepo.create(kitchen)

        let expiry = Date(timeIntervalSince1970: 1_000_000)
        let item = Item(
            locationID: kitchen.id,
            name: "Yogurt",
            quantity: 2,
            unit: .count,
            expiresAt: expiry,
            notes: "Plain greek"
        )
        try await itemRepo.create(item)

        // Same race contract as `updateQuantity` (#118): the partial
        // update must NOT touch sibling fields. Issue #16: a swipe
        // action / detail toggle that races a form save shouldn't
        // clobber the form's just-saved name/expiry/notes.
        try await itemRepo.setNeedsRestocking(id: item.id, needsRestocking: true)

        let after = try #require(try await itemRepo.item(id: item.id))
        #expect(after.needsRestocking == true)
        #expect(after.quantity == 2)
        #expect(after.name == "Yogurt")
        #expect(after.expiresAt == expiry)
        #expect(after.notes == "Plain greek")
        #expect(after.unit == .count)
    }

    @Test(
        "setNeedsRestocking is a no-op when the item id doesn't exist",
        arguments: RepositoryFactory.all)
    func setNeedsRestockingMissingIDIsNoOp(factory: RepositoryFactory) async throws {
        let itemRepo = factory.make().item
        // Random UUID — not in the empty repo. Should silently no-op,
        // matching `update(_:)` / `updateQuantity` semantics.
        try await itemRepo.setNeedsRestocking(id: UUID(), needsRestocking: true)
    }

    @Test(
        "setNeedsRestocking stamps updatedAt",
        arguments: RepositoryFactory.all)
    func setNeedsRestockingStampsTimestamp(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let itemRepo = bundle.item
        let house = try await household.currentHousehold()
        let kitchen = Location(householdID: house.id, name: "Kitchen")
        try await locationRepo.create(kitchen)

        let originalDate = Date(timeIntervalSince1970: 1)
        let item = Item(
            locationID: kitchen.id,
            name: "Coffee",
            createdAt: originalDate,
            updatedAt: originalDate
        )
        try await itemRepo.create(item)

        try await itemRepo.setNeedsRestocking(id: item.id, needsRestocking: true)

        let after = try #require(try await itemRepo.item(id: item.id))
        #expect(after.createdAt == originalDate)
        #expect(after.updatedAt > originalDate)
    }

    @Test(
        "needsRestocking(in:) includes flagged + zero-quantity items, sorted by name",
        arguments: RepositoryFactory.all)
    func needsRestockingUnion(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let itemRepo = bundle.item
        let house = try await household.currentHousehold()
        let pantry = Location(householdID: house.id, name: "Pantry")
        let freezer = Location(householdID: house.id, name: "Freezer", kind: .freezer)
        try await locationRepo.create(pantry)
        try await locationRepo.create(freezer)

        // Flagged manually (typical "we'll need this soon") — non-zero qty.
        try await itemRepo.create(
            Item(locationID: pantry.id, name: "Olive Oil", quantity: 1, needsRestocking: true)
        )
        // Implicitly out-of-stock (zero qty, not flagged) — kept around
        // so the user remembers it's a staple.
        try await itemRepo.create(Item(locationID: pantry.id, name: "Coffee", quantity: 0))
        // In another location, flagged.
        try await itemRepo.create(
            Item(locationID: freezer.id, name: "Ice Cream", quantity: 2, needsRestocking: true)
        )
        // Has stock and not flagged — should be excluded.
        try await itemRepo.create(Item(locationID: pantry.id, name: "Rice", quantity: 5))
        // Both flagged AND zero qty — appears once, not duplicated.
        try await itemRepo.create(
            Item(locationID: freezer.id, name: "Bread", quantity: 0, needsRestocking: true)
        )

        let restocking = try await itemRepo.needsRestocking(in: house.id)
        #expect(restocking.map(\.name) == ["Bread", "Coffee", "Ice Cream", "Olive Oil"])
    }

    @Test(
        "needsRestocking(in:) is scoped — items in other households are filtered out",
        arguments: RepositoryFactory.all)
    func needsRestockingScopedByHousehold(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let itemRepo = bundle.item

        let mine = try await household.currentHousehold()
        let elsewhere = Household(name: "Mom's Pantry")
        let myKitchen = Location(householdID: mine.id, name: "Kitchen")
        let momsKitchen = Location(householdID: elsewhere.id, name: "Mom's Kitchen")
        try await locationRepo.create(myKitchen)
        try await locationRepo.create(momsKitchen)

        try await itemRepo.create(
            Item(locationID: myKitchen.id, name: "My Coffee", needsRestocking: true)
        )
        try await itemRepo.create(
            Item(locationID: momsKitchen.id, name: "Mom's Coffee", needsRestocking: true)
        )

        let mineResults = try await itemRepo.needsRestocking(in: mine.id)
        #expect(mineResults.map(\.name) == ["My Coffee"])
    }

    @Test(
        "needsRestocking(in:) is empty when nothing qualifies",
        arguments: RepositoryFactory.all)
    func needsRestockingEmpty(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let itemRepo = bundle.item
        let house = try await household.currentHousehold()
        let kitchen = Location(householdID: house.id, name: "Kitchen")
        try await locationRepo.create(kitchen)

        try await itemRepo.create(Item(locationID: kitchen.id, name: "Rice", quantity: 5))
        try await itemRepo.create(Item(locationID: kitchen.id, name: "Beans", quantity: 3))

        let restocking = try await itemRepo.needsRestocking(in: house.id)
        #expect(restocking.isEmpty)
    }
}

/// Issue #153: pins the auto-flag-when-low contract that
/// `ItemRepository` implementations must honour. Same parameterized
/// shape as the other contract suites — every implementation runs
/// every test. Lives in its own suite (separate from
/// `ItemRepositoryNeedsRestockingContractTests`) so the auto-flag
/// rule has a clear, discoverable home and the existing #16 tests
/// stay focused on the manual-flag / out-of-stock semantics.
@Suite("ItemRepository auto-flag-when-low contract (#153)")
struct ItemRepositoryAutoFlagWhenLowContractTests {
    @Test(
        "create with quantity at threshold flips needsRestocking on insert",
        arguments: RepositoryFactory.all)
    func createAtThresholdFlips(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let kitchen = try await Self.makeKitchen(bundle)
        let milk = Item(
            locationID: kitchen.id,
            name: "Milk",
            quantity: 2,
            restockThreshold: 2
        )
        try await bundle.item.create(milk)
        let fetched = try #require(try await bundle.item.item(id: milk.id))
        #expect(fetched.needsRestocking == true)
        #expect(fetched.restockThreshold == 2)
    }

    @Test(
        "create with quantity above threshold does not flip",
        arguments: RepositoryFactory.all)
    func createAboveThresholdNoFlip(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let kitchen = try await Self.makeKitchen(bundle)
        let milk = Item(
            locationID: kitchen.id,
            name: "Milk",
            quantity: 5,
            restockThreshold: 2
        )
        try await bundle.item.create(milk)
        let fetched = try #require(try await bundle.item.item(id: milk.id))
        #expect(fetched.needsRestocking == false)
    }

    @Test(
        "update that drops quantity to threshold flips false → true",
        arguments: RepositoryFactory.all)
    func updateCrossingThresholdFlips(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let kitchen = try await Self.makeKitchen(bundle)
        var milk = Item(
            locationID: kitchen.id,
            name: "Milk",
            quantity: 5,
            restockThreshold: 2
        )
        try await bundle.item.create(milk)

        milk.quantity = 1
        try await bundle.item.update(milk)
        let fetched = try #require(try await bundle.item.item(id: milk.id))
        #expect(fetched.needsRestocking == true, "Auto-flag rule must fire on quantity drop.")
    }

    @Test(
        "updateQuantity partial path also fires the auto-flag rule",
        arguments: RepositoryFactory.all)
    func updateQuantityPartialFlips(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let kitchen = try await Self.makeKitchen(bundle)
        let milk = Item(
            locationID: kitchen.id,
            name: "Milk",
            quantity: 5,
            restockThreshold: 2
        )
        try await bundle.item.create(milk)

        // Partial update — the stepper-driven path. Threshold-crossing
        // here must also flip the flag, matching the full-update
        // path. Pre-#153 this was the silent gap.
        try await bundle.item.updateQuantity(id: milk.id, quantity: 0)
        let fetched = try #require(try await bundle.item.item(id: milk.id))
        #expect(fetched.needsRestocking == true)
        #expect(fetched.quantity == 0, "Quantity must still be partial-updated.")
    }

    @Test(
        "update never auto-clears: quantity rising above threshold leaves flag set",
        arguments: RepositoryFactory.all)
    func updateAboveThresholdDoesNotClear(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let kitchen = try await Self.makeKitchen(bundle)
        var milk = Item(
            locationID: kitchen.id,
            name: "Milk",
            quantity: 1,
            needsRestocking: true,
            restockThreshold: 2
        )
        try await bundle.item.create(milk)

        // User restocked above threshold but didn't manually clear
        // the flag. The flag must stay set — that's the spec's "no
        // auto-clear" rule. Clearing is the user's job via the
        // existing detail toggle / swipe action.
        milk.quantity = 10
        try await bundle.item.update(milk)
        let fetched = try #require(try await bundle.item.item(id: milk.id))
        #expect(fetched.needsRestocking == true, "Flag must persist when quantity rises.")
    }

    @Test(
        "nil threshold opts out of the auto-flag rule entirely",
        arguments: RepositoryFactory.all)
    func nilThresholdOptsOut(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let kitchen = try await Self.makeKitchen(bundle)
        let bread = Item(
            locationID: kitchen.id,
            name: "Bread",
            quantity: 0,  // Out of stock — would surface via the #16
            // `quantity == 0` rule but should NOT cause auto-flag
            // (because that's the manual-flag list path; auto-flag
            // is gated on a non-nil threshold).
            restockThreshold: nil
        )
        try await bundle.item.create(bread)
        let fetched = try #require(try await bundle.item.item(id: bread.id))
        #expect(fetched.needsRestocking == false, "Nil threshold must not auto-flag.")
    }

    @Test(
        "threshold of 0 is valid and flips at quantity 0",
        arguments: RepositoryFactory.all)
    func zeroThresholdFlipsAtZero(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let kitchen = try await Self.makeKitchen(bundle)
        let item = Item(
            locationID: kitchen.id,
            name: "Salt",
            quantity: 0,
            restockThreshold: 0
        )
        try await bundle.item.create(item)
        let fetched = try #require(try await bundle.item.item(id: item.id))
        #expect(fetched.needsRestocking == true)
        #expect(fetched.restockThreshold == 0)
    }

    @Test(
        "create + item(id:) round-trips restockThreshold (including nil)",
        arguments: RepositoryFactory.all)
    func restockThresholdRoundTrips(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let kitchen = try await Self.makeKitchen(bundle)

        let withThreshold = Item(
            locationID: kitchen.id,
            name: "Milk",
            quantity: 5,
            restockThreshold: 2
        )
        try await bundle.item.create(withThreshold)
        let withFetched = try #require(try await bundle.item.item(id: withThreshold.id))
        #expect(withFetched.restockThreshold == 2)

        let withoutThreshold = Item(
            locationID: kitchen.id,
            name: "Bread"
        )
        try await bundle.item.create(withoutThreshold)
        let withoutFetched = try #require(try await bundle.item.item(id: withoutThreshold.id))
        #expect(withoutFetched.restockThreshold == nil)
    }

    /// Shared kitchen-location helper. Mirrors the local lambdas in
    /// the other contract suites — keeps test bodies focused on the
    /// behavior under test rather than the household / location
    /// bootstrap ceremony.
    private static func makeKitchen(_ bundle: RepositoryBundle) async throws -> Location {
        let house = try await bundle.household.currentHousehold()
        let kitchen = Location(householdID: house.id, name: "Kitchen")
        try await bundle.location.create(kitchen)
        return kitchen
    }
}

@Suite("ItemPhotoRepository contract")
struct ItemPhotoRepositoryContractTests {
    @Test(
        "create + photos(for:) returns the photo strip",
        arguments: RepositoryFactory.all)
    func createAndList(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let itemRepo = bundle.item
        let photoRepo = bundle.photo
        let house = try await household.currentHousehold()
        let kitchen = Location(householdID: house.id, name: "Kitchen")
        try await locationRepo.create(kitchen)
        let waffles = Item(locationID: kitchen.id, name: "Waffle mix")
        try await itemRepo.create(waffles)

        let primary = ItemPhoto(
            itemID: waffles.id, caption: "front of box", sortOrder: 0
        )
        let secondary = ItemPhoto(
            itemID: waffles.id, caption: "ingredients", sortOrder: 1
        )
        try await photoRepo.create(primary)
        try await photoRepo.create(secondary)

        let strip = try await photoRepo.photos(for: waffles.id)
        #expect(strip.map(\.id) == [primary.id, secondary.id])
        #expect(strip.first?.caption == "front of box")
    }

    @Test(
        "photos(for:) sorts by sortOrder then createdAt",
        arguments: RepositoryFactory.all)
    func sortingByOrderThenDate(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let itemRepo = bundle.item
        let photoRepo = bundle.photo
        let house = try await household.currentHousehold()
        let kitchen = Location(householdID: house.id, name: "Kitchen")
        try await locationRepo.create(kitchen)
        let waffles = Item(locationID: kitchen.id, name: "Waffle mix")
        try await itemRepo.create(waffles)
        let now = Date()

        let back = ItemPhoto(
            itemID: waffles.id,
            caption: "back",
            sortOrder: 1,
            createdAt: now
        )
        let front = ItemPhoto(
            itemID: waffles.id,
            caption: "front",
            sortOrder: 0,
            createdAt: now.addingTimeInterval(60)
        )
        let lid = ItemPhoto(
            itemID: waffles.id,
            caption: "lid",
            sortOrder: 0,
            createdAt: now
        )

        try await photoRepo.create(back)
        try await photoRepo.create(front)
        try await photoRepo.create(lid)

        let strip = try await photoRepo.photos(for: waffles.id)
        #expect(strip.map(\.id) == [lid.id, front.id, back.id])
    }

    @Test(
        "delete removes the photo",
        arguments: RepositoryFactory.all)
    func deleteRemovesPhoto(factory: RepositoryFactory) async throws {
        let bundle = factory.make()
        let household = bundle.household
        let locationRepo = bundle.location
        let itemRepo = bundle.item
        let photoRepo = bundle.photo
        let house = try await household.currentHousehold()
        let kitchen = Location(householdID: house.id, name: "Kitchen")
        try await locationRepo.create(kitchen)
        let waffles = Item(locationID: kitchen.id, name: "Waffle mix")
        try await itemRepo.create(waffles)
        let photo = ItemPhoto(itemID: waffles.id)
        try await photoRepo.create(photo)

        try await photoRepo.delete(id: photo.id)
        #expect(try await photoRepo.photos(for: waffles.id).isEmpty)
    }
}

/// Cascade-delete is a Core Data behavior driven by the model's
/// `deletionRule="Cascade"` rule, not part of the protocol contract —
/// the in-memory mocks deliberately don't simulate it (they're intended
/// as fast fixtures for the layers above persistence). These tests pin
/// the schema's cascade rules so a future model edit can't silently
/// drop them.
@Suite("Core Data cascade deletes")
struct CascadeDeleteTests {
    @Test("Deleting a Location cascades through its Items to their ItemPhotos")
    func locationCascadesToItemsAndPhotos() async throws {
        let container = CoreDataStack.inMemoryContainer()
        let household = CoreDataHouseholdRepository(container: container)
        let locationRepo = CoreDataLocationRepository(container: container)
        let itemRepo = CoreDataItemRepository(container: container)
        let photoRepo = CoreDataItemPhotoRepository(container: container)

        let house = try await household.currentHousehold()
        let kitchen = Location(householdID: house.id, name: "Kitchen")
        try await locationRepo.create(kitchen)

        let bread = Item(locationID: kitchen.id, name: "Bread")
        let milk = Item(locationID: kitchen.id, name: "Milk")
        try await itemRepo.create(bread)
        try await itemRepo.create(milk)

        let breadPhoto = ItemPhoto(itemID: bread.id, caption: "front")
        let milkPhoto = ItemPhoto(itemID: milk.id, caption: "front")
        try await photoRepo.create(breadPhoto)
        try await photoRepo.create(milkPhoto)

        // Sanity check before the cascade.
        #expect(try await itemRepo.items(in: kitchen.id).count == 2)
        #expect(try await photoRepo.photos(for: bread.id).count == 1)
        #expect(try await photoRepo.photos(for: milk.id).count == 1)

        try await locationRepo.delete(id: kitchen.id)

        #expect(try await itemRepo.items(in: kitchen.id).isEmpty)
        #expect(try await itemRepo.item(id: bread.id) == nil)
        #expect(try await itemRepo.item(id: milk.id) == nil)
        #expect(try await photoRepo.photos(for: bread.id).isEmpty)
        #expect(try await photoRepo.photos(for: milk.id).isEmpty)
    }

    @Test("Deleting an Item cascades to its ItemPhotos")
    func itemCascadesToPhotos() async throws {
        let container = CoreDataStack.inMemoryContainer()
        let household = CoreDataHouseholdRepository(container: container)
        let locationRepo = CoreDataLocationRepository(container: container)
        let itemRepo = CoreDataItemRepository(container: container)
        let photoRepo = CoreDataItemPhotoRepository(container: container)

        let house = try await household.currentHousehold()
        let kitchen = Location(householdID: house.id, name: "Kitchen")
        try await locationRepo.create(kitchen)
        let bread = Item(locationID: kitchen.id, name: "Bread")
        try await itemRepo.create(bread)
        try await photoRepo.create(ItemPhoto(itemID: bread.id, caption: "front"))
        try await photoRepo.create(ItemPhoto(itemID: bread.id, caption: "back"))

        #expect(try await photoRepo.photos(for: bread.id).count == 2)

        try await itemRepo.delete(id: bread.id)
        #expect(try await photoRepo.photos(for: bread.id).isEmpty)
    }
}
