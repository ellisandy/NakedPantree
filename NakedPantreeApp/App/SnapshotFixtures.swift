import Foundation
import NakedPantreeDomain

/// Seeded data + initial UI state the app loads when launched with the
/// snapshot-mode environment flag. Used by `SnapshotsUITests` to produce
/// App Store / TestFlight screenshots from a deterministic state. See
/// [issue #12](https://github.com/ellisandy/NakedPantree/issues/12).
enum SnapshotFixtures {
    enum EnvKey {
        /// Set to `"1"` to enable snapshot mode. The app skips Core Data
        /// and uses the seeded in-memory bundle instead.
        static let mode = "SNAPSHOT_MODE"
        /// `smartList:<rawValue>` or `location:<name>`. Optional; default
        /// is the same `SidebarSelection.smartList(.allItems)` the app
        /// uses on a first cold launch.
        static let sidebar = "SNAPSHOT_SIDEBAR"
        /// `<item-name>`. Optional. When set, the seeded item with that
        /// exact name is selected so the detail column renders for the
        /// screenshot.
        static let item = "SNAPSHOT_ITEM"
    }

    static var isSnapshotMode: Bool {
        ProcessInfo.processInfo.environment[EnvKey.mode] == "1"
    }

    // swiftlint:disable function_body_length
    /// Build an in-memory `Repositories` bundle pre-populated with a
    /// canonical "show the app off" inventory. Each call returns a
    /// fresh bundle. Body is mostly fixture data — splitting it just
    /// moves lines around without making it more readable, so the
    /// function-length rule is suspended over this declaration.
    static func makeSeededRepositories() -> Repositories {
        let now = Date()
        let dayInSeconds: TimeInterval = 60 * 60 * 24
        func date(_ daysFromNow: Int) -> Date {
            now.addingTimeInterval(TimeInterval(daysFromNow) * dayInSeconds)
        }

        let household = Household(name: "My Pantry", createdAt: date(-30))

        let kitchen = Location(
            householdID: household.id,
            name: "Kitchen Pantry",
            kind: .pantry,
            sortOrder: 0,
            createdAt: date(-30)
        )
        let fridge = Location(
            householdID: household.id,
            name: "Fridge",
            kind: .fridge,
            sortOrder: 1,
            createdAt: date(-29)
        )
        let freezer = Location(
            householdID: household.id,
            name: "Garage Freezer",
            kind: .freezer,
            sortOrder: 2,
            createdAt: date(-28)
        )

        let items: [Item] = [
            Item(
                locationID: kitchen.id,
                name: "Tomato paste",
                quantity: 4,
                unit: .count,
                expiresAt: date(180),
                createdAt: date(-10),
                updatedAt: date(-10)
            ),
            Item(
                locationID: kitchen.id,
                name: "Bucatini",
                quantity: 2,
                unit: .package,
                createdAt: date(-7),
                updatedAt: date(-7)
            ),
            Item(
                locationID: kitchen.id,
                name: "Olive oil",
                quantity: 750,
                unit: .milliliter,
                createdAt: date(-12),
                updatedAt: date(-12)
            ),
            Item(
                locationID: kitchen.id,
                name: "Honey",
                quantity: 1,
                unit: .package,
                createdAt: date(-90),
                updatedAt: date(-90)
            ),
            Item(
                locationID: fridge.id,
                name: "Whole milk",
                quantity: 1,
                unit: .liter,
                expiresAt: date(4),
                notes: "Check the back of the fridge for the older one.",
                createdAt: date(-3),
                updatedAt: date(-3)
            ),
            Item(
                locationID: fridge.id,
                name: "Greek yogurt",
                quantity: 6,
                unit: .count,
                expiresAt: date(9),
                createdAt: date(-2),
                updatedAt: date(-2)
            ),
            Item(
                locationID: fridge.id,
                name: "Eggs",
                quantity: 12,
                unit: .count,
                expiresAt: date(21),
                createdAt: date(-5),
                updatedAt: date(-5)
            ),
            Item(
                locationID: fridge.id,
                name: "Sharp cheddar",
                quantity: 1,
                unit: .package,
                expiresAt: date(45),
                createdAt: date(-14),
                updatedAt: date(-14)
            ),
            Item(
                locationID: freezer.id,
                name: "Chicken thighs",
                quantity: 2,
                unit: .pound,
                createdAt: date(-21),
                updatedAt: date(-21)
            ),
            Item(
                locationID: freezer.id,
                name: "Vanilla ice cream",
                quantity: 1,
                unit: .liter,
                createdAt: date(-6),
                updatedAt: date(-6)
            ),
            Item(
                locationID: freezer.id,
                name: "Sourdough loaves",
                quantity: 3,
                unit: .count,
                createdAt: date(-1),
                updatedAt: date(-1)
            ),
        ]

        let locationRepo = InMemoryLocationRepository(initial: [kitchen, fridge, freezer])
        let itemRepo = InMemoryItemRepository(
            initial: items,
            locationLookup: { [weak locationRepo] id in
                try await locationRepo?.location(id: id)
            }
        )

        return Repositories(
            household: InMemoryHouseholdRepository(initial: household),
            location: locationRepo,
            item: itemRepo,
            photo: InMemoryItemPhotoRepository()
        )
    }
    // swiftlint:enable function_body_length

    /// Resolve `SNAPSHOT_SIDEBAR` against the seeded repositories. Looks
    /// up locations by exact `name` so the env value can be human-typed.
    /// Returns `nil` when the env var isn't set or is malformed —
    /// `RootView` falls back to its default selection in that case.
    static func resolveInitialSidebar(in repositories: Repositories) async -> SidebarSelection? {
        guard let raw = ProcessInfo.processInfo.environment[EnvKey.sidebar] else {
            return nil
        }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts.first {
        case "smartList":
            guard parts.count == 2, let list = SmartList(rawValue: parts[1]) else { return nil }
            return .smartList(list)
        case "location":
            guard parts.count == 2 else { return nil }
            do {
                let house = try await repositories.household.currentHousehold()
                let locations = try await repositories.location.locations(in: house.id)
                guard let match = locations.first(where: { $0.name == parts[1] }) else {
                    return nil
                }
                return .location(match.id)
            } catch {
                return nil
            }
        default:
            return nil
        }
    }

    /// Resolve `SNAPSHOT_ITEM` to the seeded item's id, by name. Same
    /// motivation as `resolveInitialSidebar` — exact-name match keeps
    /// the env var human-typed.
    static func resolveInitialItem(in repositories: Repositories) async -> Item.ID? {
        guard let name = ProcessInfo.processInfo.environment[EnvKey.item] else {
            return nil
        }
        do {
            let house = try await repositories.household.currentHousehold()
            let all = try await repositories.item.allItems(in: house.id)
            return all.first(where: { $0.name == name })?.id
        } catch {
            return nil
        }
    }
}
