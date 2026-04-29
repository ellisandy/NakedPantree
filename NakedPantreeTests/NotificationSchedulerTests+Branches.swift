import Foundation
import Testing
import UserNotifications

@testable import NakedPantree
@testable import NakedPantreeDomain

/// Branch coverage for `NotificationScheduler` instance methods —
/// issue #113. Pre-#113 these methods reached `UNUserNotificationCenter`
/// directly, which CI couldn't drive (no notification permissions
/// granted to a freshly-built host app on a sandboxed simulator).
/// apps#125 added the `NotificationCenterServicing` protocol seam so
/// the stub below can record every call and the branches are now
/// pinned.
///
/// **Scope:** authorization-gate behavior, nil-expiry / past-expiry
/// cancel paths, and the `resync` permission-gate bail (the
/// load-bearing cold-launch safety net per the Phase 4.3 contract:
/// "We never prompt at launch"). The pure helper functions
/// (`expiryNotificationTriggerDate`, identifier parsers,
/// `bundleSameDayExpiries`) already have direct test coverage in
/// the older `NotificationScheduler*Tests` suites — not duplicated
/// here.
@Suite("NotificationScheduler branches")
struct NotificationSchedulerBranchTests {
    // MARK: - cancel

    @Test("cancel(itemID:) removes the deterministic identifier")
    @MainActor
    func cancelRemovesIdentifier() async throws {
        let center = StubNotificationCenter()
        let scheduler = NotificationScheduler(servicing: center)
        let itemID = UUID()
        await scheduler.cancel(itemID: itemID)

        let removed = await center.removedIdentifiersBatches
        #expect(removed.count == 1)
        #expect(removed.first == [NotificationScheduler.identifier(for: itemID)])
    }

    // MARK: - scheduleIfNeeded

    @Test("scheduleIfNeeded with nil expiry removes any pending request and does not add")
    @MainActor
    func scheduleIfNeededNilExpiryCancels() async throws {
        let center = StubNotificationCenter()
        let scheduler = NotificationScheduler(servicing: center)
        let item = Item(locationID: UUID(), name: "Olive oil")
        await scheduler.scheduleIfNeeded(for: item)

        let removed = await center.removedIdentifiersBatches
        let added = await center.addedRequests
        #expect(removed.count == 1, "Expected one removal pass for the nil-expiry case.")
        #expect(removed.first == [NotificationScheduler.identifier(for: item.id)])
        #expect(added.isEmpty, "Nil expiry must not schedule a request.")
    }

    @Test("scheduleIfNeeded with past trigger removes pending request and does not add")
    @MainActor
    func scheduleIfNeededPastTriggerCancels() async throws {
        let center = StubNotificationCenter()
        let scheduler = NotificationScheduler(servicing: center)
        // Expiry is yesterday — `expiryNotificationTriggerDate` returns
        // nil because the lead-time window has already passed.
        let yesterday = Date(timeIntervalSinceNow: -24 * 60 * 60)
        let item = Item(
            locationID: UUID(),
            name: "Spinach",
            expiresAt: yesterday
        )
        await scheduler.scheduleIfNeeded(for: item)

        let added = await center.addedRequests
        let removed = await center.removedIdentifiersBatches
        #expect(added.isEmpty, "Past trigger must not add a request.")
        #expect(removed.count == 1, "Expected one removal pass for the past-trigger case.")
    }

    @Test("scheduleIfNeeded silently skips when authorization is denied")
    @MainActor
    func scheduleIfNeededDeniedSkips() async throws {
        let center = StubNotificationCenter()
        await center.setAuthorizationStatus(.denied)
        let scheduler = NotificationScheduler(servicing: center)
        // Future expiry well within the lead-time window.
        let futureExpiry = Date(timeIntervalSinceNow: 10 * 24 * 60 * 60)
        let item = Item(
            locationID: UUID(),
            name: "Yogurt",
            expiresAt: futureExpiry
        )
        await scheduler.scheduleIfNeeded(for: item)

        let added = await center.addedRequests
        #expect(added.isEmpty, "Denied authorization must not schedule.")
    }

