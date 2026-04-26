import NakedPantreeDomain
import SwiftUI

/// Content column. Lists items for the selected sidebar entry. Phase 1.3
/// is read-only — create / edit / delete arrive in 1.4. Smart Lists are
/// stubbed to an empty state until 1.5 / Phase 6.
struct ItemsView: View {
    let selection: SidebarSelection?
    @Binding var selectedItemID: Item.ID?

    @Environment(\.repositories) private var repositories
    @State private var items: [Item] = []
    @State private var locationName: String?

    var body: some View {
        Group {
            switch selection {
            case .none:
                placeholder("Pick a list or location.")
            case .smartList(let list):
                smartListContent(list)
            case .location(let id):
                locationContent(id: id)
            }
        }
        .navigationTitle(title)
        .navigationDestination(for: Item.ID.self) { itemID in
            ItemDetailView(itemID: itemID)
        }
    }

    private var title: String {
        switch selection {
        case .none: "Naked Pantree"
        case .smartList(let list): list.title
        case .location: locationName ?? "Location"
        }
    }

    @ViewBuilder
    private func smartListContent(_ list: SmartList) -> some View {
        // Smart-list projections (Expiring Soon, Recently Added) come in
        // a later milestone; the All Items aggregate ships with search
        // in 1.5. Until then, empty state is honest.
        ContentUnavailableView(
            list.title,
            systemImage: list.systemImage,
            description: Text("Coming with Smart Lists.")
        )
    }

    @ViewBuilder
    private func locationContent(id: Location.ID) -> some View {
        if items.isEmpty {
            ContentUnavailableView(
                "No items here yet",
                systemImage: "tray",
                description: Text("Items will land here once we wire up adding them.")
            )
            .task(id: id) { await reload(locationID: id) }
        } else {
            List(selection: $selectedItemID) {
                ForEach(items) { item in
                    ItemRow(item: item)
                        .tag(item.id)
                }
            }
            .task(id: id) { await reload(locationID: id) }
        }
    }

    @ViewBuilder
    private func placeholder(_ message: String) -> some View {
        ContentUnavailableView(message, systemImage: "list.bullet")
    }

    private func reload(locationID: Location.ID) async {
        do {
            let location = try await repositories.location.location(id: locationID)
            locationName = location?.name
            items = try await repositories.item.items(in: locationID)
        } catch {
            items = []
        }
    }
}

private struct ItemRow: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.body)
            HStack(spacing: 8) {
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

extension NakedPantreeDomain.Unit {
    /// Short label for inline display alongside a quantity. Wider design
    /// pass — pluralization, locale — lands with the unit picker UI.
    var displayLabel: String {
        switch self {
        case .count: ""
        case .gram: "g"
        case .kilogram: "kg"
        case .ounce: "oz"
        case .pound: "lb"
        case .milliliter: "ml"
        case .liter: "L"
        case .fluidOunce: "fl oz"
        case .package: "pkg"
        case .unknown(let raw): raw
        }
    }
}

#Preview {
    @Previewable @State var selectedItemID: Item.ID?
    let repos = Repositories.makePreview()
    NavigationStack {
        ItemsView(selection: nil, selectedItemID: $selectedItemID)
    }
    .environment(\.repositories, repos)
}
