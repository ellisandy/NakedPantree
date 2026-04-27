import Foundation
import Testing
@testable import NakedPantree

@Suite("Notification identifier parsing")
struct NotificationIdentifierParsingTests {
    @Test("Round-trips a scheduler-produced identifier")
    func roundTripsValid() throws {
        let id = UUID()
        let identifier = NotificationScheduler.identifier(for: id)
        let parsed = try #require(parseExpiryNotificationItemID(fromIdentifier: identifier))
        #expect(parsed == id)
    }

    @Test("Returns nil for the wrong prefix")
    func wrongPrefixReturnsNil() {
        let id = UUID()
        let identifier = "lowstock.\(id.uuidString).expiry"
        #expect(parseExpiryNotificationItemID(fromIdentifier: identifier) == nil)
    }

    @Test("Returns nil for the wrong suffix")
    func wrongSuffixReturnsNil() {
        let id = UUID()
        let identifier = "item.\(id.uuidString).reminder"
        #expect(parseExpiryNotificationItemID(fromIdentifier: identifier) == nil)
    }

    @Test("Returns nil for malformed UUID middle segment")
    func malformedUUIDReturnsNil() {
        let identifier = "item.not-a-uuid.expiry"
        #expect(parseExpiryNotificationItemID(fromIdentifier: identifier) == nil)
    }

    @Test("Returns nil for an identifier with no dots")
    func noDotsReturnsNil() {
        #expect(parseExpiryNotificationItemID(fromIdentifier: "garbage") == nil)
    }

    @Test("Returns nil for the empty string")
    func emptyStringReturnsNil() {
        #expect(parseExpiryNotificationItemID(fromIdentifier: "") == nil)
    }

    @Test("Returns nil for too many dotted segments")
    func tooManySegmentsReturnsNil() {
        let id = UUID()
        let identifier = "item.\(id.uuidString).expiry.extra"
        #expect(parseExpiryNotificationItemID(fromIdentifier: identifier) == nil)
    }
}

@Suite("Stale-identifier diff")
struct StaleExpiryIdentifiersTests {
    @Test("Identifiers whose item is gone are returned for cancellation")
    func returnsStaleIdentifiers() {
        let kept = UUID()
        let removed = UUID()
        let pending = [
            NotificationScheduler.identifier(for: kept),
            NotificationScheduler.identifier(for: removed),
        ]
        let stale = staleExpiryIdentifiers(
            pending: pending,
            currentItemIDs: [kept]
        )
        #expect(stale == [NotificationScheduler.identifier(for: removed)])
    }

    @Test("Empty current item set cancels everything matching the schema")
    func emptyCurrentSetCancelsAll() {
        let first = UUID()
        let second = UUID()
        let pending = [
            NotificationScheduler.identifier(for: first),
            NotificationScheduler.identifier(for: second),
        ]
        let stale = staleExpiryIdentifiers(pending: pending, currentItemIDs: [])
        #expect(Set(stale) == Set(pending))
    }

    @Test("Foreign identifiers are passed through, not cancelled")
    func ignoresUnknownSchemaIdentifiers() {
        // A future scheduler kind (e.g. low-stock alerts) must not have
        // its requests collateral-cancelled by this expiry sweep.
        let foreign = "lowstock.\(UUID().uuidString).alert"
        let stale = staleExpiryIdentifiers(
            pending: [foreign],
            currentItemIDs: []
        )
        #expect(stale.isEmpty)
    }

    @Test("All current — nothing stale")
    func nothingStaleWhenAllPresent() {
        let first = UUID()
        let second = UUID()
        let pending = [
            NotificationScheduler.identifier(for: first),
            NotificationScheduler.identifier(for: second),
        ]
        let stale = staleExpiryIdentifiers(
            pending: pending,
            currentItemIDs: [first, second]
        )
        #expect(stale.isEmpty)
    }

    @Test("Empty pending — nothing stale")
    func emptyPendingReturnsEmpty() {
        let stale = staleExpiryIdentifiers(
            pending: [],
            currentItemIDs: [UUID(), UUID()]
        )
        #expect(stale.isEmpty)
    }
}
