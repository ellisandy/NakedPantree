import NakedPantreeDomain
import SwiftUI

/// Content column. Lists items for the selected sidebar entry, with
/// `+` to create and swipe-to-delete. Smart Lists are stubbed to an
/// empty state until 1.5 / Phase 6.
struct ItemsView: View {
    let selection: SidebarSelection?
    @Binding var selectedItemID: Item.ID?

    @Environment(\.repositories) private var repositories
    @Environment(\.remoteChangeMonitor) private var remoteChangeMonitor
    @Environment(\.notificationScheduler) private var notificationScheduler
    @State private var items: [Item] = []
    @State private var locationName: String?
    @State private var formMode: ItemFormView.Mode?
    @State private var pendingDelete: Item?

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
        .toolbar {
            if case .location(let locationID) = selection {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        formMode = .create(locationID: locationID)
                    } label: {
                        Label("New Item", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(item: $formMode) { mode in
            ItemFormView(mode: mode) {
                if case .location(let id) = selection {
                    Task { await reload(locationID: id) }
                }
            }
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: deleteDialogBinding,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { item in
            Button("Delete", role: .destructive) {
                Task { await delete(item) }
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        }
    }

    private var title: String {
        switch selection {
        case .none: "Naked Pantree"
        case .smartList(let list): list.title
        case .location: locationName ?? "Location"
        }
    }

    private var deleteConfirmationTitle: String {
        if let pendingDelete {
            return "Delete \(pendingDelete.name)?"
        }
        return ""
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { newValue in
                if !newValue { pendingDelete = nil }
            }
        )
    }

    @ViewBuilder
    private func smartListContent(_ list: SmartList) -> some View {
        switch list {
        case .allItems:
            AllItemsView(selectedItemID: $selectedItemID)
        case .expiringSoon:
            ExpiringSoonView(selectedItemID: $selectedItemID)
        case .recentlyAdded:
            RecentlyAddedView(selectedItemID: $selectedItemID)
        }
    }

    @ViewBuilder
    private func locationContent(id: Location.ID) -> some View {
        if items.isEmpty {
            ContentUnavailableView(
                "No items here yet",
                systemImage: "tray",
                description: Text("Tap + to add the first one.")
            )
            .task(
                id: ReloadKey(scope: id, token: remoteChangeMonitor.changeToken)
            ) {
                await reload(locationID: id)
            }
        } else {
            List(selection: $selectedItemID) {
                ForEach(items) { item in
                    ItemRow(item: item)
                        .tag(item.id)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = item
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                formMode = .edit(item)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.indigo)
                        }
                }
            }
            .task(
                id: ReloadKey(scope: id, token: remoteChangeMonitor.changeToken)
            ) {
                await reload(locationID: id)
            }
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

    private func delete(_ item: Item) async {
        pendingDelete = nil
        if selectedItemID == item.id { selectedItemID = nil }
        do {
            try await repositories.item.delete(id: item.id)
            // Phase 4.1: cancel any pending expiry notification for
            // this item so a deleted bottle of milk doesn't ping
            // someone three days from now. Safe even when no request
            // was scheduled — `removePendingNotificationRequests` is a
            // no-op for unknown ids.
            notificationScheduler.cancel(itemID: item.id)
            if case .location(let id) = selection {
                await reload(locationID: id)
            }
        } catch {
            // Soft fail — reload to drop stale optimistic state.
            if case .location(let id) = selection {
                await reload(locationID: id)
            }
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
