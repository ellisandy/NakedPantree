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

        func itemTitle(for csc: UICloudSharingController) -> String? {
            "Naked Pantree"
        }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            // `UICloudSharingController` shows its own alert for the
            // failure before dismissing; we just propagate the
            // dismissal up so the sheet binding clears.
            onCompletion()
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            onCompletion()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
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
