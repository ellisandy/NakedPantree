import NakedPantreeDomain
import SwiftUI

/// Phase 6.2b: cross-household search results column. Driven by the
/// sidebar `.searchable` field on `RootView`, so this view receives the
/// (trimmed) query as a `let` and re-fetches whenever it changes. Empty
/// queries never reach here — `ItemsView` falls back to the
/// selection-driven view in that case.
///
/// Mirrors `AllItemsView`'s repository-call pattern: 250ms debounce on
/// query change, locations cached per remote-change tick, fetch via
/// `ItemRepository.search(_:in:)`. The repository search is already
/// household-scoped (case-insensitive substring on `Item.name`) so the
/// "cross-household" behavior here is purely about the surface, not the
/// query.
struct SearchResultsView: View {
    let query: String
    @Binding var selectedItemID: Item.ID?

    @Environment(\.repositories) private var repositories
    @Environment(\.remoteChangeMonitor) private var remoteChangeMonitor
    @State private var items: [Item] = []
    @State private var householdID: Household.ID?
    @State private var locationsByID: [Location.ID: Location] = [:]
    @State private var didSearch = false

    var body: some View {
        Group {
            if !didSearch {
                ProgressView()
            } else if items.isEmpty {
                emptyState
            } else {
                List(selection: $selectedItemID) {
                    ForEach(items) { item in
                        SearchResultsRow(
                            item: item,
                            locationName: locationsByID[item.locationID]?.name
                        )
                        .tag(item.id)
                    }
                }
            }
        }
        .task(id: remoteChangeMonitor.changeToken) {
            await loadShell()
        }
        .task(id: query) {
            do {
                try await Task.sleep(for: .milliseconds(250))
                await loadResults()
            } catch {
                // Cancelled by the next keystroke — that task takes over.
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView(
            "Nothing by that name yet.",
            systemImage: "magnifyingglass",
            description: Text("Try a shorter or different search.")
        )
    }

    private func loadShell() async {
        do {
            let house = try await repositories.household.currentHousehold()
            householdID = house.id
            let locations = try await repositories.location.locations(in: house.id)
            locationsByID = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
        } catch {
            return
        }
        await loadResults()
    }

    private func loadResults() async {
        guard let house = householdID else { return }
        do {
            items = try await repositories.item.search(query, in: house)
        } catch {
            items = []
        }
        didSearch = true
    }
}

private struct SearchResultsRow: View {
    let item: Item
    let locationName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.body)
            HStack(spacing: 8) {
                if let locationName {
                    Text(locationName)
                    Text("·")
                }
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
        SearchResultsView(query: "tom", selectedItemID: $selectedItemID)
    }
    .environment(\.repositories, .makePreview())
}
