import CloudKit
import CoreData
import Foundation
import NakedPantreeDomain
import NakedPantreePersistence
import SwiftUI

@main
struct NakedPantreeApp: App {
    private let repositories: Repositories
    private let remoteChangeMonitor: RemoteChangeMonitor
    private let accountStatusMonitor: AccountStatusMonitor

    init() {
        if SnapshotFixtures.isSnapshotMode {
            // Bypass Core Data when the snapshot UI tests launch us —
            // they need a deterministic, populated state and never want
            // a stray SQLite file from a previous run leaking through.
            repositories = SnapshotFixtures.makeSeededRepositories()
            remoteChangeMonitor = RemoteChangeMonitor()
            accountStatusMonitor = AccountStatusMonitor()
        } else if ProcessInfo.processInfo.environment["EMPTY_STORE"] == "1" {
            // UI-test escape hatch: empty in-memory repos that exercise
            // the real bootstrap flow without persisting anything to
            // disk. Used by `BootstrapUITests` to regression-test the
            // first-launch race.
            repositories = .makePreview()
            remoteChangeMonitor = RemoteChangeMonitor()
            accountStatusMonitor = AccountStatusMonitor()
        } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            // Unit tests load us via BUNDLE_LOADER, but the simulator has
            // no iCloud account so `cloudKitContainer()` would fail to
            // load. Repository contract tests stand up their own
            // in-memory container — the host repos here are never read.
            repositories = .makePreview()
            remoteChangeMonitor = RemoteChangeMonitor()
            accountStatusMonitor = AccountStatusMonitor()
        } else {
            // Phase 2.1: production stack is CloudKit-mirrored. The shared
            // store is wired but unused until Phase 3 sharing lands.
            let container = CoreDataStack.cloudKitContainer()
            repositories = Repositories(
                household: CoreDataHouseholdRepository(container: container),
                location: CoreDataLocationRepository(container: container),
                item: CoreDataItemRepository(container: container),
                photo: CoreDataItemPhotoRepository(container: container)
            )
            remoteChangeMonitor = RemoteChangeMonitor(
                coordinator: container.persistentStoreCoordinator
            )
            accountStatusMonitor = AccountStatusMonitor(
                container: CKContainer(identifier: CoreDataStack.cloudKitContainerIdentifier)
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.repositories, repositories)
                .environment(\.remoteChangeMonitor, remoteChangeMonitor)
                .environment(\.accountStatusMonitor, accountStatusMonitor)
        }
    }
}
