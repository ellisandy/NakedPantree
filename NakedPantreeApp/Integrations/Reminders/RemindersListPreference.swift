import Foundation
import SwiftUI

/// Issue #155 — user-level preference for which Reminders list the
/// "Push to Reminders" action writes into. Persists the chosen
/// `EKCalendar.calendarIdentifier` in UserDefaults so subsequent
/// pushes target the same list without re-prompting.
///
/// **Why not `@AppStorage`:** the codebase has zero `@AppStorage`
/// callers — we use `@Observable` classes with `didSet`-based
/// UserDefaults write-through (see `NotificationSettings`). Keeping
/// the same shape lets the SwiftUI environment hookup and tests
/// stay symmetrical with the existing notification preference.
///
/// **Lifetime:** one instance per launch, owned by `LiveDependencies`,
/// injected via `\.remindersListPreference`. Settings + Needs
/// Restocking views read and write the same instance, so a re-pick
/// on the Settings screen is visible to the next push immediately.
///
/// **Cross-device sync:** intentionally per-device, same trade-off as
/// `NotificationSettings`. Two partners on a shared household can each
/// push to their own Reminders list. Lifting to
/// `NSUbiquitousKeyValueStore` is a Phase-future polish if anyone
/// asks.
@Observable
@MainActor
final class RemindersListPreference {
    /// `EKCalendar.calendarIdentifier` of the user's chosen Reminders
    /// list, or `nil` if they haven't picked one yet (or cleared it
    /// from Settings). The first-push flow checks for `nil`, prompts
    /// the picker, and writes back; subsequent pushes use the stored
    /// id verbatim.
    var listID: String? {
        didSet {
            if let listID {
                defaults?.set(listID, forKey: Self.listIDKey)
            } else {
                defaults?.removeObject(forKey: Self.listIDKey)
            }
        }
    }

    /// `nil` for the preview/test no-op initializer; the real
    /// `UserDefaults` for the production initializer. Same pattern
    /// as `NotificationSettings.defaults`.
    nonisolated(unsafe) private let defaults: UserDefaults?

    /// `nonisolated` so the static constants are reachable from
    /// non-isolated test contexts and the inline property defaults
    /// above. Without this, Swift 6 strict concurrency treats statics
    /// on a `@MainActor` type as MainActor-isolated.
    nonisolated static let listIDKey = "settings.remindersListID"

    /// No-op preference store for previews and snapshot tests. The
    /// `nil` `defaults` short-circuits the write-throughs above so
    /// `#Preview` blocks render with a fresh empty state every time
    /// and don't leak between runs.
    ///
    /// `nonisolated` so the `@Entry` environment default — built in a
    /// non-isolated context — can construct one. Mirrors
    /// `NotificationSettings.init()`.
    nonisolated init() {
        self.defaults = nil
    }

    /// Production initializer. Reads any persisted list id on launch.
    /// Tests inject a `UserDefaults(suiteName:)` to round-trip values
    /// without touching the standard store.
    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.listID = defaults.string(forKey: Self.listIDKey)
    }
}

extension EnvironmentValues {
    @Entry var remindersListPreference = RemindersListPreference()
}
