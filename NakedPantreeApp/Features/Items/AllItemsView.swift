import NakedPantreeDomain
import SwiftUI

/// "All Items" smart-list content column. Lists every item in the
/// household, sorted by name (the repository contract on
/// `ItemRepository.allItems(in:)`). Cross-household search is the
/// sibling sidebar surface — see `SearchResultsView`.
struct AllItemsView: View {
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
                        AllItemsRow(item: item, locationName: locationsByID[item.locationID]?.name)
                            .tag(item.id)
                    }
                }
            }
        }
        .navigationTitle("All Items")
        .task(id: remoteChangeMonitor.changeToken) {
            await load()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView(
            "Pantry's empty",
            systemImage: "tray",
            description: Text("Add a location and a few items to start.")
        )
    }

    private func load() async {
        do {
            let house = try await repositories.household.currentHousehold()
            let locations = try await repositories.location.locations(in: house.id)
            locationsByID = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
            items = try await repositories.item.allItems(in: house.id)
        } catch {
            items = []
        }
        didLoad = true
    }
}

private struct AllItemsRow: View {
    let item: Item
    let locationName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.body)
            HStack(spacing: 8) {
                if let locationName {
                    Text(locationName)
                }
                Text("·")
                Text("\(item.quantity) \(item.unit.displayLabel)")
                if let expiresAt = item.expiresAt {
                    Text("·")
                    Text(expiresAt, style: .date)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    @Previewable @State var selectedItemID: Item.ID?
    NavigationStack {
        AllItemsView(selectedItemID: $selectedItemID)
    }
    .environment(\.repositories, .makePreview())
}
