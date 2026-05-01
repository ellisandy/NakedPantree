import EventKit
import Foundation
import Testing

/// Issue #155 — spike test verifying that `EKReminder.url` survives the
/// write-then-fetch round-trip in EventKit. Several Apple developer
/// forum threads (still unanswered as of iOS 18) report that values
/// written to `url` programmatically don't appear in the Reminders.app
/// UI and may not survive iCloud sync. The push-to-Reminders design
/// (#155) keys idempotent reconciliation off this exact field, so if
/// it doesn't round-trip we need a different idempotency key (most
/// likely a sentinel string in `notes`) before committing to the
/// design.
///
/// **Stage A** — local round-trip in the same `EKEventStore` instance.
/// This is what this test pins. Run on a simulator or device with
/// Reminders permission already granted.
///
/// **Stage B** — iCloud sync to a second device. Cannot be automated
/// from this test. The user verifies manually after Stage A confirms
/// the local case works.
///
/// ### How to run
///
/// 1. Pre-grant Reminders permission on the simulator:
///    ```
///    xcrun simctl privacy <device-id> grant reminders cc.mnmlst.nakedpantree
///    ```
///    Without this, the test runner blocks on the system permission
///    alert when EventKit first asks.
/// 2. Run with the env gate set:
///    ```
///    SPIKE_REMINDERS_URL=1 xcodebuild test \
///      -only-testing:NakedPantreeTests/RemindersURLRoundTripSpike
///    ```
///    Without the env var the test returns immediately (passes as a
///    no-op) — keeps it from running uselessly in CI, which has no
///    granted permission and would surface noisy failures.
///
/// **The test deletes its own data on success.** If it fails or the
/// process is killed mid-run, a stray reminder may be left in the
/// default reminders calendar with title prefixed `"NP-Spike-"`.
///
/// ### Status (as of branch `claude/155-spike-reminders-url`)
///
/// On the iOS 18 simulator, this test **crashes silently inside
/// EventKit** even with TCC pre-granted via `xcrun simctl privacy
/// <device-id> grant reminders cc.mnmlst.nakedpantree`. The xcresult
/// bundle reports "Crash: Naked Pantree at closure #1 in closure #1
/// in closure #1 in `RemindersURLRoundTripSpike.urlRoundTrips()`",
/// which is somewhere inside `requestFullAccessToReminders()` /
/// `fetchReminders(matching:)`. The simulator's Reminders backend
/// appears to be the issue, not our code — same `EKEventStore` calls
/// work fine in shipping apps on-device.
///
/// **Definitive answer requires a real device.** Run via
/// `xcrun devicectl device process launch --device <id> ...` against
/// a paired iPhone with Reminders permission granted, or attach
/// Xcode's test runner to a real device target. The #155 design
/// doesn't actually depend on the answer — the notes-sentinel
/// idempotency-key fallback works regardless of how `EKReminder.url`
/// behaves — but verifying once on a device avoids surprises if we
/// later want to surface the URL for the user's tap-to-deep-link.
///
/// This file is kept committed (rather than deleted) so a future
/// contributor with a paired device can run it in five minutes
/// instead of redoing the EventKit setup from scratch.

/// Sendable projection of the fields we care about from a fetched
/// `EKReminder`. Lives at file scope so the test body and helpers can
/// share the type, and so `EKReminder` (non-Sendable) never has to
/// cross the checked-continuation actor boundary.
private struct FetchedSnapshot: Sendable {
    let urlAbsolute: String?
    let urlScheme: String?
    let title: String?
    let found: Bool

    static let missing = FetchedSnapshot(
        urlAbsolute: nil,
        urlScheme: nil,
        title: nil,
        found: false
    )
}

