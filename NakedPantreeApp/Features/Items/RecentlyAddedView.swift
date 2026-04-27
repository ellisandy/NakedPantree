import NakedPantreeDomain
import SwiftUI

/// Sorts a household's items by `createdAt` descending — most-recent
/// adds first. Pure free function so tests can pin the input order
/// and verify the sort without a Core Data round-trip.
///
/// No time-window or count cap. The smart list is "items by recency,"
/// not "items added in the last N days" — a household with 50 items
/// total still scrolls cheaply, and capping is a polish decision
/// better made when real-world household sizes are visible. Same
/// shape as `itemsExpiringSoon` (no cutoff there either) — keep the
/// two consistent.
func itemsRecentlyAdded(_ items: [Item]) -> [Item] {
    items.sorted { $0.createdAt > $1.createdAt }
}

/// "Recently Added" smart-list content column. Cross-location list of
/// every item in the household, sorted with the most-recently-added
/// first. Useful for "what did I just put in" and "did my partner add
/// anything since I last looked."
struct RecentlyAddedView: View {
    @Binding var selectedItemID: Item.ID?

    @Environment(\.repositories) private var repositories
    @Environment(\.remoteChangeMonitor) private var remoteChangeMonitor
    @State private var items: [Item] = []
    @State private var locationsByID: [Location.ID: Location] = [:]
    @State private var didLoad = false

    var body: some View {
        Group {
            if !didLoad {
                ProgressView()
            } else if items.isEmpty {
                emptyState
            } else {
                List(selection: $selectedItemID) {
                    ForEach(items) { item in
                        RecentlyAddedRow(
                            item: item,
                            locationName: locationsByID[item.locationID]?.name
                        )
                        .tag(item.id)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.surface)
            }
        }
        .navigationTitle("Recently Added")
        .task(id: remoteChangeMonitor.changeToken) {
            await load()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView(
            "Nothing added yet",
            systemImage: "sparkles",
            description: Text("Items you add will show up here.")
        )
    }

    private func load() async {
        do {
            let household = try await repositories.household.currentHousehold()
            let locations = try await repositories.location.locations(in: household.id)
            locationsByID = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
            let allItems = try await repositories.item.allItems(in: household.id)
            items = itemsRecentlyAdded(allItems)
        } catch {
            items = []
        }
        didLoad = true
    }
}

private struct RecentlyAddedRow: View {
    let item: Item
    let locationName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name).font(.body)
            HStack(spacing: 8) {
                if let locationName {
                    Text(locationName)
                    Text("·")
                }
                Text("\(item.quantity) \(item.unit.displayLabel)")
                Text("·")
                Text(item.createdAt, style: .relative)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    @Previewable @State var selectedItemID: Item.ID?
    NavigationStack {
        RecentlyAddedView(selectedItemID: $selectedItemID)
    }
    .environment(\.repositories, .makePreview())
}
