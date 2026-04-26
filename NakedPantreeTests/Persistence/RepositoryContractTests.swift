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
