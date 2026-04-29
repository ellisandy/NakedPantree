import Foundation
import UserNotifications

/// Protocol seam over the slice of `UNUserNotificationCenter` that
/// `NotificationScheduler` actually uses (issue #113). Lets test code
/// drive the scheduler's branching paths (nil-expiry cancel,
/// past-trigger cancel, authorization gate, scheduling content,
/// resync's permission-gate bail) without spinning up the system
/// notification center on the simulator — which doesn't grant the
/// host process notification permissions and so makes the production
/// branches unobservable.
///
/// **API shape rationale.** Each method returns a `Sendable` value
/// or `Void`. The system `UNNotificationSettings` type isn't
/// `Sendable`-compliant, so `authorizationStatus()` returns the
/// `UNAuthorizationStatus` enum directly instead of the full
/// settings object. Likewise, `pendingNotificationIdentifiers()`
/// returns just the identifier strings rather than the
/// (non-Sendable) `[UNNotificationRequest]` array — the scheduler
/// only ever needs the identifiers for its sweep step.
public protocol NotificationCenterServicing: Sendable {
    /// Equivalent to `UNUserNotificationCenter.notificationSettings().authorizationStatus`.
    func authorizationStatus() async -> UNAuthorizationStatus

    /// Equivalent to `UNUserNotificationCenter.add(_:)`. Marked
    /// `sending` so an `actor` conformer (e.g. the test stub) can
    /// receive a non-`Sendable` `UNNotificationRequest` from a
    /// non-isolated caller — Swift 6's ownership-transfer marker
    /// gives the compiler enough information to know the caller
    /// won't touch the request after handing it off.
    func add(_ request: sending UNNotificationRequest) async throws

    /// Equivalent to `UNUserNotificationCenter.removePendingNotificationRequests(withIdentifiers:)`.
    /// `async` even though the live call is synchronous — keeps the
    /// stub free to use an actor for thread-safe call recording.
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async

    /// Returns identifiers only, not the full `[UNNotificationRequest]`
    /// array (which isn't `Sendable`). The scheduler only needs the
    /// identifiers for its sweep.
    func pendingNotificationIdentifiers() async -> [String]

    /// Equivalent to `UNUserNotificationCenter.requestAuthorization(options:)`.
    /// The hardcoded `[.alert, .sound, .badge]` option set is
    /// captured by the live wrapper.
    func requestAuthorization() async throws -> Bool
}

/// Production wrapper around `UNUserNotificationCenter`.
public struct LiveNotificationCenter: NotificationCenterServicing {
    /// `nonisolated(unsafe)` mirrors the same trade-off
    /// `NotificationScheduler.center` had pre-#113:
    /// `UNUserNotificationCenter` is documented as thread-safe but
    /// isn't `Sendable`-annotated.
    nonisolated(unsafe) private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    public func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    public func removePendingNotificationRequests(
        withIdentifiers identifiers: [String]
    ) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func pendingNotificationIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    public func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
}
