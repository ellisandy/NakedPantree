import NakedPantreeDomain

/// First-launch setup. `HouseholdRepository.currentHousehold()` already
/// fetches-or-creates the default `"My Pantry"` household; this service
/// completes the bootstrap by adding the default `"Kitchen"` location
/// described in `ARCHITECTURE.md` §6 if (and only if) the user has no
/// locations yet. Idempotent — safe to call on every launch.
struct BootstrapService: Sendable {
    let household: any HouseholdRepository
    let location: any LocationRepository

    func bootstrapIfNeeded() async throws {
        let house = try await household.currentHousehold()
        let existing = try await location.locations(in: house.id)
        guard existing.isEmpty else { return }
        try await location.create(
            Location(householdID: house.id, name: "Kitchen", kind: .pantry)
        )
    }
}
