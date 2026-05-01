import Foundation
import Testing

@testable import NakedPantree
@testable import NakedPantreeDomain

/// Issue #155 — pin the orchestrator state machine. The reconciler
/// itself is tested in the Domain package; here we drive the
/// permission → list-pick → reconcile → apply flow against the
/// `InMemoryRemindersService` stub and assert the right state lands
/// in `coordinator.state` at each step.
///
/// `@MainActor` because `PushToRemindersCoordinator` is `@MainActor`
/// and `RemindersListPreference` is `@MainActor`. Swift Testing's
/// `@Test` methods inherit isolation from the suite when none is
/// specified, so the assertions read mutable state cleanly.
@Suite("PushToRemindersCoordinator")
@MainActor
struct PushToRemindersCoordinatorTests {
    // Shared fixture: one household, one location, two items flagged.
    static let listID = "test-list"
    static let listSummary = RemindersListSummary(
        id: listID,
        title: "Groceries"
    )
    static let location = Location(
        householdID: UUID(),
        name: "Kitchen Pantry"
    )
    static var locationsByID: [Location.ID: Location] {
        [location.id: location]
    }

    static func makeItems() -> [Item] {
        [
            Item(locationID: location.id, name: "Sourdough"),
            Item(locationID: location.id, name: "Apples"),
        ]
    }

    // MARK: First-push happy path

    @Test("First push without a stored list publishes needsListPick")
    func firstPushNeedsListPick() async {
        let service = InMemoryRemindersService(
            lists: [Self.listSummary],
            rowsByListID: [Self.listID: []]
        )
        let preference = RemindersListPreference()
        let coordinator = PushToRemindersCoordinator(
            service: service,
            preference: preference
        )

        await coordinator.requestPush(
            items: Self.makeItems(),
            locationsByID: Self.locationsByID
        )

        guard case .needsListPick(let lists) = coordinator.state else {
            Issue.record("Expected needsListPick, got \(coordinator.state)")
            return
        }
        #expect(lists == [Self.listSummary])
    }

    @Test("Picking a list runs the push and lands in completed")
    func pickingListCompletesPush() async {
        let service = InMemoryRemindersService(
            lists: [Self.listSummary],
            rowsByListID: [Self.listID: []]
        )
        let preference = RemindersListPreference()
        let coordinator = PushToRemindersCoordinator(
            service: service,
            preference: preference
        )

        // Step 1 — request push, lands in needsListPick.
        await coordinator.requestPush(
            items: Self.makeItems(),
            locationsByID: Self.locationsByID
        )
        // Step 2 — pick.
        await coordinator.setChosenListID(
            Self.listID,
            items: Self.makeItems(),
            locationsByID: Self.locationsByID
        )

        guard case .completed(let summary) = coordinator.state else {
            Issue.record("Expected completed, got \(coordinator.state)")
            return
        }
        #expect(summary.createdCount == 2)
        #expect(summary.updatedCount == 0)
        #expect(summary.completedCount == 0)
        #expect(summary.listTitle == "Groceries")
        #expect(preference.listID == Self.listID)
    }

    // MARK: Second-push idempotency

    @Test("Second push with stored list creates nothing on equal state")
    func secondPushIsIdempotent() async {
        let service = InMemoryRemindersService(
            lists: [Self.listSummary],
            rowsByListID: [Self.listID: []]
        )
        let preference = RemindersListPreference()
        let coordinator = PushToRemindersCoordinator(
            service: service,
            preference: preference
        )
        // Capture stable items so the second push has the same item
        // ids — `makeItems()` mints fresh UUIDs each call which would
        // make the second push see ALL items as "new".
        let items = Self.makeItems()

        // First push — picks + creates.
        await coordinator.requestPush(
            items: items,
            locationsByID: Self.locationsByID
        )
        await coordinator.setChosenListID(
            Self.listID,
            items: items,
            locationsByID: Self.locationsByID
        )
        coordinator.acknowledge()

        // Second push with the same items — totalChanges should be 0.
        await coordinator.requestPush(
            items: items,
            locationsByID: Self.locationsByID
        )
        guard case .completed(let summary) = coordinator.state else {
            Issue.record("Expected completed, got \(coordinator.state)")
            return
        }
        #expect(summary.totalChanges == 0)
    }

    // MARK: Permission denied

