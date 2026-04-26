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
