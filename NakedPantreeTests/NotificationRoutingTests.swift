import Foundation
import Testing
@testable import NakedPantree

@Suite("Notification routing payload parsing")
struct NotificationItemIDParsingTests {
    @Test("Valid uuid string round-trips")
    func validUUIDStringParses() throws {
        let id = UUID()
        let payload: [AnyHashable: Any] = ["itemID": id.uuidString]
        let parsed = try #require(notificationItemID(from: payload))
        #expect(parsed == id)
    }

    @Test("Missing itemID key returns nil")
    func missingKeyReturnsNil() {
        let payload: [AnyHashable: Any] = ["other": "value"]
        #expect(notificationItemID(from: payload) == nil)
    }

    @Test("Non-string itemID value returns nil")
    func nonStringValueReturnsNil() {
        // Defensive: a malformed payload from a third party (or a
        // hand-crafted notification in tests) shouldn't crash the
        // routing layer. UUIDs are encoded as strings per the
        // scheduler's contract.
        let payload: [AnyHashable: Any] = ["itemID": 42]
        #expect(notificationItemID(from: payload) == nil)
    }

    @Test("Malformed UUID string returns nil")
    func malformedUUIDStringReturnsNil() {
        let payload: [AnyHashable: Any] = ["itemID": "not-a-uuid"]
        #expect(notificationItemID(from: payload) == nil)
    }

    @Test("Empty payload returns nil")
    func emptyPayloadReturnsNil() {
        #expect(notificationItemID(from: [:]) == nil)
    }
}

@Suite("Notification routing service")
@MainActor
struct NotificationRoutingServiceTests {
    @Test("Pending itemID round-trips through the service")
    func pendingIDRoundTrips() {
        let service = NotificationRoutingService()
        let id = UUID()
        #expect(service.pendingItemID == nil)
        service.pendingItemID = id
        #expect(service.pendingItemID == id)
        service.pendingItemID = nil
        #expect(service.pendingItemID == nil)
    }
}
