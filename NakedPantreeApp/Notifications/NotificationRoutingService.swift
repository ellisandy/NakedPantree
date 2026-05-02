import Foundation
import NakedPantreeDomain
import SwiftUI

/// Extracts the `Item.ID` from a notification's `userInfo` payload.
///
/// Pulled out as a free function so the
/// `UNUserNotificationCenterDelegate` callback stays synchronous (and
/// fast — the system gives us until the completion handler fires) and
/// unit tests can pin a payload without standing up a delegate.
///
/// The payload contract is `["itemID": "<uuid-string>"]`, set in
/// `NotificationScheduler.scheduleIfNeeded`. Returns `nil` for missing
/// keys, non-string values, or malformed UUIDs — the caller silently
/// skips routing in those cases.
func notificationItemID(from userInfo: [AnyHashable: Any]) -> Item.ID? {
    guard let raw = userInfo["itemID"] as? String else { return nil }
    return UUID(uuidString: raw)
}

/// Bridges notification taps and URL deep-links from the system layer
/// to the `RootView` navigation state.
///
/// Tap handling can't live directly in the view layer:
/// `UNUserNotificationCenter.delegate` must be assigned **before**
/// `application(_:didFinishLaunchingWithOptions:)` returns, otherwise
/// cold-launch responses are silently dropped. The delegate publishes
/// the parsed `itemID` to this service; `RootView` observes via
/// `.onChange` (warm-tap path) and reads `pendingItemID` once after
/// bootstrap completes (cold-launch path) before clearing it back to
/// nil.
///
/// **Dual-purpose (#155 follow-up).** The same channel also carries
/// item ids parsed from `nakedpantree://item/<UUID>` deep-links — a
/// tap on a pushed reminder's URL chip in Apple's Reminders.app
/// drops the URL into `RootView.onOpenURL`, which forwards the
/// resolved `Item.ID` here. Sharing the channel keeps the
/// bootstrap-aware cold/warm-tap dance to a single code path; the
/// publisher source doesn't matter once the id has been parsed. If
/// future surfaces need to distinguish the source (e.g. for
/// analytics) they can layer on top, not here.
///
/// Same architectural placement as `RemoteChangeMonitor` /
/// `NotificationScheduler`: app layer, not behind a Domain protocol.
/// `UNUserNotificationCenter` is iOS-specific.
@Observable
@MainActor
final class NotificationRoutingService {
    /// Set by the notification delegate (banner tap) or by
    /// `RootView.onOpenURL` (deep-link tap from Reminders.app, etc.).
    /// `RootView` resolves the item, navigates, then clears this back
    /// to nil. Cleared value avoids re-routing on subsequent unrelated
    /// changeToken bumps.
    var pendingItemID: Item.ID?

    /// `nonisolated` so the `@Entry` environment default value
    /// (constructed in a non-isolated context) can call it.
    nonisolated init() {}
}

extension EnvironmentValues {
    @Entry var notificationRouting = NotificationRoutingService()
}
