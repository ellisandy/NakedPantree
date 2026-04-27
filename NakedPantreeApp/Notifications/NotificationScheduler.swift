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
/// fired at the user's chosen reminder time (Phase 9.3 — wall-clock
/// hour and minute) in the local calendar. DST boundaries are handled
/// by `Calendar.date(bySettingHour:minute:second:of:)`, which resolves
/// to the wall-clock hour rather than a fixed UTC offset.
///
/// Phase 9.3 added the `minute` parameter so users can pick non-on-the-
/// hour reminder times like 7:30 PM. Pre-existing callers default to
/// `minute: 0`, matching the previous hardcoded behavior.
func expiryNotificationTriggerDate(
    expiresAt: Date,
    leadDays: Int = 3,
    hourOfDay: Int = 9,
    minute: Int = 0,
    calendar: Calendar = .current,
    now: Date = .now
) -> Date? {
    guard let leadDay = calendar.date(byAdding: .day, value: -leadDays, to: expiresAt) else {
        return nil
    }
    guard
        let target = calendar.date(
            bySettingHour: hourOfDay,
            minute: minute,
            second: 0,
            of: leadDay
        )
    else {
        return nil
    }
    return target > now ? target : nil
}

/// Recognizes a notification identifier as one this scheduler owns —
/// either the per-item shape (`item.<uuid>.expiry`) or the Phase 9.4
/// rollup shape (`day.<yyyyMMdd>.expiry`). The bundle-aware resync
/// sweep uses this to filter out third-party identifiers (future
/// low-stock alerts, share-related notifications) before computing
/// "stale relative to the expected set."
///
/// Pure free function so it stays unit-testable without standing up
/// `UNUserNotificationCenter`.
func isExpiryNotificationIdentifier(_ identifier: String) -> Bool {
    let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[2] == "expiry" else { return false }
    if parts[0] == "item" {
        return UUID(uuidString: String(parts[1])) != nil
    }
    if parts[0] == "day" {
        return parts[1].count == 8 && parts[1].allSatisfy(\.isNumber)
    }
    return false
}

/// Bundle-aware stale-identifier sweep used by `resync(currentItems:)`
/// after Phase 9.4. Returns pending identifiers that look like ours
/// (per `isExpiryNotificationIdentifier`) but aren't in the expected
/// set produced by `bundleSameDayExpiries`. Identifiers we don't
/// recognize pass through untouched, same as the per-item-only
/// `staleExpiryIdentifiers` did.
func staleBundleIdentifiers(
    pending: [String],
    expected: Set<String>
) -> [String] {
    pending.filter { identifier in
        isExpiryNotificationIdentifier(identifier) && !expected.contains(identifier)
    }
}

/// Parses the item UUID out of a notification identifier produced by
/// `NotificationScheduler.identifier(for:)`. Returns `nil` for any
/// identifier that doesn't match the `"item.<uuid>.expiry"` shape —
/// keeps the resync sweep tolerant of stray identifiers a future
/// scheduler variant might add (e.g. low-stock alerts in Phase 6).
///
/// Pure function so tests can pin both the parse and the diff logic
/// without touching `UNUserNotificationCenter`.
func parseExpiryNotificationItemID(fromIdentifier identifier: String) -> UUID? {
    let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0] == "item", parts[2] == "expiry" else {
        return nil
    }
    return UUID(uuidString: String(parts[1]))
}

/// Returns the set of pending notification identifiers that should be
/// cancelled because the underlying item no longer appears in the
/// current item set. Identifiers we don't recognize as item-expiry
/// notifications (e.g. future low-stock alerts) are passed through
/// untouched — the resync sweep stays narrowly scoped to its own kind.
///
/// Pure free function over two id sets so the diff logic is unit-testable
/// without standing up a `UNUserNotificationCenter`.
func staleExpiryIdentifiers(
    pending: [String],
    currentItemIDs: Set<UUID>
) -> [String] {
    pending.filter { identifier in
        guard let itemID = parseExpiryNotificationItemID(fromIdentifier: identifier) else {
            return false
        }
        return !currentItemIDs.contains(itemID)
    }
}

