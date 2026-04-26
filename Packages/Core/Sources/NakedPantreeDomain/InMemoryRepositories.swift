import Foundation

/// Pure-Swift `HouseholdRepository` for SwiftUI previews and tests. Backed
/// by an `actor`, so concurrent calls are serialized for free.
public actor InMemoryHouseholdRepository: HouseholdRepository {
    private var current: Household?

    public init(initial: Household? = nil) {
        self.current = initial
    }

    public func currentHousehold() async throws -> Household {
        if let current { return current }
        let new = Household()
        current = new
        return new
    }

    public func update(_ household: Household) async throws {
        current = household
    }
}

/// Pure-Swift `LocationRepository` for SwiftUI previews and tests.
public actor InMemoryLocationRepository: LocationRepository {
    private var locations: [Location.ID: Location] = [:]

    public init(initial: [Location] = []) {
        for location in initial {
            locations[location.id] = location
        }
    }

    public func locations(in householdID: Household.ID) async throws -> [Location] {
        locations.values
            .filter { $0.householdID == householdID }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    public func location(id: Location.ID) async throws -> Location? {
        locations[id]
    }

    public func create(_ location: Location) async throws {
        locations[location.id] = location
    }

    public func update(_ location: Location) async throws {
        locations[location.id] = location
    }

    public func delete(id: Location.ID) async throws {
        locations.removeValue(forKey: id)
    }
}
