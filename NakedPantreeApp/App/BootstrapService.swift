import NakedPantreeDomain

/// First-launch setup. Adds the default `"Kitchen"` location described
/// in `ARCHITECTURE.md` §6 to the user's *private* household if they
/// have no locations yet. Idempotent — safe to call on every launch.
///
/// **Phase 3:** explicitly uses `ensurePrivateHousehold()` rather than
/// `currentHousehold()` so the seed Kitchen never lands in a shared
/// household. With a shared household preferred by `currentHousehold()`,
/// the older code would have inserted Kitchen into the sender's shared
/// store right after the recipient accepted an empty share — visible
/// on the sender's device as a write they never made.
struct BootstrapService: Sendable {
    let household: any HouseholdRepository
    let location: any LocationRepository

    func bootstrapIfNeeded() async throws {
        let house = try await household.ensurePrivateHousehold()
        let existing = try await location.locations(in: house.id)
        guard existing.isEmpty else { return }
        try await location.create(
            Location(householdID: house.id, name: "Kitchen", kind: .pantry)
        )
    }
}
