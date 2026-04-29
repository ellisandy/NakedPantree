import CloudKit
import NakedPantreeDomain
import NakedPantreePersistence
import SwiftUI
import UIKit
import os

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
    let sharing: any HouseholdSharingService

    /// Fired when the controller dismisses (saved or cancelled). The
    /// caller drops the sheet binding and may want to refresh state.
    let onCompletion: () -> Void

    /// Trace for #90 (blank Share Household sheet on TestFlight).
    /// Visible via Console.app filtered by subsystem
    /// `cc.mnmlst.nakedpantree`, category `sharing`. Same lifetime
    /// note as `CloudHouseholdSharingService.logger` — keep until #90
    /// is fully closed.
    ///
    /// `nonisolated` because `UIViewControllerRepresentable` infers
    /// `@MainActor` on the struct, but the `Task` in the preparation
    /// handler runs off-main and reads `Self.logger` from there.
    nonisolated private static let logger = Logger(
        subsystem: "cc.mnmlst.nakedpantree",
        category: "sharing"
    )

    /// Cap on how long we wait for `prepareShare` before surfacing a
    /// timeout error to the controller. 60s is generous — first-time
    /// share creation can legitimately spend many seconds in
    /// `NSPersistentCloudKitContainer.share(_:to:)` while CloudKit
    /// lazy-creates the shared zone — but it's tight enough that a
    /// genuine hang produces an alert instead of an indefinitely
    /// blank sheet (the symptom in #90). Same `nonisolated` rationale
    /// as `logger`.
    nonisolated private static let prepareShareTimeout: Duration = .seconds(60)

    func makeUIViewController(context: Context) -> UICloudSharingController {
        Self.logger.notice("makeUIViewController: creating UICloudSharingController")
        let controller = UICloudSharingController { _, completion in
            // The controller calls this on the main queue once it's
            // ready to show participant UI. We race `prepareShare`
            // against a timeout (#90) so a hang surfaces as an error
            // alert instead of a blank sheet.
            Self.logger.notice("preparation handler fired — racing prepareShare against timeout")
            Task {
                let outcome = await runPrepareShareWithTimeout()
                await MainActor.run {
                    switch outcome {
                    case .success(let payload):
                        Self.logger.notice("preparation handler: completion(share, container, nil)")
                        completion(payload.share, payload.container, nil)
                    case .failure(let error):
                        let description = error.localizedDescription
                        Self.logger.error(
                            "preparation handler: completion(nil, nil, \(description, privacy: .public))"
                        )
                        completion(nil, nil, error)
                    }
                }
            }
        }
        controller.delegate = context.coordinator
        return controller
    }

    /// Runs `prepareShare(for:)` on the actor-isolated service, racing
    /// it against `prepareShareTimeout`. Whichever wins wins; the
    /// loser is cancelled. Returns the outcome as a value so the
    /// caller can dispatch onto MainActor in one place.
    private func runPrepareShareWithTimeout() async -> Result<SharePayload, Error> {
        let timeout = Self.prepareShareTimeout
        let householdID = householdID
        let sharing = sharing
        return await withTaskGroup(of: Result<SharePayload, Error>.self) { group in
            group.addTask {
                do {
                    let (share, container) = try await sharing.prepareShare(for: householdID)
                    return .success(SharePayload(share: share, container: container))
                } catch {
                    return .failure(error)
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                Self.logger.error(
                    "prepareShare timed out after \(timeout, privacy: .public)"
                )
                return .failure(SharingTimeoutError())
            }
            let first = await group.next() ?? .failure(SharingTimeoutError())
            group.cancelAll()
            return first
        }
    }

    /// Tuple-shaped payload kept as a struct so the `Result.success`
    /// destructure at the call site is a single binding (sidesteps the
    /// swift-format / swiftlint disagreement on multi-bound `let` /
    /// `case let` forms).
    private struct SharePayload {
        let share: CKShare
        let container: CKContainer
    }

    private struct SharingTimeoutError: LocalizedError {
        var errorDescription: String? {
            // Surfaced to the user by `UICloudSharingController`'s own
            // alert — keep terse and actionable.
            "Couldn't reach iCloud to prepare the share. Try again — "
                + "if it keeps happening, check the iCloud account in Settings."
        }
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
    /// Production binds `CloudHouseholdSharingService`; UI tests can
    /// inject `StubHouseholdSharingService` via the `STUB_SHARING`
    /// env var (see `NakedPantreeApp.init`).
    @Entry var householdSharing: (any HouseholdSharingService)?
}
