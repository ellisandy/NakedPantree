import Foundation
import NakedPantreeDomain
import Testing
@testable import NakedPantree

/// Shared helpers for the bundling test suites. Pulled into a namespace
/// so the @Suite types stay short enough for `type_body_length`.
enum BundleFixtures {
    /// Pinned to a fixed timezone + Gregorian calendar so day-grouping,
    /// trigger dates, and identifier stamps match across CI runners and
    /// developer machines. `Calendar.current` would otherwise drift
    /// with the host locale.
    static func laCalendar() throws -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        cal.timeZone = zone
        return cal
    }

    static func date(
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

    static func makeItem(name: String, expiresAt: Date?) -> Item {
        Item(locationID: UUID(), name: name, expiresAt: expiresAt)
    }
}

@Suite("Bundling: empty / nil-expiry inputs")
struct ExpiryBundleEmptyInputTests {
    @Test("Empty input returns empty output")
    func emptyInputProducesNoBundles() throws {
        let calendar = try BundleFixtures.laCalendar()
        let now = try BundleFixtures.date(2026, 3, 1, 12, 0, in: calendar)
        let bundles = bundleSameDayExpiries([], calendar: calendar, now: now)
        #expect(bundles.isEmpty)
    }

    @Test("Items without an expiry are dropped before bundling")
    func nilExpiryItemsAreDropped() throws {
        let calendar = try BundleFixtures.laCalendar()
        let now = try BundleFixtures.date(2026, 3, 1, 12, 0, in: calendar)
        let nilItem = BundleFixtures.makeItem(name: "Pasta", expiresAt: nil)
        let bundles = bundleSameDayExpiries([nilItem], calendar: calendar, now: now)
        #expect(bundles.isEmpty)
    }

    @Test("All-nil-expiry input returns empty output")
    func allNilExpiryProducesNoBundles() throws {
        let calendar = try BundleFixtures.laCalendar()
        let now = try BundleFixtures.date(2026, 3, 1, 12, 0, in: calendar)
        let items = [
            BundleFixtures.makeItem(name: "A", expiresAt: nil),
            BundleFixtures.makeItem(name: "B", expiresAt: nil),
        ]
        let bundles = bundleSameDayExpiries(items, calendar: calendar, now: now)
        #expect(bundles.isEmpty)
    }
}

@Suite("Bundling: single-item days")
struct ExpiryBundleSingleItemTests {
    @Test("Single item on its own day produces a single-item bundle")
    func singleItemProducesSingleBundle() throws {
        let calendar = try BundleFixtures.laCalendar()
        let now = try BundleFixtures.date(2026, 3, 15, 12, 0, in: calendar)
        let expiresAt = try BundleFixtures.date(2026, 3, 25, 9, 0, in: calendar)
        let item = BundleFixtures.makeItem(name: "Milk", expiresAt: expiresAt)

        let bundles = bundleSameDayExpiries([item], calendar: calendar, now: now)

        #expect(bundles.count == 1)
        let bundle = try #require(bundles.first)
        #expect(bundle.itemIDs == [item.id])
        #expect(bundle.title == "Milk")
        // Body shape matches the existing per-item path.
        #expect(bundle.body.hasPrefix("Expires "))
        #expect(bundle.body.hasSuffix("."))
        #expect(bundle.firesImmediately == false)
    }

    @Test("Single-item identifier matches the existing per-item scheme")
    func singleItemIdentifierMatchesPerItemScheme() throws {
        let calendar = try BundleFixtures.laCalendar()
        let now = try BundleFixtures.date(2026, 3, 15, 12, 0, in: calendar)
        let expiresAt = try BundleFixtures.date(2026, 3, 25, 9, 0, in: calendar)
        let item = BundleFixtures.makeItem(name: "Milk", expiresAt: expiresAt)

        let bundles = bundleSameDayExpiries([item], calendar: calendar, now: now)

        let bundle = try #require(bundles.first)
        // Load-bearing: scheduler reschedule path keys on this exact
        // shape. If a day collapses from N items to 1, the rollup id
        // disappears and the per-item id returns — no special casing.
        #expect(bundle.identifier == "item.\(item.id.uuidString).expiry")
        #expect(bundle.identifier == NotificationScheduler.identifier(for: item.id))
    }

