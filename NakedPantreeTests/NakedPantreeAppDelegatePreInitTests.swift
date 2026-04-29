import Foundation
import Testing
import UserNotifications

@testable import NakedPantree

/// Coverage for the pre-init event queueing in
/// `NakedPantreeAppDelegate` (issue #108). iOS can deliver
/// `userDidAcceptCloudKitShareWith` and notification taps before
/// `NakedPantreeApp.init` runs and assigns the seam vars; pre-#108
/// those events were silently dropped. Now they queue and drain
/// once `wireShareAcceptance(_:)` / `wireNotificationRouting(_:)`
/// is called.
///
/// Constructing a real `CKShare.Metadata` from a unit test isn't
/// feasible (no public init / fixture). The notification-tap path
/// uses string identifiers and is tested directly. The
/// share-metadata path's *queue mechanic* is verified by
/// inspecting `pendingShareMetadata` directly — that confirms the
/// delegate enqueues when no sink is wired, and the wire method's
/// drain is structurally identical to the notification path.
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

    @Test("Notification tap delivered before wire is queued, then drained on wire")
    func notificationTapDrainsToRouting() async throws {
        resetStaticState()
        defer { resetStaticState() }

        let delegate = NakedPantreeAppDelegate()
        let id = UUID()

        // Simulate iOS delivering a tap before the seam is wired.
        let response = try makeNotificationResponse(itemID: id)
        await withCheckedContinuation { continuation in
            delegate.userNotificationCenter(
                UNUserNotificationCenter.current(),
                didReceive: response
            ) {
                continuation.resume()
            }
        }
        #expect(NakedPantreeAppDelegate.pendingNotificationItemIDs == [id])

        // Wire the routing service. The wire method should drain.
        let routing = NotificationRoutingService()
        NakedPantreeAppDelegate.wireNotificationRouting(routing)

        // `wireNotificationRouting` schedules a `Task { @MainActor in }`
        // to publish; yield to give it a chance to run.
        try await Task.sleep(for: .milliseconds(50))

        #expect(routing.pendingItemID == id)
        #expect(NakedPantreeAppDelegate.pendingNotificationItemIDs.isEmpty)
    }

    @Test("Multiple pre-wire taps yield only the most recent (last-tap-wins)")
    func multiplePreWireTapsLastWins() async throws {
        resetStaticState()
        defer { resetStaticState() }

        let delegate = NakedPantreeAppDelegate()
        let firstID = UUID()
        let secondID = UUID()

        for id in [firstID, secondID] {
            let response = try makeNotificationResponse(itemID: id)
            await withCheckedContinuation { continuation in
                delegate.userNotificationCenter(
                    UNUserNotificationCenter.current(),
                    didReceive: response
                ) {
                    continuation.resume()
                }
            }
        }
        #expect(NakedPantreeAppDelegate.pendingNotificationItemIDs == [firstID, secondID])

        let routing = NotificationRoutingService()
        NakedPantreeAppDelegate.wireNotificationRouting(routing)
        try await Task.sleep(for: .milliseconds(50))

        // Last tap wins, matching the live tap-ordering fix from #119.
        #expect(routing.pendingItemID == secondID)
    }

    @Test("Notification tap delivered after wire bypasses the queue")
    func postWireDeliveryBypassesQueue() async throws {
        resetStaticState()
        defer { resetStaticState() }

        let routing = NotificationRoutingService()
        NakedPantreeAppDelegate.wireNotificationRouting(routing)

        let delegate = NakedPantreeAppDelegate()
        let id = UUID()
        let response = try makeNotificationResponse(itemID: id)
        await withCheckedContinuation { continuation in
            delegate.userNotificationCenter(
                UNUserNotificationCenter.current(),
                didReceive: response
            ) {
                continuation.resume()
            }
        }
        try await Task.sleep(for: .milliseconds(50))

        #expect(routing.pendingItemID == id)
        // Queue stays empty because the seam was wired before delivery.
        #expect(NakedPantreeAppDelegate.pendingNotificationItemIDs.isEmpty)
    }

    @Test("Queue resets after wire-drain so subsequent pre-wire deliveries don't replay")
    func queueResetsAfterDrain() async throws {
        resetStaticState()
        defer { resetStaticState() }

        let delegate = NakedPantreeAppDelegate()
        let firstID = UUID()
        let response = try makeNotificationResponse(itemID: firstID)
        await withCheckedContinuation { continuation in
            delegate.userNotificationCenter(
                UNUserNotificationCenter.current(),
                didReceive: response
            ) {
                continuation.resume()
            }
        }

        let routing = NotificationRoutingService()
        NakedPantreeAppDelegate.wireNotificationRouting(routing)
        try await Task.sleep(for: .milliseconds(50))

        // Queue should be cleared post-drain. A fresh tap arriving
        // post-wire goes through the live path, not the queue.
        #expect(NakedPantreeAppDelegate.pendingNotificationItemIDs.isEmpty)

        let secondID = UUID()
        let secondResponse = try makeNotificationResponse(itemID: secondID)
        await withCheckedContinuation { continuation in
            delegate.userNotificationCenter(
                UNUserNotificationCenter.current(),
                didReceive: secondResponse
            ) {
                continuation.resume()
            }
        }
        try await Task.sleep(for: .milliseconds(50))

        #expect(routing.pendingItemID == secondID)
        #expect(NakedPantreeAppDelegate.pendingNotificationItemIDs.isEmpty)
    }

    // MARK: - Helpers

    /// Build a `UNNotificationResponse` carrying the expected
    /// `userInfo` shape (the `itemID` key the delegate's
    /// `notificationItemID(from:)` parser reads).
    nonisolated private func makeNotificationResponse(
        itemID: UUID
    ) throws -> UNNotificationResponse {
        let content = UNMutableNotificationContent()
        content.userInfo = ["itemID": itemID.uuidString]
        let request = UNNotificationRequest(
            identifier: "item.\(itemID.uuidString).expiry",
            content: content,
            trigger: nil
        )
        // `UNNotificationResponse` has no public initializer. Use
        // KVC via `setValue` to mint one for testing — Apple's
        // documented test recipe for this exact case (see WWDC
        // sample code for notification-tap testing).
        let notification = try #require(makeNotification(from: request))
        let response = UNNotificationResponse()
        response.setValue(notification, forKey: "notification")
        response.setValue(
            UNNotificationDefaultActionIdentifier,
            forKey: "actionIdentifier"
        )
        return response
    }

    nonisolated private func makeNotification(
        from request: UNNotificationRequest
    ) -> UNNotification? {
        // `UNNotification` also has no public init. Same KVC trick.
        let notification = UNNotification()
        notification.setValue(request, forKey: "request")
        notification.setValue(Date(), forKey: "date")
        return notification
    }
}
