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

    /// Returns the pre-increment value so callers can dispatch on
    /// "this is the Nth call" without observing their own bump.
    func snapshotAndIncrement() -> Int {
        let snapshot = value
        value += 1
        return snapshot
    }
}

@Suite("BootstrapService — issue #110 multi-device race")
struct BootstrapServiceMultiDeviceTests {
    /// Models a second device joining an iCloud account: the household
    /// arrives via the first remote-change tick, and a "Kitchen"
    /// location arrives on a later remote-change tick. Pre-#110,
    /// bootstrap saw "household synced, locations empty" between the
    /// two ticks and seeded a Kitchen — duplicating once the synced
    /// Kitchen landed. Post-#110, the second wait gives locations
    /// time to land before bootstrap decides.
    @Test("Two-stage sync: household arrives, then locations — no duplicate Kitchen")
    func locationsArriveAfterHouseholdNoDuplicate() async throws {
        let household = InMemoryHouseholdRepository()
        let location = InMemoryLocationRepository()
        let preExistingHousehold = Household(name: "My Pantry")
        let preExistingKitchen = Location(
            householdID: preExistingHousehold.id,
            name: "Kitchen",
            kind: .pantry
        )

        // Two-stage waiter: first call seeds the household, second call
        // seeds the Kitchen. Mirrors the real CloudKit pattern of
        // separate transactions per record-zone change.
        let callCount = WaitCounter()
        let waitForRemoteChange: @Sendable () async -> Void = {
            let invocation = await callCount.snapshotAndIncrement()
            try? await Task.sleep(for: .milliseconds(50))
            switch invocation {
            case 0:
                try? await household.update(preExistingHousehold)
            case 1:
                try? await location.create(preExistingKitchen)
            default:
                break
            }
        }

        let service = BootstrapService(
            household: household,
            location: location,
            waitForRemoteChange: waitForRemoteChange,
            syncWaitTimeout: .seconds(5)
        )
        try await service.bootstrapIfNeeded()

        let locations = try await location.locations(in: preExistingHousehold.id)
        #expect(locations.count == 1, "Bootstrap must not duplicate the synced Kitchen.")
        #expect(locations.first?.id == preExistingKitchen.id)

        // Both wait calls fired: first to bring down the household,
        // second to give locations time to settle.
        let waits = await callCount.value
        #expect(waits == 2, "Bootstrap should wait twice when household arrives via sync.")
    }

    /// If the second wait elapses without locations arriving, bootstrap
    /// proceeds to seed — assumes the user really has zero locations
    /// (e.g. they deleted them all on the originating device).
    @Test("Two-stage sync: household arrives, locations don't — bootstrap seeds Kitchen")
    func locationsNeverArriveBootstrapSeeds() async throws {
        let household = InMemoryHouseholdRepository()
        let location = InMemoryLocationRepository()
        let preExistingHousehold = Household(name: "My Pantry")

        let callCount = WaitCounter()
        let waitForRemoteChange: @Sendable () async -> Void = {
            let invocation = await callCount.snapshotAndIncrement()
            try? await Task.sleep(for: .milliseconds(20))
            if invocation == 0 {
                try? await household.update(preExistingHousehold)
            }
            // Subsequent calls intentionally do nothing — locations
            // never sync in this test scenario.
        }

        let service = BootstrapService(
            household: household,
            location: location,
            waitForRemoteChange: waitForRemoteChange,
            syncWaitTimeout: .milliseconds(100)
        )
        try await service.bootstrapIfNeeded()

        let locations = try await location.locations(in: preExistingHousehold.id)
        #expect(locations.count == 1, "Bootstrap must seed Kitchen when no locations sync.")
        #expect(locations.first?.name == "Kitchen")
    }
}