    @Test("Single-item trigger fires at the configured reminder time on lead-day")
    func singleItemTriggerHonoursReminderTime() throws {
        let calendar = try BundleFixtures.laCalendar()
        let now = try BundleFixtures.date(2026, 3, 15, 12, 0, in: calendar)
        let expiresAt = try BundleFixtures.date(2026, 3, 25, 9, 0, in: calendar)
        let item = BundleFixtures.makeItem(name: "Milk", expiresAt: expiresAt)

        let bundles = bundleSameDayExpiries(
            [item],
            reminderHour: 14,
            reminderMinute: 30,
            calendar: calendar,
            now: now
        )

        let bundle = try #require(bundles.first)
        // 3 days before March 25 = March 22; reminder at 14:30 local.
        let expected = try BundleFixtures.date(2026, 3, 22, 14, 30, in: calendar)
        #expect(bundle.triggerDate == expected)
    }
}

@Suite("Bundling: multi-item rollups")
struct ExpiryBundleMultiItemTests {
    @Test("Two items same day → single rollup with N=2 copy")
    func twoItemsSameDayProducesSingularOtherCopy() throws {
        let calendar = try BundleFixtures.laCalendar()
        let now = try BundleFixtures.date(2026, 3, 15, 12, 0, in: calendar)
        let day = try BundleFixtures.date(2026, 3, 25, 9, 0, in: calendar)
        // Names chosen so the alphabetically-first lead is "Cucumber".
        let cucumber = BundleFixtures.makeItem(name: "Cucumber", expiresAt: day)
        let yogurt = BundleFixtures.makeItem(name: "Yogurt", expiresAt: day)

        let bundles = bundleSameDayExpiries([yogurt, cucumber], calendar: calendar, now: now)

        #expect(bundles.count == 1)
        let bundle = try #require(bundles.first)
        #expect(Set(bundle.itemIDs) == Set([cucumber.id, yogurt.id]))
        #expect(bundle.title == "2 items expiring soon")
        // Singular "other" + singular verb "expires".
        #expect(bundle.body.hasPrefix("Cucumber + 1 other expires "))
        #expect(bundle.body.hasSuffix("."))
        #expect(bundle.firesImmediately == false)
    }

    @Test("Three items same day → rollup with plural N≥3 copy")
    func threeItemsSameDayProducesPluralOthersCopy() throws {
        let calendar = try BundleFixtures.laCalendar()
        let now = try BundleFixtures.date(2026, 3, 15, 12, 0, in: calendar)
        let day = try BundleFixtures.date(2026, 3, 25, 9, 0, in: calendar)
        let cucumber = BundleFixtures.makeItem(name: "Cucumber", expiresAt: day)
        let yogurt = BundleFixtures.makeItem(name: "Yogurt", expiresAt: day)
        let milk = BundleFixtures.makeItem(name: "Milk", expiresAt: day)

        let bundles = bundleSameDayExpiries(
            [yogurt, cucumber, milk],
            calendar: calendar,
            now: now
        )

        #expect(bundles.count == 1)
        let bundle = try #require(bundles.first)
        #expect(bundle.itemIDs.count == 3)
        #expect(bundle.title == "3 items expiring soon")
        // Plural "others" + plural verb "expire".
        #expect(bundle.body.hasPrefix("Cucumber + 2 others expire "))
        #expect(bundle.body.hasSuffix("."))
    }

    @Test("Multi-item identifier uses yyyyMMdd of the local day")
    func multiItemIdentifierHasDayStamp() throws {
        let calendar = try BundleFixtures.laCalendar()
        let now = try BundleFixtures.date(2026, 3, 15, 12, 0, in: calendar)
        let day = try BundleFixtures.date(2026, 3, 25, 9, 0, in: calendar)
        let cucumber = BundleFixtures.makeItem(name: "Cucumber", expiresAt: day)
        let yogurt = BundleFixtures.makeItem(name: "Yogurt", expiresAt: day)

        let bundles = bundleSameDayExpiries([yogurt, cucumber], calendar: calendar, now: now)

        let bundle = try #require(bundles.first)
        #expect(bundle.identifier == "day.20260325.expiry")
    }

