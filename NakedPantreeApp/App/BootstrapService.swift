import Foundation
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
///
/// **Phase 8.2 (issue #67):** on a fresh install of a second device
/// tied to an existing iCloud account, the local Core Data store is
/// empty *because CloudKit sync hasn't replicated the existing
/// household yet*. Creating a new `Household` row immediately would
/// race the sync and end up with two households for the same user —
/// items added during the gap would orphan once the older row wins
/// the `createdAt ASC` tiebreak.
///
/// Bootstrap now races the first remote-change tick (sync has begun)
/// against a bounded `syncWaitTimeout`. After the wait it re-peeks
/// for an existing private household; only if still nil does it call
/// `ensurePrivateHousehold()` to create one. The genuinely-first-launch
/// case (no prior household, no iCloud, or new account) falls through
/// after the timeout and bootstraps as before.
struct BootstrapService: Sendable {
    let household: any HouseholdRepository
    let location: any LocationRepository
    /// Suspends until the persistence layer reports its first remote-
    /// change notification. The default no-op closure preserves the
    /// pre-Phase-8.2 behavior for callers that don't need the deferred
    /// path (snapshot mode, in-memory tests of seeding semantics).
    let waitForRemoteChange: @Sendable () async -> Void
    /// Upper bound on how long bootstrap blocks waiting for sync. The
    /// brand-color splash in `RootView` covers this window. 8s is
    /// long enough to cover typical CloudKit replication on a healthy
    /// connection (2–5s observed) with margin for slower networks,
    /// and short enough that the worst-case offline-first-launch UX
    /// is a single splash flash rather than a perceptibly stuck app.
    let syncWaitTimeout: Duration

    init(
        household: any HouseholdRepository,
        location: any LocationRepository,
        waitForRemoteChange: @escaping @Sendable () async -> Void = {},
        syncWaitTimeout: Duration = .seconds(8)
    ) {
        self.household = household
        self.location = location
        self.waitForRemoteChange = waitForRemoteChange
        self.syncWaitTimeout = syncWaitTimeout
    }

    func bootstrapIfNeeded() async throws {
        let resolution = try await resolvePrivateHousehold()
        var existing = try await location.locations(in: resolution.household.id)

        // Issue #110: locations ride a separate CloudKit transaction
        // from the household. When this device joins an iCloud account
        // for the first time, the household can sync down on the first
        // remote-change tick while locations are still in flight.
        // Pre-#110, bootstrap saw "household exists, locations empty"
        // and seeded a Kitchen — only for the synced Kitchen to land
        // moments later, leaving the device with two. Do a second
        // wait when the household came from sync, so the locations
        // collection has a chance to settle before we decide to seed.
        if existing.isEmpty && resolution.source == .syncedDown {
            await waitForFirstRemoteChangeOrTimeout()
            existing = try await location.locations(in: resolution.household.id)
        }

        guard existing.isEmpty else { return }
        try await location.create(
            Location(householdID: resolution.household.id, name: "Kitchen", kind: .pantry)
        )
    }

    /// Where the bootstrap obtained the private household — used by
    /// `bootstrapIfNeeded` to decide whether to wait an extra tick
    /// for locations to sync (issue #110).
    enum HouseholdSource: Equatable {
        /// Already in the local private store at launch — idempotent
        /// re-bootstrap, or a device whose CloudKit sync has already
        /// landed before launch. Locations are typically also already
        /// present.
        case localExisting
        /// Arrived via the first remote-change tick — e.g. a second
        /// device joining an iCloud account. Locations may still be
        /// in flight; bootstrap waits one more tick before deciding
        /// to seed.
        case syncedDown
        /// We just created it via `ensurePrivateHousehold` — first
        /// launch ever (or offline / signed-out). No remote locations
        /// to wait for; seed the Kitchen now.
        case freshlyCreated
    }

    /// Outcome of `resolvePrivateHousehold` — the resolved household
    /// plus where it came from.
    struct HouseholdResolution: Equatable {
        let household: Household
        let source: HouseholdSource
    }

    /// Decides which household this device should bootstrap into.
    ///
    /// Order of preference:
    /// 1. A row already in the local private store — use it (idempotent
    ///    re-bootstrap, or a device whose CloudKit sync has already
    ///    landed before launch). No wait.
    /// 2. Local store is empty: race the first remote-change tick
    ///    against `syncWaitTimeout`. Whichever wins, re-peek. If the
    ///    sync brought a household down, return it.
    /// 3. Still empty after the wait: this really is first launch
    ///    ever (or offline / signed-out), so create one.
    private func resolvePrivateHousehold() async throws -> HouseholdResolution {
        if let existing = try await household.existingPrivateHousehold() {
            return HouseholdResolution(household: existing, source: .localExisting)
        }
        await waitForFirstRemoteChangeOrTimeout()
        if let existing = try await household.existingPrivateHousehold() {
            return HouseholdResolution(household: existing, source: .syncedDown)
        }
        let created = try await household.ensurePrivateHousehold()
        return HouseholdResolution(household: created, source: .freshlyCreated)
    }

    /// Suspends until either the injected `waitForRemoteChange` closure
    /// returns or `syncWaitTimeout` elapses, whichever comes first. The
    /// task group cancels the loser so we don't leak a pending observer
    /// past the bootstrap point.
    private func waitForFirstRemoteChangeOrTimeout() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.waitForRemoteChange()
            }
            group.addTask { [syncWaitTimeout] in
                try? await Task.sleep(for: syncWaitTimeout)
            }
            await group.next()
            group.cancelAll()
        }
    }
}
