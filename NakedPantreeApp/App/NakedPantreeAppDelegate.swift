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
    /// Production sinks. Pre-#108, these were assigned directly by
    /// `NakedPantreeApp.init` and the delegate methods above
    /// silently dropped events delivered before init ran. Now use
    /// `wireShareAcceptance(_:)` / `wireNotificationRouting(_:)`
    /// which both assign the seam **and** drain any pre-init
    /// queued events.
    nonisolated(unsafe) static var shareAcceptance: CloudShareAcceptance?
    nonisolated(unsafe) static var notificationRouting: NotificationRoutingService?

    /// Pre-init event queues (issue #108). iOS can deliver the
    /// `userDidAcceptCloudKitShareWith` and `didReceive` delegate
    /// methods *before* `NakedPantreeApp.init` runs — the system
    /// instantiates the AppDelegate first, then SwiftUI's `App`
    /// initializer. Pre-#108 those events were silently dropped
    /// because the seam vars were still `nil`.
    ///
    /// Both delegate methods run on the main thread (the system
    /// dispatches them there for `UIApplicationDelegate`), and
    /// `NakedPantreeApp.init` also runs on main, so these arrays
    /// don't see concurrent access in practice. `nonisolated(unsafe)`
    /// matches the existing seam-var declarations above.
    nonisolated(unsafe) static var pendingShareMetadata: [CKShare.Metadata] = []
    nonisolated(unsafe) static var pendingNotificationItemIDs: [UUID] = []

    /// Wire the share-acceptance sink and drain any events queued
    /// before this call. Replace the previous `Self.shareAcceptance =
    /// acceptance` direct assignment with this method to recover
    /// pre-init events.
    static func wireShareAcceptance(_ acceptance: CloudShareAcceptance) {
        shareAcceptance = acceptance
        let pending = pendingShareMetadata
        pendingShareMetadata = []
        for metadata in pending {
            Task {
                do {
                    try await acceptance.acceptShare(metadata: metadata)
                } catch {
                    print("CloudKit share acceptance failed (drain): \(error)")
                }
            }
        }
    }

    /// Wire the notification-routing sink and apply any pre-init
    /// taps. Only the **most recent** queued tap wins — same
    /// "last tap wins" semantic as the live tap-ordering fix in
    /// #119. Earlier taps in the same launch sequence are
    /// effectively superseded.
    static func wireNotificationRouting(_ routing: NotificationRoutingService) {
        notificationRouting = routing
        let pending = pendingNotificationItemIDs
        pendingNotificationItemIDs = []
        if let lastID = pending.last {
            Task { @MainActor in
                routing.pendingItemID = lastID
            }
        }
    }

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
        // #108: queue if the seam isn't wired yet. iOS may deliver
        // share-accept during cold launch *before*
        // `NakedPantreeApp.init` has assigned the sink — the queue is
        // drained by `wireShareAcceptance(_:)` once init runs.
        guard let acceptance = Self.shareAcceptance else {
            Self.pendingShareMetadata.append(metadata)
            return
        }
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
    /// observes and either navigates to the detail or — if the item
    /// has been deleted — lands on Expiring Soon and shows the
    /// "That item is gone" alert per ARCHITECTURE.md §8.
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
        let userInfo = response.notification.request.content.userInfo
        guard let id = notificationItemID(from: userInfo) else {
            completionHandler()
            return
        }
        // #108: queue if the seam isn't wired yet. iOS may deliver a
        // notification tap during cold launch *before*
        // `NakedPantreeApp.init` has assigned the sink — the queue is
        // drained by `wireNotificationRouting(_:)`, with last-tap-wins
        // semantics matching the live tap-ordering fix in #119.
        guard let routing = Self.notificationRouting else {
            Self.pendingNotificationItemIDs.append(id)
            completionHandler()
            return
        }
        // #119: previously this method used `defer { completionHandler() }`,
        // which signalled "done" before the `Task { @MainActor in }` had
        // a chance to publish `pendingItemID`. Two consecutive taps could
        // interleave on MainActor and the *earlier* tap could win the
        // routing slot, dropping the user's most recent intent. Call
        // `completionHandler()` AFTER the publish: the Task is enqueued
        // on MainActor before this nonisolated method returns, and
        // tasks awaiting the same actor honour FIFO arrival order, so
        // tap A's Task runs before tap B's Task and `pendingItemID`
        // ends up matching the last tap.
        Task { @MainActor in
            routing.pendingItemID = id
            completionHandler()
        }
    }
}