    @Test("Lead name is alphabetically-first regardless of input order")
    func leadNameIsAlphabeticallyFirst() throws {
        let calendar = try BundleFixtures.laCalendar()
        let now = try BundleFixtures.date(2026, 3, 15, 12, 0, in: calendar)
        let day = try BundleFixtures.date(2026, 3, 25, 9, 0, in: calendar)
        let zucchini = BundleFixtures.makeItem(name: "Zucchini", expiresAt: day)
        let apricot = BundleFixtures.makeItem(name: "Apricot", expiresAt: day)
        let mango = BundleFixtures.makeItem(name: "Mango", expiresAt: day)

        // Try multiple input orderings — lead must always be the
        // alphabetically-first name.
        for permutation in [
            [zucchini, apricot, mango],
            [mango, apricot, zucchini],
            [apricot, mango, zucchini],
            [mango, zucchini, apricot],
        ] {
            let bundles = bundleSameDayExpiries(permutation, calendar: calendar, now: now)
            let bundle = try #require(bundles.first)
            #expect(bundle.body.hasPrefix("Apricot + 2 others expire "))
        }
    }
}

@Suite("Bundling: past-expiry / immediate-trigger paths")
struct ExpiryBundlePastExpiryTests {
    @Test("Already-past single-item expiry uses past-tense copy + immediate trigger")
    func pastExpirySingleItemUsesPastTense() throws {
        let calendar = try BundleFixtures.laCalendar()
        let now = try BundleFixtures.date(2026, 3, 15, 12, 0, in: calendar)
        // Expired three days ago.
        let expiresAt = try BundleFixtures.date(2026, 3, 12, 9, 0, in: calendar)
        let item = BundleFixtures.makeItem(name: "Milk", expiresAt: expiresAt)

        let bundles = bundleSameDayExpiries([item], calendar: calendar, now: now)

        #expect(bundles.count == 1)
        let bundle = try #require(bundles.first)
        #expect(bundle.title == "Milk")
        #expect(bundle.body == "Milk has expired.")
        #expect(bundle.firesImmediately == true)
        // Immediate trigger sits 60 seconds past `now`.
        #expect(bundle.triggerDate == now.addingTimeInterval(60))
    }

    @Test("Already-past multi-item expiry uses past-tense copy + immediate trigger")
    func pastExpiryMultiItemUsesPastTense() throws {
        let calendar = try BundleFixtures.laCalendar()
        let now = try BundleFixtures.date(2026, 3, 15, 12, 0, in: calendar)
        let day = try BundleFixtures.date(2026, 3, 12, 9, 0, in: calendar)
        let cucumber = BundleFixtures.makeItem(name: "Cucumber", expiresAt: day)
        let yogurt = BundleFixtures.makeItem(name: "Yogurt", expiresAt: day)
        let milk = BundleFixtures.makeItem(name: "Milk", expiresAt: day)

        let bundles = bundleSameDayExpiries(
            [yogurt, cucumber, milk],
            calendar: calendar,
            now: now
        )

        let bundle = try #require(bundles.first)
        // Title agrees with past-tense body — "expiring soon" would
        // be a lie when items have already expired.
        #expect(bundle.title == "3 items expired")
        // N=3: plural verb "have".
        #expect(bundle.body == "Cucumber + 2 others have expired.")
        #expect(bundle.firesImmediately == true)
        #expect(bundle.triggerDate == now.addingTimeInterval(60))
    }

