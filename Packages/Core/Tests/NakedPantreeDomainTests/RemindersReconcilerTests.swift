import Foundation
import Testing
@testable import NakedPantreeDomain

/// Issue #155 — pin every reconciliation rule the spec calls out, plus
/// a few defensive cases (untagged reminders, duplicate tags, sentinel
/// resolution priority). The reconciler is pure, so these are
/// in-process Swift Testing cases with no actor / EventKit ceremony.
@Suite("RemindersReconciler")
struct RemindersReconcilerTests {
    // Shared fixture: one household, one location, two items.
    static let householdID = UUID()
    static let location = Location(
        id: UUID(),
        householdID: householdID,
        name: "Kitchen Pantry"
    )
    static let locationsByID: [Location.ID: Location] = [location.id: location]

    static func makeItem(
        id: UUID = UUID(),
        name: String,
        quantity: Int32 = 1,
        unit: NakedPantreeDomain.Unit = .count,
        needsRestocking: Bool = true
    ) -> Item {
        Item(
            id: id,
            locationID: location.id,
            name: name,
            quantity: quantity,
            unit: unit,
            needsRestocking: needsRestocking
        )
    }

    static func makeSnapshot(
        calendarItemIdentifier: String = UUID().uuidString,
        nakedPantreeID: UUID? = nil,
        title: String,
        isCompleted: Bool = false
    ) -> ReminderSnapshot {
        ReminderSnapshot(
            calendarItemIdentifier: calendarItemIdentifier,
            nakedPantreeID: nakedPantreeID,
            title: title,
            isCompleted: isCompleted
        )
    }

    // MARK: Empty / no-op cases

    @Test("Empty inputs yield an empty plan")
    func emptyInputs() {
        let plan = RemindersReconciler.plan(
            items: [],
            existing: [],
            locationsByID: Self.locationsByID
        )
        #expect(plan.isEmpty)
    }

    @Test("Untagged existing reminders are ignored entirely")
    func untaggedExistingIgnored() {
        let untagged = Self.makeSnapshot(
            nakedPantreeID: nil,
            title: "Whatever the user wrote"
        )
        let plan = RemindersReconciler.plan(
            items: [],
            existing: [untagged],
            locationsByID: Self.locationsByID
        )
        // No creates, no completions — the user's hand-added reminder
        // is off-limits.
        #expect(plan.isEmpty)
    }

    // MARK: Create branch

    @Test("Item with no existing reminder produces a Create with the right payload")
    func createWhenMissing() {
        let item = Self.makeItem(name: "Sourdough", quantity: 2, unit: .count)
        let plan = RemindersReconciler.plan(
            items: [item],
            existing: [],
            locationsByID: Self.locationsByID
        )
        #expect(plan.creates.count == 1)
        #expect(plan.titleUpdates.isEmpty)
        #expect(plan.completions.isEmpty)
        let payload = plan.creates[0].payload
        #expect(payload.title == "Sourdough")
        #expect(payload.nakedPantreeID == item.id)
        #expect(payload.url == ReminderTag.url(for: item.id))
        // Notes contain the sentinel and the user-friendly body.
        #expect(payload.notes.contains(ReminderTag.notesSentinel(for: item.id)))
        #expect(payload.notes.contains("Kitchen Pantry"))
        #expect(payload.notes.contains("2"))
    }

    @Test("Multiple creates are sorted by title for determinism")
    func createsAreSortedByTitle() {
        let zebra = Self.makeItem(name: "Zebra")
        let apple = Self.makeItem(name: "Apple")
        let plan = RemindersReconciler.plan(
            items: [zebra, apple],
            existing: [],
            locationsByID: Self.locationsByID
        )
        #expect(plan.creates.map(\.payload.title) == ["Apple", "Zebra"])
    }

