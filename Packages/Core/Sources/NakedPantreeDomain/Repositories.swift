import Foundation

/// Read and update the active household.
///
/// `currentHousehold()` is fetch-or-create: on first call it creates a
/// default household named "My Pantry" and returns it; subsequent calls
/// return the same record. Cross-entity bootstrap (creating the default
/// `"Kitchen"` location described in `ARCHITECTURE.md` §6) is the
/// responsibility of an app-level startup step that calls into both
/// repositories — the household repo stays narrowly scoped to its entity.
///
/// **Phase 3 sharing semantics.** `currentHousehold()` prefers a
/// shared-store household over a private one when both exist — the
/// recipient who accepts a share lands on the shared household
/// directly. `ensurePrivateHousehold()` is the explicit private-store
/// variant: returns the local-only household, creating it if needed.
/// `BootstrapService` uses the latter so it never seeds a "Kitchen"
/// into a sender's shared household.
public protocol HouseholdRepository: Sendable {
    func currentHousehold() async throws -> Household
    /// Returns the household that lives in the *private* store,
    /// creating it on first call. Always private-only — ignores any
    /// accepted shared households entirely.
    func ensurePrivateHousehold() async throws -> Household
    /// Non-creating peek for the private-store household. Returns `nil`
    /// when the local store is empty — used by `BootstrapService` to
    /// distinguish "genuinely first launch" from "CloudKit sync hasn't
    /// arrived yet" without committing a new row. Never falls back to
    /// the shared store.
    func existingPrivateHousehold() async throws -> Household?
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
    /// Every item across every location in the household, sorted by
    /// name. Backs the `All Items` smart list and is the empty-query
    /// fallback for `search(_:in:)`.
    func allItems(in householdID: Household.ID) async throws -> [Item]
    /// Case-insensitive substring match on `Item.name`, scoped to one
    /// household. Empty / whitespace-only queries return an empty array.
    func search(_ query: String, in householdID: Household.ID) async throws -> [Item]
    func create(_ item: Item) async throws
    func update(_ item: Item) async throws
    /// Partial update that touches only `quantity` (and stamps
    /// `updatedAt`), leaving every other attribute untouched. Issue
    /// #118: `QuantityStepperModel.persist` previously did a full
    /// fetch-modify-save round-trip, which races edit-form saves of
    /// `name` / `expiresAt` — the stepper's fetch could see a stale
    /// value the form had just changed and overwrite it. This is the
    /// atomic alternative; implementations write `quantity` directly
    /// to the store row without round-tripping through an `Item`
    /// value type the caller mutates.
    ///
    /// No-op if the item doesn't exist (deleted between debounce
    /// schedule and persist) — same shape as `update(_:)`'s
    /// silent-skip semantics on a missing row.
    func updateQuantity(id: Item.ID, quantity: Int32) async throws
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
