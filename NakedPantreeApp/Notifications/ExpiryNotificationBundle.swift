import Foundation
import NakedPantreeDomain

/// One scheduled expiry notification, ready for the scheduler to convert
/// into a `UNNotificationRequest`. May represent a single item or a
/// rollup of multiple items expiring on the same local calendar day.
///
/// Phase 9.4 / issue #56. The pure-data shape lets `bundleSameDayExpiries`
/// stay testable in isolation — no scheduler, no `UNUserNotificationCenter`,
/// no I/O. The scheduler integration in `NotificationScheduler.resync` is
/// the parent's job; this file only owns the bundling logic.
struct ExpiryNotificationBundle: Sendable, Equatable {
    /// Stable identifier for `UNNotificationRequest`.
    ///
    /// - Single-item bundle: `"item.<uuid>.expiry"` — matches
    ///   `NotificationScheduler.identifier(for:)` so reschedule keeps
    ///   working unchanged when a day collapses from N → 1 items.
    /// - Multi-item bundle: `"day.<yyyyMMdd>.expiry"` — derived from the
    ///   day-of-expiry key so editing any one item's expiry rescheduling
    ///   collapses cleanly. The parent's `staleExpiryIdentifiers` sweep
    ///   needs to learn this pattern (see integration note in the PR
    ///   description).
    let identifier: String

    /// When the notification should fire. For future-trigger bundles
    /// this is the chosen reminder time (e.g. 9am local) on the lead
    /// day; for past-trigger bundles it's `now + 60s` so the
    /// notification fires immediately. The scheduler chooses
    /// `UNCalendarNotificationTrigger` vs `UNTimeIntervalNotificationTrigger`
    /// based on which range it falls in.
    let triggerDate: Date

    let title: String
    let body: String

    /// Items represented by this bundle. Single-item bundles have one
    /// element; multi-item bundles have N. The notification tap handler
    /// can deep-link to the first item or surface the expiring-soon list.
    let itemIDs: [Item.ID]

    /// True when every item in the bundle is already past its expiry
    /// at scheduling time. Used by the scheduler to pick an immediate
    /// trigger vs a calendar trigger and surfaced for tests.
    let firesImmediately: Bool
}