    @Test("Two past-expired items use singular has + singular other")
    func pastExpiryTwoItemsUsesSingularHas() throws {
        let calendar = try BundleFixtures.laCalendar()
        let now = try BundleFixtures.date(2026, 3, 15, 12, 0, in: calendar)
        let day = try BundleFixtures.date(2026, 3, 12, 9, 0, in: calendar)
        let cucumber = BundleFixtures.makeItem(name: "Cucumber", expiresAt: day)
        let yogurt = BundleFixtures.makeItem(name: "Yogurt", expiresAt: day)

        let bundles = bundleSameDayExpiries([yogurt, cucumber], calendar: calendar, now: now)

        let bundle = try #require(bundles.first)
        #expect(bundle.title == "2 items expired")
        #expect(bundle.body == "Cucumber + 1 other has expired.")
    }

    @Test("Lead-window-already-closed item bundles with immediate trigger and future copy")
    func leadWindowClosedFiresImmediatelyWithFutureCopy() throws {
        let calendar = try BundleFixtures.laCalendar()
        // Expires tomorrow — 3-day lead is already in the past, but
        // the item itself isn't expired yet. The permissive read:
        // still bundle, fire immediately, future-tense copy.
        let now = try BundleFixtures.date(2026, 3, 15, 12, 0, in: calendar)
        let expiresAt = try BundleFixtures.date(2026, 3, 16, 9, 0, in: calendar)
        let item = BundleFixtures.makeItem(name: "Milk", expiresAt: expiresAt)

        let bundles = bundleSameDayExpiries([item], calendar: calendar, now: now)

        #expect(bundles.count == 1)
        let bundle = try #require(bundles.first)
        #expect(bundle.firesImmediately == true)
        #expect(bundle.triggerDate == now.addingTimeInterval(60))
        // Future-tense — the item hasn't expired yet.
        #expect(bundle.body.hasPrefix("Expires "))
        #expect(bundle.body.hasSuffix("."))
        // Sanity: not the past-tense copy.
        #expect(bundle.body != "Milk has expired.")
    }
}

@Suite("Bundling: mixed days, DST, and timezone independence")
struct ExpiryBundleMixedAndBoundaryTests {
    @Test("Items expiring on different days produce separate bundles, ordered by trigger")
    func mixedDaysProduceMultipleBundlesOrdered() throws {
        let calendar = try BundleFixtures.laCalendar()
        let now = try BundleFixtures.date(2026, 3, 15, 12, 0, in: calendar)
        let day1 = try BundleFixtures.date(2026, 3, 22, 9, 0, in: calendar)
        let day2 = try BundleFixtures.date(2026, 3, 25, 9, 0, in: calendar)
        let day3 = try BundleFixtures.date(2026, 3, 30, 9, 0, in: calendar)
        let alpha = BundleFixtures.makeItem(name: "Alpha", expiresAt: day1)
        let beta1 = BundleFixtures.makeItem(name: "Beta", expiresAt: day2)
        let beta2 = BundleFixtures.makeItem(name: "Bravo", expiresAt: day2)
        let gamma = BundleFixtures.makeItem(name: "Gamma", expiresAt: day3)

        let bundles = bundleSameDayExpiries(
            [gamma, beta2, alpha, beta1],
            calendar: calendar,
            now: now
        )

        #expect(bundles.count == 3)
        // Ordered by trigger date ascending.
        #expect(bundles[0].triggerDate < bundles[1].triggerDate)
        #expect(bundles[1].triggerDate < bundles[2].triggerDate)
        // First bundle is single-item (Alpha alone on day1).
        #expect(bundles[0].itemIDs == [alpha.id])
        // Middle bundle is the rollup.
        #expect(bundles[1].itemIDs.count == 2)
        #expect(bundles[1].title == "2 items expiring soon")
        // Last bundle is single-item (Gamma alone on day3).
        #expect(bundles[2].itemIDs == [gamma.id])
    }

