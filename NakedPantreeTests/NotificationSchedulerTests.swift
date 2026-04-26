import Foundation
import Testing
@testable import NakedPantree

@Suite("Expiry notification trigger date")
struct ExpiryTriggerDateTests {
    /// Pinned to a fixed timezone + Gregorian calendar so the expected
    /// instants match across CI runners and developer machines —
    /// `Calendar.current` would otherwise drift with the host locale.
    private static func laCalendar() throws -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        cal.timeZone = zone
        return cal
    }

    private static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 12,
        _ minute: Int = 0,
        in calendar: Calendar
    ) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return try #require(calendar.date(from: components))
    }

    @Test("3 days before expiry, fires at 9am local")
    func threeDaysBeforeAtNineAM() throws {
        let calendar = try Self.laCalendar()
        // Item expires Friday March 20, 2026 — 9am local.
        let expiresAt = try Self.date(2026, 3, 20, 9, 0, in: calendar)
        let now = try Self.date(2026, 3, 15, 12, 0, in: calendar)

        let trigger = expiryNotificationTriggerDate(
            expiresAt: expiresAt,
            calendar: calendar,
            now: now
        )

        // 3 days before March 20 is March 17, 9am local.
        let expected = try Self.date(2026, 3, 17, 9, 0, in: calendar)
        #expect(trigger == expected)
    }

    @Test("Trigger fires at 9am local even when expiry is at midnight")
    func nineAMRegardlessOfExpiryTimeOfDay() throws {
        let calendar = try Self.laCalendar()
        let expiresAt = try Self.date(2026, 3, 20, 0, 0, in: calendar)
        let now = try Self.date(2026, 3, 15, 12, 0, in: calendar)

        let trigger = expiryNotificationTriggerDate(
            expiresAt: expiresAt,
            calendar: calendar,
            now: now
        )

        let expected = try Self.date(2026, 3, 17, 9, 0, in: calendar)
        #expect(trigger == expected)
    }

    @Test("Past trigger date returns nil")
    func pastTriggerSilentlySkips() throws {
        let calendar = try Self.laCalendar()
        // Item expires tomorrow — 3 days before is in the past.
        let now = try Self.date(2026, 3, 15, 12, 0, in: calendar)
        let expiresAt = try Self.date(2026, 3, 16, 9, 0, in: calendar)

        let trigger = expiryNotificationTriggerDate(
            expiresAt: expiresAt,
            calendar: calendar,
            now: now
        )

        #expect(trigger == nil)
    }

    @Test("Trigger date crosses spring-forward DST boundary cleanly")
    func dstSpringForwardLandsAtNineAMWallClock() throws {
        // US spring-forward 2026: clocks jump from 02:00 → 03:00 on
        // Sunday March 8. An expiry on Wed March 11 with 3-day lead
        // crosses the boundary — the trigger should still resolve to
        // 9am wall-clock time on Sunday, not 8am.
        let calendar = try Self.laCalendar()
        let expiresAt = try Self.date(2026, 3, 11, 12, 0, in: calendar)
        let now = try Self.date(2026, 3, 5, 12, 0, in: calendar)

        let trigger = expiryNotificationTriggerDate(
            expiresAt: expiresAt,
            calendar: calendar,
            now: now
        )

        let expected = try Self.date(2026, 3, 8, 9, 0, in: calendar)
        let resolved = try #require(trigger)
        let components = calendar.dateComponents([.hour, .minute], from: resolved)
        #expect(components.hour == 9)
        #expect(components.minute == 0)
        #expect(trigger == expected)
    }

    @Test("Custom lead days override default")
    func customLeadDays() throws {
        let calendar = try Self.laCalendar()
        let expiresAt = try Self.date(2026, 3, 20, 9, 0, in: calendar)
        let now = try Self.date(2026, 3, 1, 12, 0, in: calendar)

        let trigger = expiryNotificationTriggerDate(
            expiresAt: expiresAt,
            leadDays: 7,
            calendar: calendar,
            now: now
        )

        let expected = try Self.date(2026, 3, 13, 9, 0, in: calendar)
        #expect(trigger == expected)
    }
}

@Suite("Notification body copy")
struct NotificationBodyCopyTests {
    @Test("Body relative phrase is anchored to fire time, not save time")
    func bodyAnchoredToTriggerDate() throws {
        // User saves item April 1; expires April 30; default 3-day
        // lead means trigger fires April 27 9am. The body — frozen at
        // scheduling time — must read "in 3 days" relative to *fire
        // time*, not "in 4 weeks" relative to save time. This is the
        // bug-of-record that drove the API shape: `relativeTo` is the
        // trigger date.
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 30
        components.hour = 9
        let calendar = Calendar(identifier: .gregorian)
        let expiresAt = try #require(calendar.date(from: components))

        components.day = 27
        let triggerDate = try #require(calendar.date(from: components))

        let body = expiryNotificationBodyCopy(expiresAt: expiresAt, relativeTo: triggerDate)
        // Lock the prefix; the relative phrase itself is locale-formatted
        // by `RelativeDateTimeFormatter`. The only invariants we care
        // about: it starts with "Expires", ends with a period, and the
        // relative phrase mentions "3 days" — not "4 weeks".
        #expect(body.hasPrefix("Expires "))
        #expect(body.hasSuffix("."))
        #expect(body.contains("3 days"))
        #expect(!body.contains("week"))
    }
}

@Suite("Notification identifier scheme")
struct NotificationIdentifierTests {
    @Test("Identifier is deterministic across calls")
    func identifierIsDeterministic() {
        let id = UUID()
        let first = NotificationScheduler.identifier(for: id)
        let second = NotificationScheduler.identifier(for: id)
        #expect(first == second)
    }

    @Test("Identifier matches architecture spec")
    func identifierFormat() throws {
        let id = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let expected = "item.11111111-2222-3333-4444-555555555555.expiry"
        #expect(NotificationScheduler.identifier(for: id) == expected)
    }
}
