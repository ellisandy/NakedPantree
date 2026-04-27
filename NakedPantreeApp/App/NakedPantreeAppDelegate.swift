import CloudKit
import NakedPantreePersistence
import SwiftUI
import UIKit
import UserNotifications

/// `UIApplicationDelegate` shim for the events SwiftUI's `App` lifecycle
/// doesn't natively expose:
///
/// 1. `application(_:userDidAcceptCloudKitShareWith:)` — Phase 3.2:
///    iCloud share-accept callback when a recipient taps an invite.
/// 2. `userNotificationCenter(_:didReceive:withCompletionHandler:)` —
///    Phase 4.2: notification-tap deep link to the relevant item.
///
/// Wired in via `@UIApplicationDelegateAdaptor` in `NakedPantreeApp`.
/// The delegate is instantiated by the system **before**
/// `NakedPantreeApp.init` runs, so we can't take collaborators via the
/// initializer. `NakedPantreeApp.init` writes the production
/// dependencies to the static vars below; preview / test branches
/// leave them `nil`, which means a stray invite or notification tap
/// during a test run no-ops instead of crashing.
final class NakedPantreeAppDelegate:
    NSObject,
    UIApplicationDelegate,
    UNUserNotificationCenterDelegate
{
    nonisolated(unsafe) static var shareAcceptance: CloudShareAcceptance?
    nonisolated(unsafe) static var notificationRouting: NotificationRoutingService?

    /// Setting `UNUserNotificationCenter.delegate` later than this
    /// (e.g. from a SwiftUI `.task`) drops cold-launch tap responses
    /// — iOS holds the response only until the launch sequence
    /// completes. Assigning here, with the `@UIApplicationDelegateAdaptor`-
    /// owned delegate already alive, is the system-supported seam.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        guard let acceptance = Self.shareAcceptance else { return }
        Task {
            do {
                try await acceptance.acceptShare(metadata: metadata)
            } catch {
                // The recipient already tapped Accept — there's no
                // user-actionable surface here without a separate UI
                // pass. RemoteChangeMonitor will tick once the import
                // lands; if it doesn't, that's an integration bug to
                // chase, not a per-tap retry.
                print("CloudKit share acceptance failed: \(error)")
            }
        }
    }

    /// Tap → publish parsed `itemID` to the routing service. RootView
    /// observes and either navigates to the detail or shows the
    /// "That item is gone" alert (item missing, e.g. another household
    /// member deleted it before the tap). Per ARCHITECTURE.md §8 the
    /// missing-item case should land on Expiring Soon — the smart list
    /// is stubbed until Phase 6, so the interim is a banner alert in
    /// place; the §8 note records the divergence.
    /// `nonisolated` because `UIApplicationDelegate` makes this class
    /// implicitly main-actor-isolated, but `UNUserNotificationCenterDelegate`
    /// requirements are nonisolated. The delegate method itself does
    /// only synchronous, thread-safe work (parse the payload, call the
    /// completion handler) and hops to the main actor before touching
    /// the routing service's stored property.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        defer { completionHandler() }
        guard
            let id = notificationItemID(from: response.notification.request.content.userInfo),
            let routing = Self.notificationRouting
        else { return }
        Task { @MainActor in
            routing.pendingItemID = id
        }
    }
}