/// Groups items by the local-calendar day of their `expiresAt` and
/// returns one `ExpiryNotificationBundle` per day. Pure function over
/// `(items, reminder time, lead, calendar, now)` — same shape as
/// `itemsRecentlyAdded` / `itemsExpiringSoon`. Tests pin `calendar` and
/// `now` to lock behavior across timezones and DST boundaries.
///
/// **Bundling rules:**
/// - Items with `expiresAt == nil` are dropped (same as
///   `itemsExpiringSoon`).
/// - Items grouped by the local calendar day of `expiresAt`, using the
///   *injected* calendar — not `Calendar.current`. Items at 11pm and
///   1am local in adjacent days are different days even when their
///   absolute timestamps are an hour apart.
/// - For each day's group:
///   - 1 item → single-item bundle, copy unchanged from per-item path
///     (`item.name` title, `expiryNotificationBodyCopy(...)` body),
///     identifier matches `NotificationScheduler.identifier(for:)`.
///   - N ≥ 2 items → rollup bundle. Lead name is the alphabetically-first
///     name (deterministic, testable). Title and body follow the §3 +
///     §10 voice rules: useful, short, no humor (notifications are
///     mid-stakes).
/// - Items whose computed lead trigger has already passed (either the
///   item is past expiry, or it's expiring within the lead window
///   already) get an immediate trigger of `now + 60s`. The 60-second
///   pad keeps `UNTimeIntervalNotificationTrigger`'s ≥1s requirement
///   well-clear of any "fire while still scheduling" race. Past-expiry
///   items use past-tense copy ("have expired"); items expiring inside
///   the lead window use future-tense copy ("expires tomorrow") — both
///   still fire immediately because the user wants to know now.
///
/// The function is sort-deterministic: bundles are returned ordered by
/// `triggerDate` ascending, ties broken by identifier.
///
/// - Parameters:
///   - items: Items to consider. `expiresAt == nil` filtered out.
///   - reminderHour: Hour-of-day (local) the future-trigger bundles
///     fire. Phase 9.3 will inject this from settings; default 9 matches
///     the existing per-item path.
///   - reminderMinute: Minute-of-hour, default 0.
///   - leadDays: How far ahead of expiry to fire. Default 3 matches
///     §8 of `ARCHITECTURE.md` and the existing per-item path.
///   - calendar: Calendar used for day-grouping and trigger
///     construction. Inject in tests.
///   - now: Reference "now" for past-trigger detection and immediate-
///     trigger date. Inject in tests.
/// - Returns: One bundle per occupied day, ordered by trigger date.
func bundleSameDayExpiries(
    _ items: [Item],
    reminderHour: Int = 9,
    reminderMinute: Int = 0,
    leadDays: Int = 3,
    calendar: Calendar = .current,
    now: Date = Date()
) -> [ExpiryNotificationBundle] {
    // Filter to items with a real expiry, then group by the local
    // calendar day of that expiry. Using the injected calendar's
    // `startOfDay(for:)` yields a `Date` that's stable across the same
    // local day and so works as a dictionary key — DST transitions
    // don't break grouping because `startOfDay` accounts for them.
    let withExpiry = items.compactMap { item -> (Item, Date)? in
        guard let expiresAt = item.expiresAt else { return nil }
        return (item, expiresAt)
    }

    let grouped = Dictionary(grouping: withExpiry) { _, expiresAt in
        calendar.startOfDay(for: expiresAt)
    }

    let bundles = grouped.compactMap { dayStart, pairs -> ExpiryNotificationBundle? in
        // Items in a day's group may not all share the same
        // `expiresAt` instant — pick the soonest as the canonical
        // expiry for body-copy purposes. (For multi-item bundles we
        // don't show the time anyway; for single-item it's the actual
        // expiry of that item.)
        let sortedByExpiry = pairs.sorted { $0.1 < $1.1 }
        let canonicalExpiresAt = sortedByExpiry[0].1
        let dayItems = sortedByExpiry.map(\.0)

        // Compute the future trigger date: lead-day's reminder time
        // in the injected calendar. If we can't form it, fall through
        // to immediate.
        let leadDay = calendar.date(byAdding: .day, value: -leadDays, to: dayStart)
        let futureTrigger = leadDay.flatMap {
            calendar.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: $0)
        }

        // Choose trigger: future if it's still ahead of `now`, else
        // immediate (60s pad past `now`). Also detect "already past
        // expiry" for past-tense copy.
        let isAllPastExpiry = sortedByExpiry.allSatisfy { $0.1 <= now }
        let firesImmediately: Bool
        let triggerDate: Date
        if let future = futureTrigger, future > now {
            firesImmediately = false
            triggerDate = future
        } else {
            firesImmediately = true
            triggerDate = now.addingTimeInterval(60)
        }

        let identifier = bundleIdentifier(
            dayItems: dayItems,
            dayStart: dayStart,
            calendar: calendar
        )

        let (title, body) = bundleCopy(
            items: dayItems,
            canonicalExpiresAt: canonicalExpiresAt,
            triggerDate: triggerDate,
            isAllPastExpiry: isAllPastExpiry
        )

        return ExpiryNotificationBundle(
            identifier: identifier,
            triggerDate: triggerDate,
            title: title,
            body: body,
            itemIDs: dayItems.map(\.id),
            firesImmediately: firesImmediately
        )
    }

    return bundles.sorted { lhs, rhs in
        if lhs.triggerDate != rhs.triggerDate {
            return lhs.triggerDate < rhs.triggerDate
        }
        return lhs.identifier < rhs.identifier
    }
}

