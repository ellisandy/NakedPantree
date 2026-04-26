import CloudKit
import NakedPantreeDomain
import NakedPantreePersistence
import SwiftUI
import UIKit

/// `UIViewControllerRepresentable` over `UICloudSharingController`. iOS
/// 26 still doesn't have a SwiftUI-native participant manager — the
/// generic `ShareLink` doesn't surface CKShare semantics — so the bridge
/// is the supported path. See `ARCHITECTURE.md` §5.
///
/// The controller takes a `preparationHandler` so the share is created
/// lazily *while* the controller presents — that avoids leaving a
/// dangling CKShare behind if the user taps "Share" then dismisses
/// without inviting anyone.
struct CloudSharingControllerView: UIViewControllerRepresentable {
    let householdID: Household.ID
    let sharing: CloudHouseholdSharingService

    /// Fired when the controller dismisses (saved or cancelled). The
    /// caller drops the sheet binding and may want to refresh state.
    let onCompletion: () -> Void

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController { _, completion in
            // The controller calls this on the main queue once it's
            // ready to show participant UI. We hop to a Task to use the
            // async sharing API, then bounce results back via the
            // synchronous completion closure.
            Task {
                do {
                    let (share, container) = try await sharing.prepareShare(for: householdID)
                    await MainActor.run {
                        completion(share, container, nil)
                    }
                } catch {
                    await MainActor.run {
                        completion(nil, nil, error)
                    }
                }
            }
        }
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
            // Surfaced to the user by `UICloudSharingController` itself —
            // it shows an alert before dismissing. Nothing more for us
            // to do until 3.3 introduces user-facing feedback.
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
    @Entry var householdSharing: CloudHouseholdSharingService?
}
