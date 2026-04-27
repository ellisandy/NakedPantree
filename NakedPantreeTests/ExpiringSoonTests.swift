import Foundation
import NakedPantreeDomain
import Testing
@testable import NakedPantree

@Suite("Expiring Soon filter and sort")
struct ExpiringSoonFilterTests {
    private static func makeItem(name: String, expiresAt: Date?) -> Item {
        Item(locationID: UUID(), name: name, expiresAt: expiresAt)
    }

    @Test("Items without an expiry are dropped")
    func dropsNilExpiry() {
        let nilItem = Self.makeItem(name: "Pasta", expiresAt: nil)
        let withExpiry = Self.makeItem(name: "Milk", expiresAt: Date())
        let result = itemsExpiringSoon([nilItem, withExpiry])
        #expect(result.map(\.id) == [withExpiry.id])
    }

    @Test("Result sorts ascending so past-expiry leads, near-future follows")
    func sortsAscendingByExpiresAt() {
        let now = Date()
        let lastWeek = Self.makeItem(name: "Old", expiresAt: now.addingTimeInterval(-7 * 86400))
        let tomorrow = Self.makeItem(name: "Soon", expiresAt: now.addingTimeInterval(86400))
        let nextMonth = Self.makeItem(name: "Later", expiresAt: now.addingTimeInterval(30 * 86400))

        let result = itemsExpiringSoon([nextMonth, lastWeek, tomorrow])

        #expect(result.map(\.id) == [lastWeek.id, tomorrow.id, nextMonth.id])
    }

    @Test("Empty input returns empty output")
    func emptyInputReturnsEmpty() {
        #expect(itemsExpiringSoon([]).isEmpty)
    }

    @Test("All-nil input returns empty output")
    func allNilInputReturnsEmpty() {
        let items = [
            Self.makeItem(name: "A", expiresAt: nil),
            Self.makeItem(name: "B", expiresAt: nil),
        ]
        #expect(itemsExpiringSoon(items).isEmpty)
    }

    @Test("Stable when two items share the same expiry")
    func sharedExpiryDoesNotCrash() {
        let shared = Date()
        let first = Self.makeItem(name: "First", expiresAt: shared)
        let second = Self.makeItem(name: "Second", expiresAt: shared)
        let result = itemsExpiringSoon([first, second])
        // Both must appear; relative order isn't asserted because the
        // sort isn't required to be stable on ties.
        #expect(Set(result.map(\.id)) == Set([first.id, second.id]))
        #expect(result.count == 2)
    }
}
