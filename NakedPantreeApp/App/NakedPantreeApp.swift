import CloudKit
import CoreData
import Foundation
import NakedPantreeDomain
import NakedPantreePersistence
import SwiftUI

@main
struct NakedPantreeApp: App {
    @UIApplicationDelegateAdaptor(NakedPantreeAppDelegate.self) private var appDelegate

    private let repositories: Repositories
    private let remoteChangeMonitor: RemoteChangeMonitor
    private let accountStatusMonitor: AccountStatusMonitor
    private let householdSharing: CloudHouseholdSharingService?

    init() {
        if SnapshotFixtures.isSnapshotMode {
            // Bypass Core Data when the snapshot UI tests launch us —
            // they need a deterministic, populated state and never want
            // a stray SQLite file from a previous run leaking through.
            repositories = SnapshotFixtures.makeSeededRepositories()
            remoteChangeMonitor = RemoteChangeMonitor()
            accountStatusMonitor = AccountStatusMonitor()
            householdSharing = nil
        } else if ProcessInfo.processInfo.environment["EMPTY_STORE"] == "1" {
            // UI-test escape hatch: empty in-memory repos that exercise
            // the real bootstrap flow without persisting anything to
            // disk. Used by `BootstrapUITests` to regression-test the
            // first-launch race.
            repositories = .makePreview()
            remoteChangeMonitor = RemoteChangeMonitor()
            accountStatusMonitor = AccountStatusMonitor()
            householdSharing = nil
        } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            // Unit tests load us via BUNDLE_LOADER, but the simulator has
            // no iCloud account so `cloudKitContainer()` would fail to
            // load. Repository contract tests stand up their own
            // in-memory container — the host repos here are never read.
            repositories = .makePreview()
            remoteChangeMonitor = RemoteChangeMonitor()
            accountStatusMonitor = AccountStatusMonitor()
            householdSharing = nil
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
            remoteChangeMonitor = RemoteChangeMonitor(
                coordinator: container.persistentStoreCoordinator
            )
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
            NakedPantreeAppDelegate.shareAcceptance = CloudShareAcceptance(container: container)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.repositories, repositories)
                .environment(\.remoteChangeMonitor, remoteChangeMonitor)
                .environment(\.accountStatusMonitor, accountStatusMonitor)
                .environment(\.householdSharing, householdSharing)
        }
    }
}