    @Test("Unit .count omits the empty label so notes don't read '2  — Kitchen'")
    func notesOmitEmptyUnitLabel() {
        let item = Self.makeItem(name: "Apples", quantity: 2, unit: .count)
        let payload = RemindersReconciler.payload(
            for: item,
            locationsByID: Self.locationsByID
        )
        // Should be "[NP-ID:UUID]\n2 — Kitchen Pantry", not "2  — ...".
        #expect(payload.notes.contains("2 — Kitchen Pantry"))
        #expect(!payload.notes.contains("2  —"))
    }

    @Test("Missing location resolves to body without the location segment")
    func notesOmitMissingLocation() {
        let item = Self.makeItem(name: "Mystery", quantity: 1, unit: .count)
        let payload = RemindersReconciler.payload(
            for: item,
            // Empty lookup — location id won't resolve.
            locationsByID: [:]
        )
        let stripped = payload.notes.replacingOccurrences(
            of: ReminderTag.notesSentinel(for: item.id),
            with: ""
        )
        let body = stripped.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        #expect(body == "1")
    }

    // MARK: Leave / title-update branch

    @Test("Item already present and not completed produces no op")
    func leaveExistingActiveReminder() {
        let item = Self.makeItem(name: "Sourdough")
        let snapshot = Self.makeSnapshot(
            nakedPantreeID: item.id,
            title: "Sourdough"
        )
        let plan = RemindersReconciler.plan(
            items: [item],
            existing: [snapshot],
            locationsByID: Self.locationsByID
        )
        #expect(plan.isEmpty)
    }

    @Test("Renamed item with active existing reminder queues a title update")
    func updateTitleWhenItemRenamed() {
        let item = Self.makeItem(name: "Sourdough Bread")
        let existing = Self.makeSnapshot(
            calendarItemIdentifier: "ek-1",
            nakedPantreeID: item.id,
            title: "Sourdough"
        )
        let plan = RemindersReconciler.plan(
            items: [item],
            existing: [existing],
            locationsByID: Self.locationsByID
        )
        #expect(plan.creates.isEmpty)
        let expected = ReminderPlan.UpdateTitle(
            calendarItemIdentifier: "ek-1",
            newTitle: "Sourdough Bread"
        )
        #expect(plan.titleUpdates == [expected])
        #expect(plan.completions.isEmpty)
    }

    // MARK: Skip-when-completed branch

    @Test("Item with a completed existing reminder is skipped (no resurrect)")
    func skipCompletedExisting() {
        let item = Self.makeItem(name: "Sourdough")
        let completed = Self.makeSnapshot(
            nakedPantreeID: item.id,
            title: "Sourdough",
            isCompleted: true
        )
        let plan = RemindersReconciler.plan(
            items: [item],
            existing: [completed],
            locationsByID: Self.locationsByID
        )
        #expect(plan.isEmpty)
    }

    @Test("Renamed item whose existing reminder is completed is still skipped")
    func skipCompletedExistingEvenAfterRename() {
        let item = Self.makeItem(name: "Sourdough Bread")
        let completed = Self.makeSnapshot(
            calendarItemIdentifier: "ek-1",
            nakedPantreeID: item.id,
            title: "Sourdough",
            isCompleted: true
        )
        let plan = RemindersReconciler.plan(
            items: [item],
            existing: [completed],
            locationsByID: Self.locationsByID
        )
        // Don't queue an update against a completed reminder — that
        // would resurrect it from the user's perspective.
        #expect(plan.isEmpty)
    }

    // MARK: Mark-completed branch

    @Test("Existing reminder whose item is no longer in the list is marked completed")
    func markCompletedWhenItemRemovedFromList() {
        let removedItemID = UUID()
        let stale = Self.makeSnapshot(
            calendarItemIdentifier: "ek-stale",
            nakedPantreeID: removedItemID,
            title: "Yesterday's restock"
        )
        let plan = RemindersReconciler.plan(
            items: [],
            existing: [stale],
            locationsByID: Self.locationsByID
        )
        #expect(plan.creates.isEmpty)
        #expect(plan.titleUpdates.isEmpty)
        let expected = ReminderPlan.MarkCompleted(calendarItemIdentifier: "ek-stale")
        #expect(plan.completions == [expected])
    }

