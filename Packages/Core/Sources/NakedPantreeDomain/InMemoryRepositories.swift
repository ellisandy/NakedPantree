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

    /// Single-store mock — same record as `currentHousehold()` since
    /// there's no shared store to distinguish from.
    public func ensurePrivateHousehold() async throws -> Household {
        try await currentHousehold()
    }

    /// Non-creating peek — returns whatever's currently stored without
    /// initializing on the first call. The mock's "private store" is
    /// just `current`, so the only thing distinguishing this from
    /// `currentHousehold()` is the lack of side-effecting creation.
    public func existingPrivateHousehold() async throws -> Household? {
        current
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
        // Issue #133: enforce per-household uniqueness with the
        // normalized comparison declared in `LocationRepository`.
        // `excluding` is nil because every location in the household
        // is a potential collision on create (the new row has no
        // existing id to skip).
        try requireUniqueName(
            location.name,
            in: location.householdID,
            excluding: nil
        )
        locations[location.id] = location
    }

    public func update(_ location: Location) async throws {
        // `excluding: location.id` lets the caller rename the row to
        // its own current name (or change kind/sortOrder without
        // touching the name) — same row's old name doesn't count as
        // a duplicate.
        try requireUniqueName(
            location.name,
            in: location.householdID,
            excluding: location.id
        )
        locations[location.id] = location
    }

    /// Fast-path uniqueness check used by `create` and `update`.
    /// Throws `LocationRepositoryError.duplicateName` when the
    /// normalized name matches any location in the same household
    /// other than the one identified by `excluding`.
    private func requireUniqueName(
        _ name: String,
        in householdID: Household.ID,
        excluding selfID: Location.ID?
    ) throws {
        let target = normalizedLocationName(name)
        let collision = locations.values.first { existing in
            existing.householdID == householdID
                && existing.id != selfID
                && normalizedLocationName(existing.name) == target
        }
        if collision != nil {
            throw LocationRepositoryError.duplicateName(name: name)
        }
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

    public func allItems(in householdID: Household.ID) async throws -> [Item] {
        var results: [Item] = []
        for item in items.values {
            let location = try await locationLookup(item.locationID)
            if location?.householdID == householdID {
                results.append(item)
            }
        }
        return results.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
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
        // Issue #153: evaluate the auto-flag-when-low rule before
        // persisting so a brand-new item created with `quantity == 0`
        // and a non-nil threshold lands on the Needs Restocking list
        // immediately. See `ItemRepository` doc for the contract.
        items[item.id] = Self.applyAutoFlagWhenLow(item)
    }

    public func update(_ item: Item) async throws {
        var stamped = item
        stamped.updatedAt = Date()
        // Issue #153: same rule as create — every full-update path
        // re-evaluates the threshold. The repository is the canonical
        // place for this so future save paths (barcode scan #4, OCR
        // #137) inherit the behavior automatically.
        items[item.id] = Self.applyAutoFlagWhenLow(stamped)
    }

    public func updateQuantity(id: Item.ID, quantity: Int32) async throws {
        // Issue #118: partial update — touch only `quantity` and
        // stamp `updatedAt`. The actor's serial isolation makes
        // this atomic against concurrent `update(_:)` calls.
        guard var existing = items[id] else { return }
        existing.quantity = quantity
        existing.updatedAt = Date()
        // Issue #153: even on the partial path, the auto-flag rule
        // evaluates against the freshly-written quantity. A
        // stepper-driven decrement that crosses the threshold
        // line should land on Needs Restocking without the user
        // opening the form.
        items[id] = Self.applyAutoFlagWhenLow(existing)
    }

    /// Issue #153: shared auto-flag-when-low evaluation. Pure
    /// function so the rule is identical across `create`, `update`,
    /// and `updateQuantity`. Returns the item unchanged when no
    /// threshold is set, when quantity is above threshold, or when
    /// the flag is already true.
    private static func applyAutoFlagWhenLow(_ item: Item) -> Item {
        guard
            let threshold = item.restockThreshold,
            item.quantity <= threshold,
            !item.needsRestocking
        else {
            return item
        }
        var flagged = item
        flagged.needsRestocking = true
        return flagged
    }

    public func setNeedsRestocking(id: Item.ID, needsRestocking: Bool) async throws {
        // Issue #16: partial update — touch only `needsRestocking`
        // and `updatedAt`. Same actor-serialized atomicity as
        // `updateQuantity`.
        guard var existing = items[id] else { return }
        existing.needsRestocking = needsRestocking
        existing.updatedAt = Date()
        items[id] = existing
    }

    public func needsRestocking(in householdID: Household.ID) async throws -> [Item] {
        var results: [Item] = []
        for item in items.values where item.needsRestocking || item.quantity == 0 {
            let location = try await locationLookup(item.locationID)
            if location?.householdID == householdID {
                results.append(item)
            }
        }
        return results.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
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
