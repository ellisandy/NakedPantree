import Foundation
import Testing
@testable import NakedPantreeDomain

/// Issue #155 — pin the in-memory stub's behavior so PR B's
/// orchestrator + UI tests have a trustworthy fake. Production code
/// uses `EventKitRemindersService` (App target); this fake is the
/// preview / snapshot / EMPTY_STORE / unit-test surface.
@Suite("InMemoryRemindersService")
struct InMemoryRemindersServiceTests {
    static let listID = "list-1"
    static let listSummary = RemindersListSummary(
        id: listID,
        title: "Groceries"
    )

    @Test("Granted access returns the seeded lists")
    func grantedReturnsLists() async throws {
        let service = InMemoryRemindersService(
            lists: [Self.listSummary],
            rowsByListID: [Self.listID: []]
        )
        let lists = try await service.availableLists()
        #expect(lists == [Self.listSummary])
    }

    @Test("Denied access throws accessNotGranted from every read/write")
    func deniedThrows() async {
        let service = InMemoryRemindersService(
            accessStatus: .denied,
            lists: [Self.listSummary],
            rowsByListID: [Self.listID: []]
        )
        await #expect(throws: RemindersServiceError.accessNotGranted) {
            _ = try await service.availableLists()
        }
        await #expect(throws: RemindersServiceError.accessNotGranted) {
            _ = try await service.snapshots(in: Self.listID)
        }
        await #expect(throws: RemindersServiceError.accessNotGranted) {
            try await service.apply(ReminderPlan(), in: Self.listID)
        }
    }

    @Test("snapshots resolves nakedPantreeID from URL or notes")
    func snapshotsResolveIdentity() async throws {
        let urlID = UUID()
        let notesID = UUID()
        let url = try #require(ReminderTag.url(for: urlID))
        let urlRow = InMemoryRemindersService.Row(
            calendarItemIdentifier: "ek-url",
            title: "Bread",
            url: url
        )
        let notesRow = InMemoryRemindersService.Row(
            calendarItemIdentifier: "ek-notes",
            title: "Milk",
            notes: ReminderTag.notesSentinel(for: notesID)
        )
        let userRow = InMemoryRemindersService.Row(
            calendarItemIdentifier: "ek-user",
            title: "Stamps"
        )
        let service = InMemoryRemindersService(
            lists: [Self.listSummary],
            rowsByListID: [Self.listID: [urlRow, notesRow, userRow]]
        )
        let snapshots = try await service.snapshots(in: Self.listID)
        #expect(snapshots.count == 3)
        #expect(snapshots[0].nakedPantreeID == urlID)
        #expect(snapshots[1].nakedPantreeID == notesID)
        #expect(snapshots[2].nakedPantreeID == nil)
    }

    @Test("apply persists creates so a follow-up snapshots call sees them")
    func applyPersistsCreates() async throws {
        let service = InMemoryRemindersService(
            lists: [Self.listSummary],
            rowsByListID: [Self.listID: []]
        )
        let itemID = UUID()
        let payload = ReminderPayload(
            title: "Sourdough",
            notes: "\(ReminderTag.notesSentinel(for: itemID))\n2 — Kitchen",
            url: ReminderTag.url(for: itemID),
            nakedPantreeID: itemID
        )
        let plan = ReminderPlan(creates: [.init(payload: payload)])
        try await service.apply(plan, in: Self.listID)
        let snapshots = try await service.snapshots(in: Self.listID)
        #expect(snapshots.count == 1)
        #expect(snapshots[0].title == "Sourdough")
        #expect(snapshots[0].nakedPantreeID == itemID)
        #expect(snapshots[0].isCompleted == false)
    }

    @Test("apply respects titleUpdate + markCompleted operations")
    func applyMutatesExistingRows() async throws {
        let itemID = UUID()
        let seedRow = InMemoryRemindersService.Row(
            calendarItemIdentifier: "ek-seed",
            nakedPantreeID: itemID,
            title: "Old name",
            url: ReminderTag.url(for: itemID)
        )
        let staleRow = InMemoryRemindersService.Row(
            calendarItemIdentifier: "ek-stale",
            nakedPantreeID: UUID(),
            title: "Yesterday",
            url: ReminderTag.url(for: UUID())
        )
        let service = InMemoryRemindersService(
            lists: [Self.listSummary],
            rowsByListID: [Self.listID: [seedRow, staleRow]]
        )
        let plan = ReminderPlan(
            titleUpdates: [
                .init(calendarItemIdentifier: "ek-seed", newTitle: "New name")
            ],
            completions: [
                .init(calendarItemIdentifier: "ek-stale")
            ]
        )
        try await service.apply(plan, in: Self.listID)
        let rows = await service.rows(in: Self.listID)
        let seed = try #require(rows.first { $0.calendarItemIdentifier == "ek-seed" })
        let stale = try #require(rows.first { $0.calendarItemIdentifier == "ek-stale" })
        #expect(seed.title == "New name")
        #expect(seed.isCompleted == false)
        #expect(stale.isCompleted)
    }

    @Test("apply against an unknown list throws listNotFound")
    func applyToUnknownListThrows() async {
        let service = InMemoryRemindersService(lists: [], rowsByListID: [:])
        await #expect(throws: RemindersServiceError.listNotFound(id: "nope")) {
            try await service.apply(ReminderPlan(), in: "nope")
        }
    }
}