    @Test("Stale reminder that's already completed is a no-op")
    func staleCompletedReminderIsNoOp() {
        let removedItemID = UUID()
        let stale = Self.makeSnapshot(
            nakedPantreeID: removedItemID,
            title: "Yesterday's restock",
            isCompleted: true
        )
        let plan = RemindersReconciler.plan(
            items: [],
            existing: [stale],
            locationsByID: Self.locationsByID
        )
        #expect(plan.isEmpty)
    }

    // MARK: Idempotency

    @Test("Re-running the reconciler against the post-apply state yields an empty plan")
    func idempotentSecondRun() async throws {
        let item = Self.makeItem(name: "Sourdough")
        let firstPlan = RemindersReconciler.plan(
            items: [item],
            existing: [],
            locationsByID: Self.locationsByID
        )
        // Simulate a successful apply: the create lands as a tagged
        // active snapshot.
        let payload = firstPlan.creates[0].payload
        let postApply = Self.makeSnapshot(
            nakedPantreeID: payload.nakedPantreeID,
            title: payload.title,
            isCompleted: false
        )
        let secondPlan = RemindersReconciler.plan(
            items: [item],
            existing: [postApply],
            locationsByID: Self.locationsByID
        )
        #expect(secondPlan.isEmpty)
    }

    // MARK: Mixed scenarios

    @Test("Mixed inputs produce all three operation types in a single pass")
    func mixedInputs() {
        // Three items, three reminders, three different fates:
        //   A: in list, no existing reminder       → Create
        //   B: in list, existing active, renamed   → UpdateTitle
        //   C: not in list, existing active        → MarkCompleted
        // Plus an untagged reminder we must not touch.
        let itemA = Self.makeItem(name: "Apples")
        let itemB = Self.makeItem(name: "Bananas (organic)")
        let removedItemCID = UUID()
        let existingB = Self.makeSnapshot(
            calendarItemIdentifier: "ek-B",
            nakedPantreeID: itemB.id,
            title: "Bananas"
        )
        let existingC = Self.makeSnapshot(
            calendarItemIdentifier: "ek-C",
            nakedPantreeID: removedItemCID,
            title: "Cilantro"
        )
        let untagged = Self.makeSnapshot(
            calendarItemIdentifier: "ek-user",
            nakedPantreeID: nil,
            title: "Buy stamps"
        )
        let plan = RemindersReconciler.plan(
            items: [itemA, itemB],
            existing: [existingB, existingC, untagged],
            locationsByID: Self.locationsByID
        )
        #expect(plan.creates.count == 1)
        #expect(plan.creates[0].payload.title == "Apples")
        let expectedUpdate = ReminderPlan.UpdateTitle(
            calendarItemIdentifier: "ek-B",
            newTitle: "Bananas (organic)"
        )
        let expectedCompletion = ReminderPlan.MarkCompleted(
            calendarItemIdentifier: "ek-C"
        )
        #expect(plan.titleUpdates == [expectedUpdate])
        #expect(plan.completions == [expectedCompletion])
    }

    // MARK: Defensive — duplicate tags

    @Test("Duplicate tags resolve to first-wins, second is treated as untagged")
    func duplicateTagsFirstWins() {
        let item = Self.makeItem(name: "Sourdough")
        let first = Self.makeSnapshot(
            calendarItemIdentifier: "ek-1",
            nakedPantreeID: item.id,
            title: "Sourdough"
        )
        let dup = Self.makeSnapshot(
            calendarItemIdentifier: "ek-2",
            nakedPantreeID: item.id,
            title: "Sourdough"
        )
        let plan = RemindersReconciler.plan(
            items: [item],
            existing: [first, dup],
            locationsByID: Self.locationsByID
        )
        // First snapshot won the index lookup → no create, no title
        // update (titles match). The second is now "untagged" from
        // the cleanup pass's perspective because its id matches an
        // active item, so it's left alone too.
        #expect(plan.isEmpty)
    }
}
