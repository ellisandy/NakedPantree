import CloudKit
import NakedPantreePersistence
import SwiftUI
import UIKit

/// `UIApplicationDelegate` shim for the one event SwiftUI's `App`
/// lifecycle doesn't natively expose: the iCloud share-accept callback
/// (`application(_:userDidAcceptCloudKitShareWith:)`). When a recipient
/// taps an invite link in Messages / Mail / AirDrop, iOS calls this
/// method on the registered delegate. Wired in via
/// `@UIApplicationDelegateAdaptor` in `NakedPantreeApp`.
///
/// The delegate is instantiated by the system **before** `NakedPantreeApp.init`
/// runs, so we can't take the acceptance service via the initializer.
/// `NakedPantreeApp.init` writes to `Self.shareAcceptance` after
/// constructing the production CloudKit container; preview / test
/// branches leave it `nil`, which means a stray invite during a test
/// run no-ops instead of crashing.
final class NakedPantreeAppDelegate: NSObject, UIApplicationDelegate {
    nonisolated(unsafe) static var shareAcceptance: CloudShareAcceptance?

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
}
