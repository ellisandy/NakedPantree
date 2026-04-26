import Foundation
import Testing
@testable import NakedPantree
@testable import NakedPantreeDomain

@Suite("BootstrapService")
struct BootstrapServiceTests {
    @Test("First call creates the default Kitchen location")
    func firstCallSeedsKitchen() async throws {
        let household = InMemoryHouseholdRepository()
        let location = InMemoryLocationRepository()
        let service = BootstrapService(household: household, location: location)

        try await service.bootstrapIfNeeded()

        let house = try await household.currentHousehold()
        let locations = try await location.locations(in: house.id)
        #expect(locations.map(\.name) == ["Kitchen"])
        #expect(locations.first?.kind == .pantry)
    }

    @Test("Second call is a no-op — Kitchen isn't duplicated")
    func secondCallIsNoop() async throws {
        let household = InMemoryHouseholdRepository()
        let location = InMemoryLocationRepository()
        let service = BootstrapService(household: household, location: location)

        try await service.bootstrapIfNeeded()
        try await service.bootstrapIfNeeded()

        let house = try await household.currentHousehold()
        let locations = try await location.locations(in: house.id)
        #expect(locations.count == 1)
    }

    @Test("Existing locations are left alone — Kitchen is not added on top")
    func existingLocationsLeftAlone() async throws {
        let household = InMemoryHouseholdRepository()
        let location = InMemoryLocationRepository()
        let house = try await household.currentHousehold()
        try await location.create(
            Location(householdID: house.id, name: "Garage Freezer", kind: .freezer)
        )

        let service = BootstrapService(household: household, location: location)
        try await service.bootstrapIfNeeded()

        let locations = try await location.locations(in: house.id)
        #expect(locations.map(\.name) == ["Garage Freezer"])
    }
}