    @Test("Denied access publishes permissionDenied")
    func deniedAccessPublishesPermissionDenied() async {
        let service = InMemoryRemindersService(
            accessStatus: .denied,
            lists: [Self.listSummary],
            rowsByListID: [Self.listID: []]
        )
        let preference = RemindersListPreference()
        let coordinator = PushToRemindersCoordinator(
            service: service,
            preference: preference
        )

        await coordinator.requestPush(
            items: Self.makeItems(),
            locationsByID: Self.locationsByID
        )

        #expect(coordinator.state == .permissionDenied)
    }

    @Test("Restricted access publishes permissionDenied")
    func restrictedAccessPublishesPermissionDenied() async {
        let service = InMemoryRemindersService(
            accessStatus: .restricted,
            lists: [Self.listSummary],
            rowsByListID: [Self.listID: []]
        )
        let preference = RemindersListPreference()
        let coordinator = PushToRemindersCoordinator(
            service: service,
            preference: preference
        )

        await coordinator.requestPush(
            items: Self.makeItems(),
            locationsByID: Self.locationsByID
        )

        #expect(coordinator.state == .permissionDenied)
    }

    // MARK: Stored list deleted

    @Test("Stored list missing from availableLists clears + re-prompts")
    func storedListMissingClearsAndRePrompts() async {
        let stale = "deleted-list-id"
        let service = InMemoryRemindersService(
            lists: [Self.listSummary],
            rowsByListID: [Self.listID: []]
        )
        let preference = RemindersListPreference()
        preference.listID = stale
        let coordinator = PushToRemindersCoordinator(
            service: service,
            preference: preference
        )

        await coordinator.requestPush(
            items: Self.makeItems(),
            locationsByID: Self.locationsByID
        )

        guard case .needsListPick(let lists) = coordinator.state else {
            Issue.record("Expected needsListPick, got \(coordinator.state)")
            return
        }
        #expect(lists == [Self.listSummary])
        #expect(preference.listID == nil)
    }

    // MARK: Cancel + acknowledge

    @Test("cancelListPick returns to idle")
    func cancelListPickReturnsToIdle() async {
        let service = InMemoryRemindersService(
            lists: [Self.listSummary],
            rowsByListID: [Self.listID: []]
        )
        let preference = RemindersListPreference()
        let coordinator = PushToRemindersCoordinator(
            service: service,
            preference: preference
        )

        await coordinator.requestPush(
            items: Self.makeItems(),
            locationsByID: Self.locationsByID
        )
        coordinator.cancelListPick()

        #expect(coordinator.state == .idle)
        #expect(preference.listID == nil)
    }

    @Test("acknowledge after completed returns to idle")
    func acknowledgeAfterCompletedReturnsToIdle() async {
        let service = InMemoryRemindersService(
            lists: [Self.listSummary],
            rowsByListID: [Self.listID: []]
        )
        let preference = RemindersListPreference()
        preference.listID = Self.listID
        let coordinator = PushToRemindersCoordinator(
            service: service,
            preference: preference
        )

        await coordinator.requestPush(
            items: Self.makeItems(),
            locationsByID: Self.locationsByID
        )
        coordinator.acknowledge()

        #expect(coordinator.state == .idle)
    }

    // MARK: Mark-completed branch via service

    @Test("Item removed from list since last push lands as a completion")
    func itemRemovedSinceLastPushIsCompleted() async throws {
        // Seed an existing tagged reminder for an item that's no
        // longer on the restock list. The reconciler should queue a
        // mark-completed; the coordinator should report that in the
        // summary.
        let removedItem = Item(
            locationID: Self.location.id,
            name: "Yesterday's restock"
        )
        let staleRow = InMemoryRemindersService.Row(
            calendarItemIdentifier: "ek-stale",
            nakedPantreeID: removedItem.id,
            title: removedItem.name,
            url: ReminderTag.url(for: removedItem.id)
        )
        let service = InMemoryRemindersService(
            lists: [Self.listSummary],
            rowsByListID: [Self.listID: [staleRow]]
        )
        let preference = RemindersListPreference()
        preference.listID = Self.listID
        let coordinator = PushToRemindersCoordinator(
            service: service,
            preference: preference
        )

        await coordinator.requestPush(
            items: Self.makeItems(),
            locationsByID: Self.locationsByID
        )

        guard case .completed(let summary) = coordinator.state else {
            Issue.record("Expected completed, got \(coordinator.state)")
            return
        }
        #expect(summary.completedCount == 1)
        #expect(summary.createdCount == 2)
    }
}
