import NakedPantreeDomain
import SwiftUI

/// "All Items" smart-list content column. Lists every item in the
/// household, with `.searchable` driving a household-scoped name match
/// through `ItemRepository.search(_:in:)`. Empty / whitespace queries
/// fall back to `allItems(in:)`.
struct AllItemsView: View {
    @Binding var selectedItemID: Item.ID?

    @Environment(\.repositories) private var repositories
    @State private var query: String = ""
    @State private var items: [Item] = []
    @State private var householdID: Household.ID?
    @State private var locationsByID: [Location.ID: Location] = [:]

    var body: some View {
        Group {
            if items.isEmpty {
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
        .searchable(text: $query, prompt: "Search items")
        .task { await reload() }
        .onChange(of: query) { _, _ in
            Task { await reload() }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            ContentUnavailableView(
                "Pantry's empty",
                systemImage: "tray",
                description: Text("Add a location and a few items to start.")
            )
        } else {
            ContentUnavailableView.search(text: trimmed)
        }
    }

    private func reload() async {
        do {
            let house = try await repositories.household.currentHousehold()
            householdID = house.id
            let locations = try await repositories.location.locations(in: house.id)
            locationsByID = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })

            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                items = try await repositories.item.allItems(in: house.id)
            } else {
                items = try await repositories.item.search(trimmed, in: house.id)
            }
        } catch {
            items = []
        }
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
