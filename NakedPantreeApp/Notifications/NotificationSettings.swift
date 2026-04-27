import Foundation
import SwiftUI

/// User-level preferences that drive how expiry notifications fire. The
/// only knob today is the wall-clock time of day — Phase 9.3 lets users
/// pick when reminders land instead of the previously hardcoded 9:00 AM
/// (`NotificationScheduler.expiryNotificationTriggerDate` default).
///
/// **Storage:** UserDefaults, single household-wide preference. v1
/// intentionally per-device — cross-device sync of the preference (via
/// `NSUbiquitousKeyValueStore` or CloudKit) is deferred per the issue
/// scope. The default values match the previous hardcoded behavior so
/// existing TestFlight users see zero observable change until the
/// integration commit wires this into the scheduler.
///
/// **Architectural placement:** app layer, alongside `NotificationScheduler`
/// and `NotificationRoutingService`. Same trade-off as
/// `RemoteChangeMonitor` / `AccountStatusMonitor`: lift behind a Domain
/// protocol when a non-iOS surface needs the same signal. UserDefaults
/// is iOS-friendly but the abstraction would be cheap if the future
/// macOS CLI grows a notion of "schedule a reminder."
///
/// **`@Observable` shape:** matches `RemoteChangeMonitor` /
/// `AccountStatusMonitor` so the SwiftUI environment hookup is the same
/// pattern. The `nonisolated init()` form requires mutable defaults to
/// live inline on the property declaration — same trick
/// `AccountStatusMonitor.status` uses — because the `@Observable` macro
/// makes stored properties `@MainActor`-isolated and a `nonisolated`
/// initializer body can't write to them.
@Observable
@MainActor
final class NotificationSettings {
    /// Wall-clock hour (0–23) when expiry reminders fire. Defaults to 9
    /// to match the previous hardcoded value at
    /// `NotificationScheduler.expiryNotificationTriggerDate(hourOfDay:)`.
    var hourOfDay: Int = 9 {
        didSet {
            defaults?.set(hourOfDay, forKey: Self.hourKey)
        }
    }

    /// Wall-clock minute (0–59) when expiry reminders fire. Defaults to
    /// 0 — same as the previous hardcoded `minute: 0` baked into the
    /// scheduler.
    var minute: Int = 0 {
        didSet {
            defaults?.set(minute, forKey: Self.minuteKey)
        }
    }

    /// `nil` for the preview/test no-op initializer; the real
    /// `UserDefaults` for the production initializer. The `nil` case
    /// keeps `didSet` from writing to `.standard` from a preview /
    /// snapshot context, where we want a fresh default each time.
    nonisolated(unsafe) private let defaults: UserDefaults?

    /// `nonisolated` so the static constants are reachable from
    /// non-isolated test contexts and the inline property defaults
    /// above. Without this, Swift 6 strict concurrency treats statics
    /// on a `@MainActor` type as MainActor-isolated.
    nonisolated static let hourKey = "settings.notifications.reminderHour"
    nonisolated static let minuteKey = "settings.notifications.reminderMinute"

    /// Hardcoded default that mirrors the value the scheduler was using
    /// before this preference existed. Migration is implicitly a no-op:
    /// users who never opened the new Settings screen keep their 9:00 AM
    /// reminder.
    nonisolated static let defaultHourOfDay = 9
    nonisolated static let defaultMinute = 0

    /// No-op settings store for previews and snapshot tests. Holds the
    /// values in memory only (the `nil` `defaults` short-circuits the
    /// write-throughs above) so #Preview blocks render with the
    /// hardcoded defaults and don't leak between runs.
    ///
    /// `nonisolated` so the `@Entry` environment default — built in a
    /// non-isolated context — can construct one. Mirrors
    /// `RemoteChangeMonitor.init()` and `AccountStatusMonitor.init()`.
    /// The body intentionally only sets the `nonisolated(unsafe)`
    /// `defaults` field; mutable property defaults are inline above so
    /// a nonisolated body never touches MainActor-isolated storage.
    nonisolated init() {
        self.defaults = nil
    }

    /// Production initializer. Reads the persisted values on launch,
    /// falling back to the hardcoded defaults when nothing is stored.
    /// Tests inject a `UserDefaults(suiteName:)` to round-trip values
    /// without touching the standard store.
    ///
    /// The two property writes below trip `didSet` and write back what
    /// we just read — idempotent, two `UserDefaults.set` calls per
    /// launch. Cheap; not worth a guard flag.
    init(defaults: UserDefaults) {
        self.defaults = defaults
        // `object(forKey:)` returns nil when nothing's stored, which
        // distinguishes "user has never opened settings" from "user
        // explicitly chose 0" — `integer(forKey:)` would conflate them.
        if defaults.object(forKey: Self.hourKey) != nil {
            self.hourOfDay = defaults.integer(forKey: Self.hourKey)
        }
        if defaults.object(forKey: Self.minuteKey) != nil {
            self.minute = defaults.integer(forKey: Self.minuteKey)
        }
    }
}

extension EnvironmentValues {
    @Entry var notificationSettings = NotificationSettings()
}
