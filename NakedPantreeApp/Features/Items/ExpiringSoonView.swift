import NakedPantreeDomain
import SwiftUI

/// Filters a household's items down to the ones with a set expiry,
/// sorted ascending so already-expired items lead and the next-up
/// items follow. Pure free function so tests can pin `now` and
/// verify the sort without a Core Data round-trip — the view layer
/// just hands its current `[Item]` straight in.
///
/// Items with `expiresAt == nil` are dropped — the smart list is an
/// "act on this" surface; an item with no expiry isn't actionable
/// in this context.
func itemsExpiringSoon(_ items: [Item]) -> [Item] {
    items
        .filter { $0.expiresAt != nil }
        // Force-unwrap is safe: filter above guarantees non-nil. The
        // ordering puts past-expiry first because past dates are
        // numerically smaller — that's the desired UX (most-urgent
        // items lead the list).
        .sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
}

/// "Expiring Soon" smart-list content column. Cross-location list of
/// every item in the household that has an `expiresAt`, sorted with
/// already-expired items leading and the next-to-expire items
/// following. Per `ARCHITECTURE.md` §8 this is the surface a
/// notification-tap deep link routes the user to when the underlying
/// item has been deleted.
struct ExpiringSoonView: View {
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
                        ExpiringSoonRow(
                            item: item,
                            locationName: locationsByID[item.locationID]?.name
                        )
                        .tag(item.id)
                    }
                }
            }
        }
        .navigationTitle("Expiring Soon")
        .task(id: remoteChangeMonitor.changeToken) {
            await load()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView(
            "Nothing's expiring",
            systemImage: "clock.badge.checkmark",
            description: Text("Items with an expiry date will show up here.")
        )
    }

    private func load() async {
        do {
            let household = try await repositories.household.currentHousehold()
            let locations = try await repositories.location.locations(in: household.id)
            locationsByID = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
            let allItems = try await repositories.item.allItems(in: household.id)
            items = itemsExpiringSoon(allItems)
        } catch {
            items = []
        }
        didLoad = true
    }
}

private struct ExpiringSoonRow: View {
    let item: Item
    let locationName: String?

    @Environment(\.calendar) private var calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(item.name).font(.body)
                if isExpired {
                    expiredBadge
                }
            }
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

    private var isExpired: Bool {
        guard let expiresAt = item.expiresAt else { return false }
        return expiresAt < Date()
    }

    /// Icon + text — never color alone, per `DESIGN_GUIDELINES.md` §6
    /// accessibility rule. The badge stays compact so the row layout
    /// reads at a glance.
    @ViewBuilder
    private var expiredBadge: some View {
        Label("Expired", systemImage: "exclamationmark.triangle.fill")
            .labelStyle(.titleAndIcon)
            .font(.caption.bold())
            .foregroundStyle(.red)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.red.opacity(0.12), in: Capsule())
    }
}

#Preview {
    @Previewable @State var selectedItemID: Item.ID?
    NavigationStack {
        ExpiringSoonView(selectedItemID: $selectedItemID)
    }
    .environment(\.repositories, .makePreview())
}
