import Foundation
import Testing
@testable import NakedPantree

/// Persistence + default-value tests for `NotificationSettings`.
///
/// Each test stands up a fresh `UserDefaults(suiteName:)` and clears
/// it on construction so values don't leak between cases. The suite
/// name is randomized per test to keep parallel test runs isolated;
/// `removePersistentDomain` ensures no stale state survives.
@Suite("NotificationSettings")
@MainActor
struct NotificationSettingsTests {
    private static func freshDefaults() throws -> UserDefaults {
        let suite = "NotificationSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Defaults to 9:00 AM when nothing is stored")
    func defaultsTo9AMWhenEmpty() throws {
        let defaults = try Self.freshDefaults()
        let settings = NotificationSettings(defaults: defaults)

        #expect(settings.hourOfDay == 9)
        #expect(settings.minute == 0)
    }

    @Test("Default constants match the previous hardcoded scheduler value")
    func defaultConstantsMatchHardcoded() {
        // Pin the migration contract: existing TestFlight users must
        // see exactly the same time-of-day until they explicitly change
        // it. If a future commit drifts the default, this fails loudly.
        #expect(NotificationSettings.defaultHourOfDay == 9)
        #expect(NotificationSettings.defaultMinute == 0)
    }

    @Test("Round-trips a stored hour through a new instance")
    func roundTripsHour() throws {
        let defaults = try Self.freshDefaults()
        let writer = NotificationSettings(defaults: defaults)
        writer.hourOfDay = 18
        writer.minute = 30

        // A fresh instance over the same defaults sees the persisted
        // values — proves the `didSet` write-through reaches storage
        // and the production initializer reads it back.
        let reader = NotificationSettings(defaults: defaults)
        #expect(reader.hourOfDay == 18)
        #expect(reader.minute == 30)
    }

    @Test("Explicit zero hour is distinguished from missing key")
    func zeroHourPersists() throws {
        // `integer(forKey:)` returns 0 for both "user picked midnight"
        // and "nothing stored." The implementation guards with
        // `object(forKey:)` to keep them distinct — pin that here so
        // a future "simplification" doesn't conflate the cases.
        let defaults = try Self.freshDefaults()
        let writer = NotificationSettings(defaults: defaults)
        writer.hourOfDay = 0
        writer.minute = 0

        let reader = NotificationSettings(defaults: defaults)
        #expect(reader.hourOfDay == 0)
        #expect(reader.minute == 0)
    }

    @Test("No-op initializer holds defaults in memory only")
    func noOpInitDoesNotPersist() throws {
        // The `nonisolated init()` is what the `@Entry` environment
        // default uses for previews / tests. It must not leak into
        // `.standard` UserDefaults — we just verify it constructs with
        // the documented defaults.
        let settings = NotificationSettings()
        #expect(settings.hourOfDay == 9)
        #expect(settings.minute == 0)

        // Mutating the no-op instance shouldn't crash even though
        // there's no backing defaults.
        settings.hourOfDay = 20
        #expect(settings.hourOfDay == 20)
    }

    @Test("Storage keys are stable")
    func storageKeysStable() {
        // The keys are part of the on-disk contract for any user who
        // already saved a preference. Re-naming them is a migration,
        // not a refactor — pin the strings.
        #expect(NotificationSettings.hourKey == "settings.notifications.reminderHour")
        #expect(NotificationSettings.minuteKey == "settings.notifications.reminderMinute")
    }
}
