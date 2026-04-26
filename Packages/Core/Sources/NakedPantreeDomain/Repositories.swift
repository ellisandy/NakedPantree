import Foundation

/// Read and update the active household.
///
/// `currentHousehold()` is fetch-or-create: on first call it bootstraps a
/// default household named "My Pantry" with one default `Location` named
/// "Kitchen" (Phase 1 exit criterion in `ROADMAP.md`). Subsequent calls
/// return the same record. Callers don't need to know about bootstrap.
public protocol HouseholdRepository: Sendable {
    func currentHousehold() async throws -> Household
    func update(_ household: Household) async throws
}

/// CRUD over `Location`s scoped to a single household.
public protocol LocationRepository: Sendable {
    func locations(in householdID: Household.ID) async throws -> [Location]
    func location(id: Location.ID) async throws -> Location?
    func create(_ location: Location) async throws
    func update(_ location: Location) async throws
    func delete(id: Location.ID) async throws
}

/// CRUD over `Item`s plus household-scoped search.
///
/// `update(_:)` stamps `updatedAt = Date()` on the persisted record before
/// writing — the value passed in by the caller is overwritten. Tests may
/// inject a clock indirectly by reading the persisted record back; the
/// protocol does not expose one.
public protocol ItemRepository: Sendable {
    func items(in locationID: Location.ID) async throws -> [Item]
    func item(id: Item.ID) async throws -> Item?
    /// Case-insensitive substring match on `Item.name`, scoped to one
    /// household. Empty / whitespace-only queries return an empty array.
    func search(_ query: String, in householdID: Household.ID) async throws -> [Item]
    func create(_ item: Item) async throws
    func update(_ item: Item) async throws
    func delete(id: Item.ID) async throws
}

/// CRUD over an item's photo strip. The lowest-`sortOrder` photo is the
/// primary; the rest are secondary. See `ARCHITECTURE.md` §4.
public protocol ItemPhotoRepository: Sendable {
    func photos(for itemID: Item.ID) async throws -> [ItemPhoto]
    func create(_ photo: ItemPhoto) async throws
    func update(_ photo: ItemPhoto) async throws
    func delete(id: ItemPhoto.ID) async throws
}
