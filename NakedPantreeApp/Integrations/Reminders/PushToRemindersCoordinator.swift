import Foundation
import NakedPantreeDomain
import SwiftUI

/// Issue #155 — orchestrates the "Push to Reminders" flow from the
/// `NeedsRestockingView` toolbar button. Pulled out of the view body
/// so the state machine + service wiring can be unit-tested without
/// driving SwiftUI, and so the same flow can be reused from the
/// Settings re-pick path.
///
/// **Flow:**
/// 1. `requestPush(items:locationsByID:)` — entry point. Resolves
///    permission lazily.
/// 2. If permission denied → publish `.permissionDenied` for the UI's
///    inline error + Settings deep link.
/// 3. If no list chosen → publish `.needsListPick(lists)` so the view
///    presents the picker. Caller writes the choice via
///    `setChosenListID(_:)` and re-invokes `requestPush`.
/// 4. With permission + list → fetch existing snapshots, run the
///    reconciler, apply the plan.
/// 5. Publish `.completed(summary)` for the toast.
///
/// Errors at any stage land in `.failed(message)` with a short user-
/// facing string. The view treats the four states uniformly — the
/// state enum is the API contract.
@Observable
@MainActor
final class PushToRemindersCoordinator {
    /// Publishable state. The view observes this and drives the UI
    /// off whichever case is active. `.idle` between flows; the
    /// .needsListPick / .permissionDenied / .completed / .failed
    /// states each carry the data the view renders.
    enum State: Equatable {
        case idle
        case running
        case needsListPick(lists: [RemindersListSummary])
        case permissionDenied
        case completed(summary: PushSummary)
        case failed(message: String)
    }

    /// Shape of the post-push toast message. The view renders
    /// "Pushed N items to <list>." — the count and list name come
    /// from here.
    struct PushSummary: Equatable {
        let createdCount: Int
        let updatedCount: Int
        let completedCount: Int
        let listTitle: String

        var totalChanges: Int { createdCount + updatedCount + completedCount }
    }

    private(set) var state: State = .idle

    private let service: any RemindersService
    private let preference: RemindersListPreference

    init(
        service: any RemindersService,
        preference: RemindersListPreference
    ) {
        self.service = service
        self.preference = preference
    }

    /// Acknowledge the most recent terminal state (`.completed`,
    /// `.failed`, `.permissionDenied`). The view calls this when the
    /// toast / banner dismisses so a follow-up tap starts from
    /// `.idle`. `.needsListPick` is dismissed via `setChosenListID`
    /// (positive case) or `cancelListPick` (user backed out).
    func acknowledge() {
        if case .running = state { return }
        state = .idle
    }

    /// User picked a list from the picker sheet. Persist + re-run
    /// the push so a single sequence (tap → pick → push) lands
    /// without a second tap.
    func setChosenListID(
        _ listID: String,
        items: [Item],
        locationsByID: [Location.ID: Location]
    ) async {
        preference.listID = listID
        await requestPush(items: items, locationsByID: locationsByID)
    }

    /// User backed out of the picker sheet. Return to `.idle` without
    /// touching the preference — the next push tries the same flow
    /// from the top.
    func cancelListPick() {
        state = .idle
    }

    /// Top-level entry point. Idempotent against repeated taps —
    /// guards on `running` so concurrent invocations don't race.
    func requestPush(
        items: [Item],
        locationsByID: [Location.ID: Location]
    ) async {
        if case .running = state { return }
        state = .running

        do {
            // 1. Permission.
            let access = try await service.requestAccess()
            guard access == .granted else {
                state = .permissionDenied
                return
            }

            // 2. Resolve list. Either we have one stored or we ask.
            let listID: String
            let listTitle: String
            if let stored = preference.listID {
                let lists = try await service.availableLists()
                if let match = lists.first(where: { $0.id == stored }) {
                    listID = match.id
                    listTitle = match.title
                } else {
                    // Stored list was deleted in Reminders. Re-prompt
                    // — don't silently fall back. Spec: "surface a
                    // one-time 'Pick a new list' prompt and don't
                    // silently fall back."
                    preference.listID = nil
                    state = .needsListPick(lists: lists)
                    return
                }
            } else {
                let lists = try await service.availableLists()
                state = .needsListPick(lists: lists)
                return
            }

            // 3. Reconcile.
            let existing = try await service.snapshots(in: listID)
            let plan = RemindersReconciler.plan(
                items: items,
                existing: existing,
                locationsByID: locationsByID
            )

            // 4. Apply.
            try await service.apply(plan, in: listID)

            state = .completed(
                summary: PushSummary(
                    createdCount: plan.creates.count,
                    updatedCount: plan.titleUpdates.count,
                    completedCount: plan.completions.count,
                    listTitle: listTitle
                )
            )
        } catch let error as RemindersServiceError {
            state = .failed(message: Self.message(for: error))
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    /// Map predictable `RemindersServiceError` cases to short user-
    /// facing strings. Falls through to the localized description for
    /// anything we haven't explicitly classified.
    private static func message(for error: RemindersServiceError) -> String {
        switch error {
        case .accessNotGranted:
            return "Reminders access isn't granted yet."
        case .listNotFound:
            return "That list isn't there anymore. Pick another one."
        case .unexpected(let message):
            return message
        }
    }
}
