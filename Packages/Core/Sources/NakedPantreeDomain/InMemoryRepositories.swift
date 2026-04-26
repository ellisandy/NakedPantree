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

/// Pure-Swift `ItemRepository` for SwiftUI previews and tests.
///
/// `update(_:)` stamps `updatedAt = Date()` per the protocol contract.
/// `create(_:)` honors the caller-supplied `updatedAt` so deterministic
/// fixture data still works.
///
/// Search resolution depends on knowing each item's household. Since
/// `Item` only carries `locationID`, the in-memory impl needs a way to
/// resolve `locationID → householdID` — pass in a `LocationRepository`
/// (any conforming type) at init time. The resolver runs once per
/// `search(_:in:)` call.
public actor InMemoryItemRepository: ItemRepository {
    private var items: [Item.ID: Item] = [:]
    private let locationLookup: @Sendable (Location.ID) async throws -> Location?

    /// `locationLookup` defaults to "no household scoping" — search will
    /// match items in any household. Provide a real lookup (typically
    /// `locationRepo.location(id:)`) when scoping matters.
    public init(
        initial: [Item] = [],
        locationLookup: @Sendable @escaping (Location.ID) async throws -> Location? = { _ in nil }
    ) {
        for item in initial {
            items[item.id] = item
        }
        self.locationLookup = locationLookup
    }

    public func items(in locationID: Location.ID) async throws -> [Item] {
        items.values
            .filter { $0.locationID == locationID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func item(id: Item.ID) async throws -> Item? {
        items[id]
    }

    public func search(_ query: String, in householdID: Household.ID) async throws -> [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        let needle = trimmed.lowercased()

        var results: [Item] = []
        for item in items.values where item.name.lowercased().contains(needle) {
            let location = try await locationLookup(item.locationID)
            if location?.householdID == householdID {
                results.append(item)
            }
        }
        return results.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    public func create(_ item: Item) async throws {
        items[item.id] = item
    }

    public func update(_ item: Item) async throws {
        var stamped = item
        stamped.updatedAt = Date()
        items[item.id] = stamped
    }

    public func delete(id: Item.ID) async throws {
        items.removeValue(forKey: id)
    }
}

/// Pure-Swift `ItemPhotoRepository` for SwiftUI previews and tests.
public actor InMemoryItemPhotoRepository: ItemPhotoRepository {
    private var photos: [ItemPhoto.ID: ItemPhoto] = [:]

    public init(initial: [ItemPhoto] = []) {
        for photo in initial {
            photos[photo.id] = photo
        }
    }

    public func photos(for itemID: Item.ID) async throws -> [ItemPhoto] {
        photos.values
            .filter { $0.itemID == itemID }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    public func create(_ photo: ItemPhoto) async throws {
        photos[photo.id] = photo
    }

    public func update(_ photo: ItemPhoto) async throws {
        photos[photo.id] = photo
    }

    public func delete(id: ItemPhoto.ID) async throws {
        photos.removeValue(forKey: id)
    }
}
