import NakedPantreeDomain
import NakedPantreePersistence
import SwiftUI

@main
struct NakedPantreeApp: App {
    private let repositories: Repositories

    init() {
        let container = CoreDataStack.persistentContainer()
        repositories = Repositories(
            household: CoreDataHouseholdRepository(container: container),
            location: CoreDataLocationRepository(container: container),
            item: CoreDataItemRepository(container: container),
            photo: CoreDataItemPhotoRepository(container: container)
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.repositories, repositories)
        }
    }
}
