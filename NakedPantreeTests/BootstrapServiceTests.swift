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

    // MARK: - Phase 8.2 / issue #67 — deferred bootstrap on fresh-install

    /// Genuine first-launch (no household, no sync arrives) — bootstrap
    /// must fall through after the timeout and create a household.
    /// Uses a tiny timeout to keep the test fast; the wait closure is
    /// the default no-op so nothing ever resolves it.
    @Test("Timeout without sync — creates a new household after the wait")
    func timeoutWithoutSyncCreatesHousehold() async throws {
        let household = InMemoryHouseholdRepository()
        let location = InMemoryLocationRepository()
        let service = BootstrapService(
            household: household,
            location: location,
            syncWaitTimeout: .milliseconds(50)
        )

        // Empty store, empty wait → the service must hit the
        // ensurePrivateHousehold path and seed Kitchen.
        try await service.bootstrapIfNeeded()

        let peeked = try await household.existingPrivateHousehold()
        #expect(peeked != nil)
        let house = try #require(peeked)
        let locations = try await location.locations(in: house.id)
        #expect(locations.map(\.name) == ["Kitchen"])
    }

    /// Sync arrives before the timeout — bootstrap must adopt the
    /// household that arrived rather than creating a new one. Models
    /// the second-device-fresh-install case from issue #67.
    @Test("Sync arrives before timeout — adopts the synced household, no duplicate")
    func syncArrivesBeforeTimeoutAdoptsExistingHousehold() async throws {
        let household = InMemoryHouseholdRepository()
        let location = InMemoryLocationRepository()
        let preExistingHousehold = Household(name: "My Pantry")

        // The waiter sleeps briefly to model "remote change is on its
        // way", then writes the pre-existing household into the
        // *same* repository the bootstrap service is reading from.
        // Resolving the closure unblocks the race; bootstrap re-peeks
        // and sees the seeded row.
        let waitForRemoteChange: @Sendable () async -> Void = {
            try? await Task.sleep(for: .milliseconds(50))
            try? await household.update(preExistingHousehold)
        }

        let service = BootstrapService(
            household: household,
            location: location,
            waitForRemoteChange: waitForRemoteChange,
            syncWaitTimeout: .seconds(5)
        )

        try await service.bootstrapIfNeeded()

        // The household the service used must be the synced one — same
        // id, not a freshly-minted UUID. Items added in the gap would
        // attach to this id, so this is the load-bearing guarantee.
        let resolved = try #require(try await household.existingPrivateHousehold())
        #expect(resolved.id == preExistingHousehold.id)
        // Kitchen still seeded once into the adopted household.
        let locations = try await location.locations(in: preExistingHousehold.id)
        #expect(locations.map(\.name) == ["Kitchen"])
    }

    /// Idempotency under both branches: once a household exists, a
    /// second `bootstrapIfNeeded()` call short-circuits at the peek
    /// and never enters the wait. Verified by passing a waiter that
    /// would `fatalError` if invoked.
    @Test("Second call short-circuits — never enters the wait again")
    func secondCallSkipsWaitOnceHouseholdExists() async throws {
        let household = InMemoryHouseholdRepository()
        let location = InMemoryLocationRepository()

        // First pass: create a household with a quick timeout.
        let firstPass = BootstrapService(
            household: household,
            location: location,
            syncWaitTimeout: .milliseconds(50)
        )
        try await firstPass.bootstrapIfNeeded()

        // Second pass: the waiter must never run because the peek
        // succeeds. If the implementation regresses to always-wait,
        // this counter going non-zero catches it.
        let waitInvocations = WaitCounter()
        let secondPass = BootstrapService(
            household: household,
            location: location,
            waitForRemoteChange: { await waitInvocations.increment() },
            syncWaitTimeout: .seconds(60)
        )
        try await secondPass.bootstrapIfNeeded()

        let count = await waitInvocations.value
        #expect(count == 0)
        let house = try await household.currentHousehold()
        let locations = try await location.locations(in: house.id)
        #expect(locations.count == 1)
    }
}

/// Test-only counter so the closure can record invocations across
/// concurrency domains without ad-hoc locking.
private actor WaitCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
