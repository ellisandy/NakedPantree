import CloudKit
import Foundation
import NakedPantreeDomain
import NakedPantreePersistence
import os

/// Top-level helper that bridges `HouseholdSharingService.prepareShare`
/// to the `UICloudSharingController` presentation flow. Issue #90.
///
/// **Why it exists.** `UICloudSharingController(preparationHandler:)`
/// was deprecated in iOS 17, and on iOS 17+/26 simulators we observed
/// the preparation handler closure simply never being invoked — leaving
/// the user staring at a blank sheet (the literal #90 symptom). Apple's
/// non-deprecated initializer is `init(share:container:)`, which
/// requires the share to exist *before* the controller is constructed.
/// That moves the prep step out of the controller and up to the parent
/// view, which is exactly what this helper supports.
///
/// The race-against-timeout shape that used to live on
/// `CloudSharingControllerView.runPrepareShareWithTimeout` lives here
/// now — a hang in `prepareShare` should still surface as an alert
/// rather than a perceptibly-stuck "Preparing…" spinner.
enum ShareSheetPreparation {
    /// `Identifiable` so SwiftUI can drive a `.sheet(item:)` binding
    /// off the prepared payload. The id is fresh per prepare call so
    /// presenting twice in a row replaces the sheet rather than
    /// reusing a stale instance.
    struct PreparedShare: Identifiable, Sendable {
        let id = UUID()
        let share: CKShare
        let container: CKContainer
    }

    /// Surfaced in the user-facing alert when the prepare step
    /// exceeds `timeout`. Same copy as the legacy in-controller
    /// timeout — keep terse and actionable.
    struct TimeoutError: LocalizedError {
        var errorDescription: String? {
            "Couldn't reach iCloud to prepare the share. Try again — "
                + "if it keeps happening, check the iCloud account in Settings."
        }
    }

    /// Default upper bound on how long the parent view spins waiting
    /// for `prepareShare`. 60s matches the legacy timeout — long
    /// enough to cover first-share latency on a slow connection,
    /// short enough that a genuine hang produces an alert instead
    /// of an indefinitely stuck UI.
    static let defaultTimeout: Duration = .seconds(60)

    /// Trace lines come out under the same subsystem/category as
    /// `CloudSharingControllerView` and `CloudHouseholdSharingService`,
    /// so a single `subsystem:cc.mnmlst.nakedpantree` filter in
    /// Console.app captures the whole share path.
    private static let logger = Logger(
        subsystem: "cc.mnmlst.nakedpantree",
        category: "sharing"
    )

    /// Race `service.prepareShare(for:)` against `timeout`. Whichever
    /// task wins the group's first slot wins; the loser is cancelled.
    /// The shape mirrors the old `runPrepareShareWithTimeout` so the
    /// test suite that drove that helper carries forward verbatim.
    static func prepareShare(
        for householdID: Household.ID,
        using service: any HouseholdSharingService,
        timeout: Duration = defaultTimeout
    ) async -> Result<PreparedShare, Error> {
        Self.logger.notice(
            "ShareSheetPreparation.prepareShare start: \(householdID, privacy: .public)"
        )
        return await withTaskGroup(of: Result<PreparedShare, Error>.self) { group in
            group.addTask {
                do {
                    let (share, container) = try await service.prepareShare(for: householdID)
                    return .success(PreparedShare(share: share, container: container))
                } catch {
                    return .failure(error)
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                Self.logger.error(
                    "ShareSheetPreparation timed out after \(timeout, privacy: .public)"
                )
                return .failure(TimeoutError())
            }
            let first = await group.next() ?? .failure(TimeoutError())
            group.cancelAll()
            switch first {
            case .success:
                Self.logger.notice("ShareSheetPreparation succeeded — payload ready")
            case .failure(let error):
                Self.logger.error(
                    "ShareSheetPreparation failed: \(error.localizedDescription, privacy: .public)"
                )
            }
            return first
        }
    }
}
