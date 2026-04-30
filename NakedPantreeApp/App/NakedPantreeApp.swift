import CloudKit
import CoreData
import Foundation
import NakedPantreeDomain
import NakedPantreePersistence
import SwiftUI
import UserNotifications

@main
struct NakedPantreeApp: App {
    @UIApplicationDelegateAdaptor(NakedPantreeAppDelegate.self) private var appDelegate

    private let repositories: Repositories
    private let remoteChangeMonitor: RemoteChangeMonitor
    private let accountStatusMonitor: AccountStatusMonitor
    private let householdSharing: (any HouseholdSharingService)?
    private let notificationScheduler: NotificationScheduler
    private let notificationRouting: NotificationRoutingService
    private let notificationSettings: NotificationSettings

    init() {
        // Phase 4.2: a single routing service across all branches —
        // preview / snapshot / test surfaces never get tap callbacks
        // (no scheduled notifications) but the environment value still
        // needs to resolve, and a fresh service is cheap.
        let routing = NotificationRoutingService()
        notificationRouting = routing

        if SnapshotFixtures.isSnapshotMode {
            // Bypass Core Data when the snapshot UI tests launch us —
            // they need a deterministic, populated state and never want
            // a stray SQLite file from a previous run leaking through.
            repositories = SnapshotFixtures.makeSeededRepositories()
            remoteChangeMonitor = RemoteChangeMonitor()
            accountStatusMonitor = AccountStatusMonitor()
            householdSharing = nil
            notificationScheduler = NotificationScheduler()
            notificationSettings = NotificationSettings()
        } else if ProcessInfo.processInfo.environment["EMPTY_STORE"] == "1" {
            // UI-test escape hatch: empty in-memory repos that exercise
            // the real bootstrap flow without persisting anything to
            // disk. Used by `BootstrapUITests` to regression-test the
            // first-launch race.
            repositories = .makePreview()
            remoteChangeMonitor = RemoteChangeMonitor()
            accountStatusMonitor = AccountStatusMonitor()
            // `STUB_SHARING=1` swaps in `StubHouseholdSharingService`
            // so `SharingUITests` can drive the Settings → Share
            // Household path on CI without an iCloud account. Without
            // the stub, `householdSharing` stays nil and the Share
            // Household button hides — same behavior as
            // `BootstrapUITests` and snapshot mode.
            if ProcessInfo.processInfo.environment["STUB_SHARING"] == "1" {
                householdSharing = StubHouseholdSharingService()
            } else {
                householdSharing = nil
            }
            notificationScheduler = NotificationScheduler()
            notificationSettings = NotificationSettings()
        } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            // Unit tests load us via BUNDLE_LOADER, but the simulator has
            // no iCloud account so `cloudKitContainer()` would fail to
            // load. Repository contract tests stand up their own
            // in-memory container — the host repos here are never read.
            repositories = .makePreview()
            remoteChangeMonitor = RemoteChangeMonitor()
            accountStatusMonitor = AccountStatusMonitor()
            householdSharing = nil
            notificationScheduler = NotificationScheduler()
            notificationSettings = NotificationSettings()
        } else {
            // Phase 2.1: production stack is CloudKit-mirrored. Phase 3
            // adds the sharing service against the same container.
            let container = CoreDataStack.cloudKitContainer()
            let cloudKitContainer = CKContainer(
                identifier: CoreDataStack.cloudKitContainerIdentifier
            )
            repositories = Repositories(
                household: CoreDataHouseholdRepository(container: container),
                location: CoreDataLocationRepository(container: container),
                item: CoreDataItemRepository(container: container),
                photo: CoreDataItemPhotoRepository(container: container)
            )
            remoteChangeMonitor = RemoteChangeMonitor(container: container)
            accountStatusMonitor = AccountStatusMonitor(container: cloudKitContainer)
            householdSharing = CloudHouseholdSharingService(
                container: container,
                cloudKitContainer: cloudKitContainer
            )
            // Phase 3.2: hand the share-acceptance service to the
            // delegate so `application(_:userDidAcceptCloudKitShareWith:)`
            // can import shared records when a recipient taps an
            // invite. The delegate is instantiated by the system before
            // this init runs, so a static var is the simplest seam.
            NakedPantreeAppDelegate.wireShareAcceptance(
                CloudShareAcceptance(container: container)
            )
            // Phase 9.3: persisted reminder time, constructed before
            // the scheduler so it can read `settings.hourOfDay` /
            // `.minute` when scheduling and when bundling same-day
            // expiries (Phase 9.4 integration).
            notificationSettings = NotificationSettings(defaults: .standard)
            notificationScheduler = NotificationScheduler(
                center: .current(),
                settings: notificationSettings
            )
        }
        // Phase 4.2: the delegate routes notification taps into this
        // service. Same static-var pattern as `shareAcceptance` —
        // delegate construction precedes app init, so the seam is a
        // post-hoc handoff.
        NakedPantreeAppDelegate.wireNotificationRouting(routing)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.repositories, repositories)
                .environment(\.remoteChangeMonitor, remoteChangeMonitor)
                .environment(\.accountStatusMonitor, accountStatusMonitor)
                .environment(\.householdSharing, householdSharing)
                .environment(\.notificationScheduler, notificationScheduler)
                .environment(\.notificationRouting, notificationRouting)
                .environment(\.notificationSettings, notificationSettings)
        }
    }
}
