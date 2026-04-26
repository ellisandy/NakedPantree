import NakedPantreeDomain
import SwiftUI

/// Bundle the four repository protocols the UI layer reads from. Lives on
/// the SwiftUI environment so any view can pull just the ones it needs
/// without prop-drilling.
///
/// Default value uses the in-memory implementations from
/// `NakedPantreeDomain` so `#Preview` blocks render without setup. The
/// real `NakedPantreeApp` overrides the environment with Core Data-backed
/// repos at app launch.
struct Repositories: Sendable {
    let household: any HouseholdRepository
    let location: any LocationRepository
    let item: any ItemRepository
    let photo: any ItemPhotoRepository

    /// Each call returns a fresh in-memory bundle — `#Preview` blocks that
    /// seed fixture data don't bleed into each other.
    static func makePreview() -> Repositories {
        let location = InMemoryLocationRepository()
        return Repositories(
            household: InMemoryHouseholdRepository(),
            location: location,
            item: InMemoryItemRepository(
                locationLookup: { [weak location] id in
                    try await location?.location(id: id)
                }
            ),
            photo: InMemoryItemPhotoRepository()
        )
    }
}

extension EnvironmentValues {
    @Entry var repositories: Repositories = .makePreview()
}
