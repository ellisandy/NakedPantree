import NakedPantreeDomain
import SwiftUI

/// Issue #16: "Needs Restocking" smart-list content column. Cross-
/// household list of items the user has flagged for restocking
/// (`needsRestocking == true`) or that are out of stock
/// (`quantity == 0`). The repository handles the union and sort —
/// see `ItemRepository.needsRestocking(in:)`.
///
/// Same shape as `AllItemsView` / `RecentlyAddedView`: load on the
/// remote-change tick, render rows + leading swipe to flip the flag
/// off (the swipe label flips to "Got it" when the item is already
/// flagged), trailing swipe stays empty here — destructive deletes
/// belong on the per-location list, not on a smart projection.
struct NeedsRestockingView: View {
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
                        NeedsRestockingRow(
                            item: item,
                            locationName: locationsByID[item.locationID]?.name
                        )
                        .tag(item.id)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            RestockSwipeButton(item: item) { newValue in
                                Task { await toggle(item.id, to: newValue) }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.surface)
            }
        }
        .navigationTitle("Needs Restocking")
        .task(id: remoteChangeMonitor.changeToken) {
            await load()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        // Voice rule §10: short, calming, with a brand wink that's
        // *not* about a sync failure (those are off-limits per §9).
        // "Pantry's stocked." was the canonical line in the issue's
        // empty-state suggestion — keeping it.
        ContentUnavailableView(
            "Pantry's stocked.",
            systemImage: "checkmark.seal",
            description: Text("Items you flag for restocking will show up here.")
        )
    }

    private func load() async {
        do {
            let household = try await repositories.household.currentHousehold()
            let locations = try await repositories.location.locations(in: household.id)
            locationsByID = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
            items = try await repositories.item.needsRestocking(in: household.id)
        } catch {
            items = []
        }
        didLoad = true
    }

    private func toggle(_ id: Item.ID, to newValue: Bool) async {
        do {
            try await repositories.item.setNeedsRestocking(
                id: id,
                needsRestocking: newValue
            )
            await load()
        } catch {
            // Soft-fail — reload picks up canonical state on the
            // next remote-change tick. Swallowing matches the same
            // shape as `ItemsView.delete`'s catch arm.
        }
    }
}

private struct NeedsRestockingRow: View {
    let item: Item
    let locationName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(item.name).font(.body)
                // Issue #156: shared expired badge across every list.
                // An expired item that's also flagged for restock is
                // exactly the case the user wants surfaced in red.
                ItemExpiryBadge(expiresAt: item.expiresAt)
            }
            HStack(spacing: 8) {
                if let locationName {
                    Text(locationName)
                    Text("·")
                }
                // The two reasons an item lands here render as a hint
                // the user can scan without opening the detail. Both
                // reasons show when both apply.
                if item.quantity == 0 {
                    Text("Out of stock")
                }
                if item.needsRestocking && item.quantity == 0 {
                    Text("·")
                }
                if item.needsRestocking {
                    Text("Flagged")
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
        NeedsRestockingView(selectedItemID: $selectedItemID)
    }
    .environment(\.repositories, .makePreview())
}