/// Schedules and cancels local expiry notifications for items.
///
/// Phase 4.1: callers (`ItemFormView.save()`, `ItemsView.delete()`)
/// invoke the scheduler directly after a write succeeds — the
/// low-latency local fast path. Phase 4.3 adds `resync(currentItems:)`,
/// driven by the `NSPersistentStoreRemoteChange` observer
/// (`RemoteChangeMonitor.changeToken`) wired in `RootView`. The two
/// paths are intentionally redundant: form callbacks fire immediately
/// without the observer's debounce; the observer is the correctness
/// backstop for remote changes and cold-launch backfill. Both ride
/// the same idempotent `scheduleIfNeeded`, so the overlap costs only
/// a few CPU cycles. Issue #28 (history-token bookkeeping) would let
/// the observer skip locally-authored transactions and remove the
/// redundancy without changing observable behavior — complementary,
/// not blocking.
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

    /// Phase 9.3: optional reference to the user's notification
    /// preferences. Drives the wall-clock reminder time. `nil` for
    /// previews / tests / EMPTY_STORE / unit-test host paths, where
    /// the default 9:00 AM (matching the pre-9.3 hardcoded value)
    /// preserves existing behavior.
    private let settings: NotificationSettings?

    /// No-op scheduler for previews and tests. `nonisolated` so the
    /// `@Entry` default value (built in a non-isolated context) can
    /// call it. The trick is similar in spirit to
    /// `RemoteChangeMonitor.init()`, but the mechanism differs —
    /// here the `let center` needs `nonisolated(unsafe)` to be
    /// settable from a non-isolated init.
    nonisolated init() {
        self.center = nil
        self.settings = nil
    }

    /// Production initializer. `settings` is optional so callers that
    /// want the previous hardcoded 9:00 AM behavior (e.g. tests that
    /// don't care about the picker) can still construct without one.
    /// `NakedPantreeApp` always passes a real one in production.
    init(center: UNUserNotificationCenter, settings: NotificationSettings? = nil) {
        self.center = center
        self.settings = settings
    }

    /// Reads the current reminder hour from settings, falling back to
    /// the pre-9.3 hardcoded value when no settings store is wired.
    /// `@MainActor`-isolated like the class itself, since
    /// `NotificationSettings` is `@Observable @MainActor`.
    private var reminderHour: Int {
        settings?.hourOfDay ?? NotificationSettings.defaultHourOfDay
    }

    /// Reads the current reminder minute. Same fallback shape as
    /// `reminderHour`.
    private var reminderMinute: Int {
        settings?.minute ?? NotificationSettings.defaultMinute
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

        guard
            let triggerDate = expiryNotificationTriggerDate(
                expiresAt: expiresAt,
                hourOfDay: reminderHour,
                minute: reminderMinute
            )
        else {
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

    /// Brings pending expiry notifications into agreement with the
    /// current set of items.
    ///
    /// Phase 9.4: items are bundled by local-calendar day before
    /// scheduling. A day with N items produces one rollup notification
    /// (`day.<yyyyMMdd>.expiry`) instead of N per-item banners; a day
    /// with one item still produces a single-item notification using
    /// the same `item.<uuid>.expiry` identifier `scheduleIfNeeded`
    /// produces, so a day collapsing N → 1 hands off cleanly without
    /// a special case. The form-save fast-path (`scheduleIfNeeded`
    /// direct) still emits per-item; the next remote-change tick's
    /// resync converges to the bundled shape, cancelling the now-
    /// stale per-item request via the `staleBundleIdentifiers` sweep.
    ///
    /// Called from `RootView` on every `RemoteChangeMonitor.changeToken`
    /// tick. The first tick fires at cold launch — that's intentional:
    /// it backfills "user reinstalled," "user re-granted notification
    /// permission," and "remote changes happened while backgrounded
    /// for weeks." The cost is O(bundles) + O(pending) per pass.
    ///
    /// **Permission gate.** A blanket `.notDetermined` bail at the top
    /// keeps this background sweep from triggering the permission
    /// prompt — a cold launch with seeded items would otherwise hit
    /// `requestAuthorization` and break Phase 4.1's "lazy. We never
    /// prompt at launch" contract. The form-save path keeps its
    /// prompt because that's the contextual moment.
    func resync(currentItems: [Item]) async {
        guard let center else { return }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .notDetermined, .denied:
            // Sweep is a background reconciliation, not a contextual
            // moment. Bail rather than prompt.
            return
        @unknown default:
            return
        }

        let bundles = bundleSameDayExpiries(
            currentItems,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute
        )
        for bundle in bundles {
            await scheduleBundle(bundle, on: center)
        }

        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let expected = Set(bundles.map(\.identifier))
        let stale = staleBundleIdentifiers(pending: pending, expected: expected)
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
    }

    /// Converts a bundle into a `UNNotificationRequest` and registers
    /// it. Bundles whose computed lead trigger has already passed
    /// (`firesImmediately`) use a short `UNTimeIntervalNotificationTrigger`;
    /// future bundles use `UNCalendarNotificationTrigger` so the system
    /// fires at the wall-clock minute the user chose, even if the
    /// device is off then.
    ///
    /// `userInfo` carries the first item's id so the existing tap-routing
    /// (`NotificationRoutingService`) keeps working — multi-item bundles
    /// land on the first item's detail; single-item bundles land on
    /// that item, same as before.
    private func scheduleBundle(
        _ bundle: ExpiryNotificationBundle,
        on center: UNUserNotificationCenter
    ) async {
        guard await ensureAuthorization(center: center) else { return }

        let content = UNMutableNotificationContent()
        content.title = bundle.title
        content.body = bundle.body
        content.sound = .default
        if let leadID = bundle.itemIDs.first {
            content.userInfo = ["itemID": leadID.uuidString]
        }

        let trigger: UNNotificationTrigger
        if bundle.firesImmediately {
            // `UNTimeIntervalNotificationTrigger` requires ≥1s; the
            // bundling function already pads to `now + 60s` so this
            // is comfortable.
            let interval = max(1.0, bundle.triggerDate.timeIntervalSinceNow)
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        } else {
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: bundle.triggerDate
            )
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }

        let request = UNNotificationRequest(
            identifier: bundle.identifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            // No remediation path — `.add` rejects only on system
            // throttling or denied authorization that flipped between
            // our check and the call. Silent skip; user has expiry in
            // the UI either way.
        }
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