    @Test("scheduleIfNeeded with authorization adds a request carrying the item id in userInfo")
    @MainActor
    func scheduleIfNeededAuthorizedSchedules() async throws {
        let center = StubNotificationCenter()
        await center.setAuthorizationStatus(.authorized)
        let scheduler = NotificationScheduler(servicing: center)
        let futureExpiry = Date(timeIntervalSinceNow: 10 * 24 * 60 * 60)
        let item = Item(
            locationID: UUID(),
            name: "Yogurt",
            expiresAt: futureExpiry
        )
        await scheduler.scheduleIfNeeded(for: item)

        let added = await center.addedRequests
        #expect(added.count == 1)
        let request = try #require(added.first)
        #expect(request.identifier == NotificationScheduler.identifier(for: item.id))
        #expect(request.content.title == item.name)
        #expect(request.content.userInfo["itemID"] as? String == item.id.uuidString)
    }

    // MARK: - resync permission gate

    @Test("resync bails when authorization is .notDetermined (never prompts at launch)")
    @MainActor
    func resyncNotDeterminedBails() async throws {
        let center = StubNotificationCenter()
        await center.setAuthorizationStatus(.notDetermined)
        let scheduler = NotificationScheduler(servicing: center)
        await scheduler.resync(currentItems: [])

        let auth = await center.requestAuthorizationCallCount
        let added = await center.addedRequests
        #expect(auth == 0, "resync must not prompt — Phase 4.3 contract.")
        #expect(added.isEmpty, "resync must not schedule when notDetermined.")
    }

    @Test("resync bails when authorization is .denied")
    @MainActor
    func resyncDeniedBails() async throws {
        let center = StubNotificationCenter()
        await center.setAuthorizationStatus(.denied)
        let scheduler = NotificationScheduler(servicing: center)
        // Items present so we can verify nothing got scheduled.
        let item = Item(
            id: UUID(),
            name: "Spinach",
            quantity: 1,
            unit: .count,
            expiresAt: Date(timeIntervalSinceNow: 10 * 24 * 60 * 60),
            notes: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        await scheduler.resync(currentItems: [item])

        let added = await center.addedRequests
        let removed = await center.removedIdentifiersBatches
        #expect(added.isEmpty)
        #expect(removed.isEmpty, "resync must not even sweep stale ids when denied.")
    }
}

// MARK: - Stub

/// Actor-based stub that records every call. Lives at file scope so
/// the suite types (which are `MainActor`-isolated by virtue of the
/// `@MainActor` test annotations) can construct it from any test
/// without isolation gymnastics.
actor StubNotificationCenter: NotificationCenterServicing {
    private var status: UNAuthorizationStatus = .authorized
    private var grant: Bool = true
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedIdentifiersBatches: [[String]] = []
    private var pendingIdentifiersValue: [String] = []
    private(set) var requestAuthorizationCallCount: Int = 0
    private var addError: Error?

    func setAuthorizationStatus(_ value: UNAuthorizationStatus) {
        status = value
    }
    func setAuthorizationGrant(_ value: Bool) {
        grant = value
    }
    func setPendingIdentifiers(_ ids: [String]) {
        pendingIdentifiersValue = ids
    }
    func setAddError(_ error: Error) {
        addError = error
    }

    // MARK: NotificationCenterServicing

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func add(_ request: UNNotificationRequest) async throws {
        if let addError {
            throw addError
        }
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        removedIdentifiersBatches.append(identifiers)
        pendingIdentifiersValue.removeAll { identifiers.contains($0) }
    }

    func pendingNotificationIdentifiers() async -> [String] {
        pendingIdentifiersValue
    }

    func requestAuthorization() async throws -> Bool {
        requestAuthorizationCallCount += 1
        return grant
    }
}
