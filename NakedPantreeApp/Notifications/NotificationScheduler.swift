import Foundation
import NakedPantreeDomain
import SwiftUI
import UserNotifications

/// Builds the user-facing notification body for a given expiry, with
/// the relative phrase pinned to a reference date.
///
/// `reference` should be the trigger date (when the notification will
/// fire), not the save time — `UNMutableNotificationContent.body` is
/// frozen at scheduling time, so a body computed against `.now` would
/// drift from reality between save and fire. With the default 3-day
/// lead, this consistently reads "Expires in 3 days." regardless of
/// when the user saved the item.
///
/// Pure function (not a method on `NotificationScheduler`) so unit
/// tests can pin the reference date and verify the exact string.
func expiryNotificationBodyCopy(expiresAt: Date, relativeTo reference: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    formatter.dateTimeStyle = .named
    let relative = formatter.localizedString(for: expiresAt, relativeTo: reference)
    return "Expires \(relative)."
}

/// Computes the local trigger date for an expiry notification.
///
/// Pulled out as a free function so unit tests can pin `calendar` /
/// `now` without standing up a `UNUserNotificationCenter`. Returns `nil`
/// when the resulting target is in the past — `UNCalendarNotificationTrigger`
/// silently drops past dates and produces console noise, so the
/// scheduler skips registration in that case (lead-time window already
/// closed; the UI still shows the expiry itself).
///
/// Lead time matches `ARCHITECTURE.md` §8: 3 days before `expiresAt`,
/// fired at 9:00 in the user's local calendar. DST boundaries are
/// handled by `Calendar.date(bySettingHour:minute:second:of:)`, which
/// resolves to the wall-clock hour rather than a fixed UTC offset.
func expiryNotificationTriggerDate(
    expiresAt: Date,
    leadDays: Int = 3,
    hourOfDay: Int = 9,
    calendar: Calendar = .current,
    now: Date = .now
) -> Date? {
    guard let leadDay = calendar.date(byAdding: .day, value: -leadDays, to: expiresAt) else {
        return nil
    }
    guard
        let target = calendar.date(
            bySettingHour: hourOfDay,
            minute: 0,
            second: 0,
            of: leadDay
        )
    else {
        return nil
    }
    return target > now ? target : nil
}

/// Schedules and cancels local expiry notifications for items.
///
/// Phase 4.1: callers (`ItemFormView.save()`, `ItemsView.delete()`)
/// invoke the scheduler directly after a write succeeds. Phase 4.2
/// will add `NSManagedObjectContextDidSave` / `NSPersistentStoreRemoteChange`
/// observation so a remote-side edit reschedules without a local UI
/// round-trip.
///
/// **Identifier scheme:** `"item.\(item.id.uuidString).expiry"` — adding
/// the same identifier replaces any pending request, so re-saving an
/// item with a changed expiry implicitly reschedules. Clearing the
/// expiry removes the request.
///
/// **Permission flow:** lazy. We never prompt at launch. The first
/// time a user saves an item with `expiresAt`, we hit
/// `getNotificationSettings()`. `.notDetermined` → request. `.denied`
/// → silent skip. `.authorized` / `.provisional` → schedule.
///
/// Same architectural placement as `RemoteChangeMonitor` /
/// `AccountStatusMonitor`: app layer, not behind a Domain protocol.
/// `UNUserNotificationCenter` is iOS-specific and the future macOS CLI
/// has no notion of "schedule a banner." Lift behind a protocol if
/// AppIntents or watchOS need it.
@MainActor
final class NotificationScheduler {
    /// `nonisolated(unsafe)` so the no-op `nonisolated init()` below
    /// can write the `nil` initial value at construction. The class
    /// stays `@MainActor` for ergonomic consistency with
    /// `RemoteChangeMonitor` / `AccountStatusMonitor`;
    /// `UNUserNotificationCenter` is documented as thread-safe so
    /// the unsafe qualifier is sound — only the storage write needs
    /// the relaxation, not the underlying API.
    nonisolated(unsafe) private let center: UNUserNotificationCenter?

    /// No-op scheduler for previews and tests. `nonisolated` so the
    /// `@Entry` default value (built in a non-isolated context) can
    /// call it. The trick is similar in spirit to
    /// `RemoteChangeMonitor.init()`, but the mechanism differs —
    /// here the `let center` needs `nonisolated(unsafe)` to be
    /// settable from a non-isolated init.
    nonisolated init() {
        self.center = nil
    }

    init(center: UNUserNotificationCenter) {
        self.center = center
    }

    /// Idempotent. Re-running with the same item replaces any pending
    /// request (deterministic identifier). Clearing `expiresAt`
    /// cancels. A past trigger date silently skips.
    func scheduleIfNeeded(for item: Item) async {
        guard let center else { return }
        let id = Self.identifier(for: item.id)

        guard let expiresAt = item.expiresAt else {
            center.removePendingNotificationRequests(withIdentifiers: [id])
            return
        }

        guard let triggerDate = expiryNotificationTriggerDate(expiresAt: expiresAt) else {
            // Lead-time window has passed. Drop any older request that
            // might still be pending from a previous expiry value.
            center.removePendingNotificationRequests(withIdentifiers: [id])
            return
        }

        guard await ensureAuthorization(center: center) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = item.name
        content.body = expiryNotificationBodyCopy(expiresAt: expiresAt, relativeTo: triggerDate)
        // userInfo is wired in 4.1 even though tap-routing lands in
        // 4.2 — keeping requests carrying the id means the routing PR
        // is purely additive (a delegate method) and doesn't need to
        // backfill identifiers onto already-scheduled requests.
        content.userInfo = ["itemID": item.id.uuidString]
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            // No remediation path — `.add` rejects only on system
            // throttling or denied authorization that flipped between
            // our check and the call. Silent skip; user has expiry in
            // the UI either way.
        }
    }

    /// Removes the pending request for an item. Used by the delete
    /// path, which only has the id once the row is gone.
    func cancel(itemID: Item.ID) {
        guard let center else { return }
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier(for: itemID)])
    }

    private func ensureAuthorization(center: UNUserNotificationCenter) async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    /// `nonisolated` — pure function over the id, no instance state.
    /// Tests call it from a sync `Testing` context.
    nonisolated static func identifier(for itemID: Item.ID) -> String {
        "item.\(itemID.uuidString).expiry"
    }

}

extension EnvironmentValues {
    @Entry var notificationScheduler = NotificationScheduler()
}
