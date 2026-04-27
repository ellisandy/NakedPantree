import Foundation
import NakedPantreeDomain
import Testing
@testable import NakedPantree

@Suite("Recently Added sort")
struct RecentlyAddedSortTests {
    private static func makeItem(name: String, createdAt: Date) -> Item {
        Item(locationID: UUID(), name: name, createdAt: createdAt)
    }

    @Test("Sort is descending by createdAt — newest first")
    func sortsDescendingByCreatedAt() {
        let now = Date()
        let oldest = Self.makeItem(name: "First", createdAt: now.addingTimeInterval(-86400 * 7))
        let middle = Self.makeItem(name: "Middle", createdAt: now.addingTimeInterval(-86400))
        let newest = Self.makeItem(name: "Newest", createdAt: now)

        let result = itemsRecentlyAdded([oldest, middle, newest])

        #expect(result.map(\.id) == [newest.id, middle.id, oldest.id])
    }

    @Test("Empty input returns empty output")
    func emptyInputReturnsEmpty() {
        #expect(itemsRecentlyAdded([]).isEmpty)
    }

    @Test("Items with the same createdAt both appear")
    func sameCreatedAtBothAppear() {
        let shared = Date()
        let first = Self.makeItem(name: "First", createdAt: shared)
        let second = Self.makeItem(name: "Second", createdAt: shared)
        let result = itemsRecentlyAdded([first, second])
        #expect(Set(result.map(\.id)) == Set([first.id, second.id]))
        #expect(result.count == 2)
    }

    @Test("Items with no expiry are still included — Recently Added is sort-only, not filter")
    func includesItemsWithoutExpiry() {
        let now = Date()
        let withExpiry = Item(
            locationID: UUID(),
            name: "Milk",
            expiresAt: now.addingTimeInterval(86400),
            createdAt: now
        )
        let withoutExpiry = Item(
            locationID: UUID(),
            name: "Pasta",
            expiresAt: nil,
            createdAt: now.addingTimeInterval(-3600)
        )
        let result = itemsRecentlyAdded([withoutExpiry, withExpiry])
        #expect(result.map(\.id) == [withExpiry.id, withoutExpiry.id])
    }
}
