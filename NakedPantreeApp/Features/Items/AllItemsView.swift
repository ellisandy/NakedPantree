import NakedPantreeDomain
import SwiftUI

/// "All Items" smart-list content column. Lists every item in the
/// household, with `.searchable` driving a household-scoped name match
/// through `ItemRepository.search(_:in:)`. Empty / whitespace queries
/// fall back to `allItems(in:)`.
struct AllItemsView: View {
    @Binding var selectedItemID: Item.ID?

    @Environment(\.repositories) private var repositories
    @Environment(\.remoteChangeMonitor) private var remoteChangeMonitor
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
        // Shell (household + locations) only refetches when CloudKit
        // imports a remote change — typing in the search bar shouldn't
        // re-hit those rows.
        .task(id: remoteChangeMonitor.changeToken) {
            await loadShell()
        }
        // Items refetch on query change, debounced so a flurry of
        // keystrokes resolves into one Core Data hop instead of one
        // per character. `.task(id:)` cancels the previous task when
        // `query` changes, and `Task.sleep` throws on cancel — so only
        // the last keystroke after a 250ms pause actually fetches.
        .task(id: query) {
            do {
                if !query.isEmpty {
                    try await Task.sleep(for: .milliseconds(250))
                }
                await loadItems()
            } catch {
                // Cancelled — the next .task takes over.
            }
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

    /// Fetch the household + locations once on appear and on each remote
    /// change. Triggers an items load at the end so the initial render
    /// shows data without waiting for the query-task to fire.
    private func loadShell() async {
        do {
            let house = try await repositories.household.currentHousehold()
            householdID = house.id
            let locations = try await repositories.location.locations(in: house.id)
            locationsByID = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
        } catch {
            return
        }
        await loadItems()
    }

    /// Fetch items for the current `query`. Bails if the shell hasn't
    /// resolved a household yet — `loadShell()` calls back into this
    /// once it has, so the empty state never sticks.
    private func loadItems() async {
        guard let house = householdID else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                items = try await repositories.item.allItems(in: house)
            } else {
                items = try await repositories.item.search(trimmed, in: house)
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