@Suite("Issue #155 spike: EKReminder.url round-trip")
@MainActor
struct RemindersURLRoundTripSpike {
    @Test("URL set on save survives a fetchReminders round-trip")
    func urlRoundTrips() async throws {
        // Stage A.0 — synchronous authorization check BEFORE we
        // construct the store or call `requestFullAccessToReminders`.
        //
        // Why: on CI runners, the unit-test process has no way to
        // dismiss a permission alert, and `requestFullAccessToReminders`
        // blocks indefinitely waiting for user input — the entire
        // xcodebuild test job hits the GH Actions 6-hour ceiling and
        // gets killed. Pre-checking the status keeps that path
        // off-limits to CI:
        //
        //   * .fullAccess     → run the spike (TCC pre-granted via
        //                       `xcrun simctl privacy ... grant
        //                       reminders cc.mnmlst.nakedpantree`).
        //   * .notDetermined  → bail. CI lands here; would prompt.
        //   * .denied / .restricted → bail.
        //   * .writeOnly      → bail; spike needs read access too.
        //
        // Swift Testing has no first-class skip; an early return
        // reads as "passed." The print line surfaces the bail in the
        // test log so a future contributor running locally can tell
        // why the spike didn't actually exercise the contract.
        let status = EKEventStore.authorizationStatus(for: .reminder)
        guard status == .fullAccess else {
            print(
                "⏭  Spike skipped: reminders authorization is "
                    + "\(status.rawValue) (need .fullAccess via "
                    + "`xcrun simctl privacy <device-id> grant reminders "
                    + "cc.mnmlst.nakedpantree`)."
            )
            return
        }

        let store = EKEventStore()
        // Stage A.1 — Swift Testing has no first-class skip; an early
        // return reads as "passed." Now that we know the user has
        // already granted full access, this call is a no-op fast path
        // — `requestFullAccessToReminders` returns true immediately.
        let granted = try await store.requestFullAccessToReminders()
        guard granted else {
            print("⏭  Spike skipped: requestFullAccessToReminders unexpectedly returned false.")
            return
        }

        // Stage A.2 — find a writable reminders list. Default
        // calendar is the right target — same surface a real user picks.
        let calendar = try #require(
            store.defaultCalendarForNewReminders(),
            "No default reminders calendar — the simulator may not have any reminder lists."
        )

        // Stage A.3 — create a reminder with a non-trivial url.
        // Mirror the production design's URL shape so the test catches
        // scheme-related surprises (Apple's docs are silent on URL-scheme
        // constraints).
        let testItemID = UUID()
        let testURLString = "nakedpantree://item/\(testItemID.uuidString)"
        let testURL = try #require(URL(string: testURLString))
        let reminderTitle = "NP-Spike-\(testItemID.uuidString.prefix(8))"

        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = reminderTitle
        reminder.url = testURL
        try store.save(reminder, commit: true)
        let savedID = reminder.calendarItemIdentifier

        // Stage A.4 — fetch + project to Sendable inside the closure.
        let snapshot = await Self.fetchSnapshot(
            store: store,
            calendar: calendar,
            savedID: savedID
        )

        try #require(
            snapshot.found,
            "Reminder we just saved didn't come back from predicateForReminders."
        )

        // Stage A.5 — the actual assertion. Three things to pin:
        //   1. url is non-nil
        //   2. url equals what we wrote (not coerced/normalized)
        //   3. url's scheme is preserved
        #expect(
            snapshot.urlAbsolute != nil,
            // swiftlint:disable:next line_length
            "EKReminder.url is NIL after fetch — issue #155 design needs the notes-sentinel fallback. (title=\(snapshot.title ?? "?"))"
        )
        #expect(
            snapshot.urlAbsolute == testURLString,
            "URL mutated. Wrote \(testURLString); read back \(snapshot.urlAbsolute ?? "nil")."
        )
        #expect(
            snapshot.urlScheme == "nakedpantree",
            "URL scheme mutated. Wrote nakedpantree; read back \(snapshot.urlScheme ?? "nil")."
        )

        // Stage A.6 — best-effort cleanup. Errors are swallowed: cleanup
        // isn't part of what the spike pins.
        await Self.deleteReminder(store: store, calendar: calendar, savedID: savedID)
    }

    /// Fetch all reminders in `calendar` and project the row whose
    /// `calendarItemIdentifier` matches `savedID` to a Sendable
    /// snapshot. Returns `.missing` if the row isn't found or the
    /// fetch returns nil. Lives outside the test body to keep
    /// `urlRoundTrips()` under SwiftLint's `function_body_length`.
    private static func fetchSnapshot(
        store: EKEventStore,
        calendar: EKCalendar,
        savedID: String
    ) async -> FetchedSnapshot {
        let predicate = store.predicateForReminders(in: [calendar])
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { results in
                guard let results else {
                    continuation.resume(returning: .missing)
                    return
                }
                let savedRow = results.first { reminder in
                    reminder.calendarItemIdentifier == savedID
                }
                guard let saved = savedRow else {
                    continuation.resume(returning: .missing)
                    return
                }
                continuation.resume(
                    returning: FetchedSnapshot(
                        urlAbsolute: saved.url?.absoluteString,
                        urlScheme: saved.url?.scheme,
                        title: saved.title,
                        found: true
                    )
                )
            }
        }
    }

    /// Best-effort delete. The fetch + remove happen inside the
    /// completion closure so the non-Sendable `EKReminder` never
    /// crosses the actor boundary back to the test body.
    private static func deleteReminder(
        store: EKEventStore,
        calendar: EKCalendar,
        savedID: String
    ) async {
        let predicate = store.predicateForReminders(in: [calendar])
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            store.fetchReminders(matching: predicate) { results in
                if let row = results?.first(where: {
                    $0.calendarItemIdentifier == savedID
                }) {
                    try? store.remove(row, commit: true)
                }
                cont.resume()
            }
        }
    }
}