/// Builds the stable identifier for a bundle. Single-item bundles match
/// `NotificationScheduler.identifier(for:)` exactly — that's load-bearing
/// for the resync path: when a day collapses from N items to 1, the
/// rollup identifier disappears and the per-item identifier returns,
/// and the scheduler's existing `removePendingNotificationRequests`
/// sweep handles it without special-casing.
///
/// Multi-item identifiers use `yyyyMMdd` of the day key, formed from
/// calendar components (not `DateFormatter`) so the result is stable
/// across locales and timezones.
private func bundleIdentifier(
    dayItems: [Item],
    dayStart: Date,
    calendar: Calendar
) -> String {
    if dayItems.count == 1, let only = dayItems.first {
        return "item.\(only.id.uuidString).expiry"
    }
    let components = calendar.dateComponents([.year, .month, .day], from: dayStart)
    let year = components.year ?? 0
    let month = components.month ?? 0
    let day = components.day ?? 0
    let stamp = String(format: "%04d%02d%02d", year, month, day)
    return "day.\(stamp).expiry"
}

/// Builds title + body for a bundle. Single-item copy matches the
/// existing per-item path; multi-item copy follows the §3 voice rules
/// (useful, short, no humor at mid-stakes notifications).
///
/// **Variants** (N = item count, lead = alphabetically-first name):
/// - Single, future: title `item.name`, body `expiryNotificationBodyCopy(...)`.
/// - Single, past: title `item.name`, body `"\(item.name) has expired."`.
/// - N≥2, future: title `"\(N) items expiring soon"`,
///   body `"\(lead) + \(N-1) other(s) expire(s) \(relative)."`
/// - N≥2, past: title `"\(N) items expired"`,
///   body `"\(lead) + \(N-1) other(s) ha(s/ve) expired."`
///
/// Subject-verb agreement on `expires`/`expire` and `has`/`have` is
/// driven by the count of "others" — singular for 1, plural for 2+ —
/// not the total item count. Title agrees with body voice: future
/// rollups read "expiring soon"; past rollups read "expired" so the
/// banner doesn't claim something is upcoming when it isn't.
private func bundleCopy(
    items: [Item],
    canonicalExpiresAt: Date,
    triggerDate: Date,
    isAllPastExpiry: Bool
) -> (title: String, body: String) {
    if items.count == 1, let only = items.first {
        let title = only.name
        let body: String
        if isAllPastExpiry {
            body = "\(only.name) has expired."
        } else {
            body = expiryNotificationBodyCopy(
                expiresAt: canonicalExpiresAt,
                relativeTo: triggerDate
            )
        }
        return (title, body)
    }

    // Multi-item: pick the alphabetically-first name as the lead so
    // the copy is deterministic regardless of input order. Test
    // fixtures should make this rule visible.
    let names = items.map(\.name).sorted {
        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
    }
    let lead = names[0]
    let othersCount = names.count - 1
    let othersWord = othersCount == 1 ? "other" : "others"

    let title: String
    let body: String
    if isAllPastExpiry {
        // Title must agree with body — "expiring soon" reads false
        // when the items have already expired (§10 checklist item 1).
        title = "\(items.count) items expired"
        let verb = othersCount == 1 ? "has" : "have"
        body = "\(lead) + \(othersCount) \(othersWord) \(verb) expired."
    } else {
        title = "\(items.count) items expiring soon"
        let verb = othersCount == 1 ? "expires" : "expire"
        let relative = relativeExpiryPhrase(expiresAt: canonicalExpiresAt, relativeTo: triggerDate)
        body = "\(lead) + \(othersCount) \(othersWord) \(verb) \(relative)."
    }
    return (title, body)
}

/// Same `RelativeDateTimeFormatter` shape as `expiryNotificationBodyCopy`,
/// returning just the relative phrase (no `"Expires "` prefix, no
/// trailing period). The multi-item body composes its own sentence so
/// it doesn't double up on punctuation.
private func relativeExpiryPhrase(expiresAt: Date, relativeTo reference: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    formatter.dateTimeStyle = .named
    return formatter.localizedString(for: expiresAt, relativeTo: reference)
}
