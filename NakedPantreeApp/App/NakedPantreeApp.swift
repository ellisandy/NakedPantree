import Foundation
import NakedPantreeDomain
import NakedPantreePersistence
import SwiftUI

@main
struct NakedPantreeApp: App {
    private let repositories: Repositories

    init() {
        if SnapshotFixtures.isSnapshotMode {
            // Bypass Core Data when the snapshot UI tests launch us —
            // they need a deterministic, populated state and never want
            // a stray SQLite file from a previous run leaking through.
            repositories = SnapshotFixtures.makeSeededRepositories()
        } else if ProcessInfo.processInfo.environment["EMPTY_STORE"] == "1" {
            // UI-test escape hatch: empty in-memory repos that exercise
            // the real bootstrap flow without persisting anything to
            // disk. Used by `BootstrapUITests` to regression-test the
            // first-launch race.
            repositories = .makePreview()
        } else {
            let container = CoreDataStack.persistentContainer()
            repositories = Repositories(
                household: CoreDataHouseholdRepository(container: container),
                location: CoreDataLocationRepository(container: container),
                item: CoreDataItemRepository(container: container),
                photo: CoreDataItemPhotoRepository(container: container)
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.repositories, repositories)
        }
    }
}
