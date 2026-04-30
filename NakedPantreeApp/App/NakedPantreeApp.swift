import CloudKit
import CoreData
import Foundation
import NakedPantreeDomain
import NakedPantreePersistence
import SwiftUI
import UserNotifications

/// App-level entry point.
///
/// **Issue #106:** the previous version did all dependency wiring
/// synchronously inside `init()` and called `fatalError` if
/// `CoreDataStack.cloudKitContainer()` threw — crashing every launch
/// for any user who hit a corrupt SQLite or a bad migration. The
/// wiring now lives in `AppLauncher`, which catches the throw and
/// renders `DataRecoveryView` instead. SwiftUI's body switches on
/// `launcher.state`.
@main
struct NakedPantreeApp: App {
    @UIApplicationDelegateAdaptor(NakedPantreeAppDelegate.self) private var appDelegate
    @State private var launcher = AppLauncher()

    var body: some Scene {
        WindowGroup {
            switch launcher.state {
            case .loading:
                // The launcher transitions out of `.loading`
                // synchronously inside `init`, so this branch only
                // shows during the brief window between a `retry()` /
                // `resetAndRetry()` call and the next `attemptLoad()`
                // completing — single render frame in practice. Reuse
                // `LaunchView` so the user sees the same brand splash
                // they saw at cold-start.
                LaunchView()
            case .ready(let dependencies):
                RootView()
                    .environment(\.repositories, dependencies.repositories)
                    .environment(\.remoteChangeMonitor, dependencies.remoteChangeMonitor)
                    .environment(\.accountStatusMonitor, dependencies.accountStatusMonitor)
                    .environment(\.householdSharing, dependencies.householdSharing)
                    .environment(\.notificationScheduler, dependencies.notificationScheduler)
                    .environment(\.notificationRouting, dependencies.notificationRouting)
                    .environment(\.notificationSettings, dependencies.notificationSettings)
            case .failed(let failure):
                DataRecoveryView(
                    errorDescription: failure.errorDescription,
                    accountStatusMonitor: failure.accountStatusMonitor,
                    onTryAgain: { launcher.retry() },
                    onResetAndRetry: { launcher.resetAndRetry() }
                )
            }
        }
    }
}