    @Test("DST spring-forward day groups items into the same local day")
    func dstSpringForwardKeepsSameLocalDayGrouping() throws {
        // US spring-forward 2026: clocks jump 02:00 → 03:00 on Sunday
        // March 8. Two items both expire on March 8 (one in the
        // morning, one in the evening) — they must group into one
        // bundle because they share the local calendar day.
        let calendar = try BundleFixtures.laCalendar()
        let now = try BundleFixtures.date(2026, 3, 1, 12, 0, in: calendar)
        let morning = try BundleFixtures.date(2026, 3, 8, 9, 0, in: calendar)
        let evening = try BundleFixtures.date(2026, 3, 8, 22, 0, in: calendar)
        let cucumber = BundleFixtures.makeItem(name: "Cucumber", expiresAt: morning)
        let yogurt = BundleFixtures.makeItem(name: "Yogurt", expiresAt: evening)

        let bundles = bundleSameDayExpiries([cucumber, yogurt], calendar: calendar, now: now)

        #expect(bundles.count == 1)
        let bundle = try #require(bundles.first)
        #expect(bundle.itemIDs.count == 2)
        #expect(bundle.identifier == "day.20260308.expiry")
    }

    @Test("DST spring-forward day's lead trigger lands at 9am wall-clock")
    func dstSpringForwardTriggerLandsAtNineAMWallClock() throws {
        // Item expires Wed March 11 — 3-day lead is Sunday March 8,
        // the spring-forward day. Trigger should resolve to 9am wall
        // clock, not 8am.
        let calendar = try BundleFixtures.laCalendar()
        let now = try BundleFixtures.date(2026, 3, 1, 12, 0, in: calendar)
        let expiresAt = try BundleFixtures.date(2026, 3, 11, 12, 0, in: calendar)
        let item = BundleFixtures.makeItem(name: "Milk", expiresAt: expiresAt)

        let bundles = bundleSameDayExpiries([item], calendar: calendar, now: now)

        let bundle = try #require(bundles.first)
        let components = calendar.dateComponents([.hour, .minute], from: bundle.triggerDate)
        #expect(components.hour == 9)
        #expect(components.minute == 0)
        let expected = try BundleFixtures.date(2026, 3, 8, 9, 0, in: calendar)
        #expect(bundle.triggerDate == expected)
    }

    @Test("Day-grouping uses the injected calendar's timezone, not the host's")
    func dayGroupingHonoursInjectedTimezone() throws {
        // Same UTC instants, two timezones: New York vs Tokyo. The
        // bundling key is the *local* calendar day, so the same two
        // items will or won't group depending on which timezone the
        // injected calendar uses. This pins the contract.
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))

        // Construct two `Date` instants such that, in NY, both fall
        // on March 25; but in Tokyo, one falls on March 25 and the
        // other on March 26.
        // 2026-03-25 23:00 NY = 2026-03-26 12:00 Tokyo (next day).
        // 2026-03-25 09:00 NY = 2026-03-25 22:00 Tokyo (same day).
        var nyLate = DateComponents()
        nyLate.year = 2026
        nyLate.month = 3
        nyLate.day = 25
        nyLate.hour = 23
        let nyLateDate = try #require(ny.date(from: nyLate))

        var nyEarly = DateComponents()
        nyEarly.year = 2026
        nyEarly.month = 3
        nyEarly.day = 25
        nyEarly.hour = 9
        let nyEarlyDate = try #require(ny.date(from: nyEarly))

        let cucumber = Item(locationID: UUID(), name: "Cucumber", expiresAt: nyLateDate)
        let yogurt = Item(locationID: UUID(), name: "Yogurt", expiresAt: nyEarlyDate)

        let nyNow = try BundleFixtures.date(2026, 3, 1, 12, 0, in: ny)
        let nyBundles = bundleSameDayExpiries(
            [cucumber, yogurt],
            calendar: ny,
            now: nyNow
        )
        // NY: same local day, one bundle.
        #expect(nyBundles.count == 1)

        let tokyoNow = try BundleFixtures.date(2026, 3, 1, 12, 0, in: tokyo)
        let tokyoBundles = bundleSameDayExpiries(
            [cucumber, yogurt],
            calendar: tokyo,
            now: tokyoNow
        )
        // Tokyo: different local days (March 25 vs March 26), two
        // single-item bundles.
        #expect(tokyoBundles.count == 2)
        #expect(tokyoBundles[0].itemIDs.count == 1)
        #expect(tokyoBundles[1].itemIDs.count == 1)
    }
}
