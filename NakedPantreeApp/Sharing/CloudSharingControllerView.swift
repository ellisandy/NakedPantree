import CloudKit
import NakedPantreeDomain
import NakedPantreePersistence
import SwiftUI
import UIKit
import os

/// `UIViewControllerRepresentable` over `UICloudSharingController`.
///
/// **Issue #90 / Phase 11 refactor.** Earlier shipping versions used
/// `UICloudSharingController.init(preparationHandler:)` so the share
/// could be created lazily *while* the controller presented (avoiding
/// a dangling `CKShare` if the user dismissed without inviting). That
/// initializer was deprecated in iOS 17, and on iOS 17+/26 simulators
/// we observed the preparation handler closure silently never being
/// invoked — leaving the user with a blank sheet (the literal #90
/// symptom).
///
/// The fix is to move share preparation up to the parent view via
/// `ShareSheetPreparation`, then pass the resolved `(CKShare, CKContainer)`
/// to the non-deprecated `init(share:container:)`. The controller
/// renders participant UI immediately because the share already
/// exists. The orphan-share trade-off (a tap of "Share Household"
/// followed by an immediate dismiss leaves a CKShare on iCloud)
/// is accepted: `CloudHouseholdSharingService.prepareShare` is
/// idempotent — the next tap reuses the existing share via
/// `existingShare(matching:)`. A follow-up issue covers cleaning up
/// truly-empty shares on dismiss.
struct CloudSharingControllerView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    /// Fired when the controller dismisses (saved or cancelled). The
    /// caller drops the sheet binding and may want to refresh state.
    let onCompletion: () -> Void

    /// Trace for #90. Visible via Console.app filtered by subsystem
    /// `cc.mnmlst.nakedpantree`, category `sharing`. Same lifetime
    /// note as `CloudHouseholdSharingService.logger` — keep until #90
    /// is fully closed and the failure mode is documented in
    /// DEVELOPMENT.md §7.
    nonisolated private static let logger = Logger(
        subsystem: "cc.mnmlst.nakedpantree",
        category: "sharing"
    )

    func makeUIViewController(context: Context) -> UICloudSharingController {
        // Diag (post-#90 follow-up) — answer "what state is the share
        // in at the moment we hand it to the system controller?" The
        // Messages link-preview hang is most plausibly explained by
        // `share.url` being nil here; the system controller would
        // then hand a nil URL to the Messages share extension. Log
        // the full state so the trace ends the speculation.
        let urlString = share.url?.absoluteString ?? "<nil>"
        let recordName = share.recordID.recordName
        let participantCount = share.participants.count
        // print() fallback — the prior two share traces had our
        // Logger.notice entries silently dropping in this exact window
        // (between prepareShare and Messages activation). stderr
        // survives os_log batching / Console de-dup, so we get a hard
        // answer to "did UICloudSharingController see a populated URL?"
        print(
            "[NP-MAKEVC] url=\(urlString) recordName=\(recordName) participants=\(participantCount)"
        )
        Self.logger.notice(
            // swiftlint:disable:next line_length
            "makeUIViewController: share state url='\(urlString, privacy: .public)' recordName='\(recordName, privacy: .public)' participants.count=\(participantCount, privacy: .public)"
        )
        Self.logger.notice(
            "makeUIViewController: creating UICloudSharingController(share:container:)"
        )
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {
        // No-op — the controller manages its own lifecycle.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let onCompletion: () -> Void

        init(onCompletion: @escaping () -> Void) {
            self.onCompletion = onCompletion
        }

        nonisolated private static let logger = Logger(
            subsystem: "cc.mnmlst.nakedpantree",
            category: "sharing"
        )

        func itemTitle(for csc: UICloudSharingController) -> String? {
            Self.logger.notice("delegate.itemTitle requested")
            return "Naked Pantree"
        }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            // `UICloudSharingController` shows its own alert for the
            // failure before dismissing; we just propagate the
            // dismissal up so the sheet binding clears.
            Self.logger.error(
                "delegate.failedToSaveShare: \(error.localizedDescription, privacy: .public)"
            )
            onCompletion()
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            // Post-save the share's `url` should be populated by
            // CloudKit. Log it so a trace from a successful invite +
            // a hanging-Messages invite can be compared side by side.
            let urlString = csc.share?.url?.absoluteString ?? "<nil>"
            Self.logger.notice(
                "delegate.didSaveShare: post-save url='\(urlString, privacy: .public)'"
            )
            onCompletion()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            Self.logger.notice("delegate.didStopSharing")
            onCompletion()
        }
    }
}

extension EnvironmentValues {
    /// `nil` in previews / tests / snapshot mode — the "Share Household"
    /// button hides itself rather than presenting a broken sheet.
    /// Production binds `CloudHouseholdSharingService`; UI tests can
    /// inject `StubHouseholdSharingService` via the `STUB_SHARING`
    /// env var (see `NakedPantreeApp.init`).
    @Entry var householdSharing: (any HouseholdSharingService)?
}
