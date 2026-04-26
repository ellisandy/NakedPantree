import CoreData
import Foundation
import Testing

@testable import NakedPantreeDomain
@testable import NakedPantreePersistence

/// Each test is parameterized over a `Factory` so the same contract runs
/// against the in-memory mock and the Core Data implementation. Per Phase 1
/// exit criteria in `ROADMAP.md`: "Repository protocol tests pass with both
/// the Core Data implementation and an in-memory mock."
struct RepositoryFactory: Sendable, CustomStringConvertible {
    let label: String
    let make:
        @Sendable () -> (
            household: any HouseholdRepository,
            location: any LocationRepository
        )

    var description: String { label }

    static let all: [RepositoryFactory] = [
        RepositoryFactory(label: "InMemory") {
            (InMemoryHouseholdRepository(), InMemoryLocationRepository())
        },
        RepositoryFactory(label: "CoreData") {
            let container = CoreDataStack.inMemoryContainer()
            return (
                CoreDataHouseholdRepository(container: container),
                CoreDataLocationRepository(container: container)
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
        let (household, _) = factory.make()
        let first = try await household.currentHousehold()
        #expect(first.name == "My Pantry")
    }

    @Test(
        "currentHousehold is idempotent — same row on every call",
        arguments: RepositoryFactory.all)
    func currentHouseholdIsIdempotent(factory: RepositoryFactory) async throws {
        let (household, _) = factory.make()
        let first = try await household.currentHousehold()
        let second = try await household.currentHousehold()
        #expect(first.id == second.id)
        #expect(first.createdAt == second.createdAt)
    }

    @Test(
        "update persists a renamed household",
        arguments: RepositoryFactory.all)
    func updatePersists(factory: RepositoryFactory) async throws {
        let (household, _) = factory.make()
        var current = try await household.currentHousehold()
        current.name = "Rev's Place"
        try await household.update(current)

        let refetched = try await household.currentHousehold()
        #expect(refetched.id == current.id)
        #expect(refetched.name == "Rev's Place")
    }
}

@Suite("LocationRepository contract")
struct LocationRepositoryContractTests {
    @Test(
        "create + locations(in:) returns the created location",
        arguments: RepositoryFactory.all)
    func createAndList(factory: RepositoryFactory) async throws {
        let (household, locationRepo) = factory.make()
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
        let (household, locationRepo) = factory.make()
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
        let (household, locationRepo) = factory.make()
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
        let (household, locationRepo) = factory.make()
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
        let (household, locationRepo) = factory.make()
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
        let (_, locationRepo) = factory.make()
        let unknown = try await locationRepo.location(id: UUID())
        #expect(unknown == nil)
    }
}
