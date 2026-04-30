import Foundation
import Testing

@testable import NakedPantree

/// Coverage for the pre-init event queueing in
/// `NakedPantreeAppDelegate` (issue #108). iOS can deliver
/// `userDidAcceptCloudKitShareWith` and notification taps before
/// `NakedPantreeApp.init` runs and assigns the seam vars; pre-#108
/// those events were silently dropped. Now they queue and drain
/// once `wireShareAcceptance(_:)` / `wireNotificationRouting(_:)`
/// is called.
///
/// **Test scope.** These tests pin the queue + drain mechanic
/// directly: append to the queue, call `wireNotificationRouting(_:)`,
/// assert drain. Constructing `UNNotificationResponse` /
/// `UNNotification` from a unit test isn't feasible — both have
/// unavailable `init()` and no public alternative — so the
/// delegate methods themselves aren't called here. Their
/// "if seam nil → enqueue, else deliver direct" logic is
/// straightforward enough to verify by inspection; the value of
/// the test suite is making sure the *drain* happens correctly
/// when wire fires.
@Suite("AppDelegate pre-init queue (#108)")
@MainActor
struct NakedPantreeAppDelegatePreInitTests {
    /// Reset all static state before and after each test so order-
    /// independence holds. Static vars in the delegate carry across
    /// test instances otherwise.
    private func resetStaticState() {
        NakedPantreeAppDelegate.shareAcceptance = nil
        NakedPantreeAppDelegate.notificationRouting = nil
        NakedPantreeAppDelegate.pendingShareMetadata = []
        NakedPantreeAppDelegate.pendingNotificationItemIDs = []
    }

    @Test("wireNotificationRouting drains a queued tap to routing.pendingItemID")
    func drainSingleQueuedTap() async throws {
        resetStaticState()
        defer { resetStaticState() }

        let id = UUID()
        // Simulate the pre-init enqueue path: the delegate method
        // appends here when `Self.notificationRouting == nil`.
        NakedPantreeAppDelegate.pendingNotificationItemIDs.append(id)

        let routing = NotificationRoutingService()
        NakedPantreeAppDelegate.wireNotificationRouting(routing)

        // Drain spawns a `Task { @MainActor in }`; yield once so it
        // runs before assertion.
        try await Task.sleep(for: .milliseconds(50))

        #expect(routing.pendingItemID == id)
        #expect(NakedPantreeAppDelegate.pendingNotificationItemIDs.isEmpty)
    }

    @Test("Multiple pre-wire taps yield only the most recent on drain (last-tap-wins)")
    func drainPicksLastTap() async throws {
        resetStaticState()
        defer { resetStaticState() }

        let firstID = UUID()
        let secondID = UUID()
        NakedPantreeAppDelegate.pendingNotificationItemIDs = [firstID, secondID]

        let routing = NotificationRoutingService()
        NakedPantreeAppDelegate.wireNotificationRouting(routing)
        try await Task.sleep(for: .milliseconds(50))

        // Last tap wins, matching the live tap-ordering fix from #119.
        #expect(routing.pendingItemID == secondID)
        #expect(NakedPantreeAppDelegate.pendingNotificationItemIDs.isEmpty)
    }

    @Test("wireNotificationRouting on an empty queue does not synthesize a tap")
    func wireWithEmptyQueueIsNoOp() async throws {
        resetStaticState()
        defer { resetStaticState() }

        let routing = NotificationRoutingService()
        // Queue starts empty.
        NakedPantreeAppDelegate.wireNotificationRouting(routing)
        try await Task.sleep(for: .milliseconds(50))

        #expect(routing.pendingItemID == nil)
    }

    @Test("Wire is idempotent w.r.t. a cleared queue (no replay on second wire)")
    func secondWireDoesNotReplay() async throws {
        resetStaticState()
        defer { resetStaticState() }

        let id = UUID()
        NakedPantreeAppDelegate.pendingNotificationItemIDs.append(id)

        let firstRouting = NotificationRoutingService()
        NakedPantreeAppDelegate.wireNotificationRouting(firstRouting)
        try await Task.sleep(for: .milliseconds(50))
        #expect(firstRouting.pendingItemID == id)

        // Wire a fresh routing service. The queue is now empty —
        // the second routing should NOT receive the original tap.
        let secondRouting = NotificationRoutingService()
        NakedPantreeAppDelegate.wireNotificationRouting(secondRouting)
        try await Task.sleep(for: .milliseconds(50))

        #expect(secondRouting.pendingItemID == nil)
    }
}
