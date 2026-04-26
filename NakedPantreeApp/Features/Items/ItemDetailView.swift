import NakedPantreeDomain
import SwiftUI

/// Detail column. Read-only by default; tap Edit to open the item form.
struct ItemDetailView: View {
    let itemID: Item.ID?

    @Environment(\.repositories) private var repositories
    @Environment(\.remoteChangeMonitor) private var remoteChangeMonitor
    @State private var item: Item?
    @State private var formMode: ItemFormView.Mode?

    var body: some View {
        Group {
            if let item {
                detail(for: item)
            } else if itemID == nil {
                ContentUnavailableView(
                    "Pick an item",
                    systemImage: "sidebar.right",
                    description: Text("Item details will show here.")
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle(item?.name ?? "")
        .toolbar {
            if let item {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        formMode = .edit(item)
                    }
                }
            }
        }
        .sheet(item: $formMode) { mode in
            ItemFormView(mode: mode) {
                Task { await reload() }
            }
        }
        .task(id: ReloadKey(scope: itemID, token: remoteChangeMonitor.changeToken)) {
            await reload()
        }
    }

    @ViewBuilder
    private func detail(for item: Item) -> some View {
        Form {
            Section("Quantity") {
                Text("\(item.quantity) \(item.unit.displayLabel)")
            }

            if let expiresAt = item.expiresAt {
                Section("Expires") {
                    Text(expiresAt, style: .date)
                }
            }

            if let notes = item.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }
        }
    }

    private func reload() async {
        guard let itemID else {
            item = nil
            return
        }
        do {
            item = try await repositories.item.item(id: itemID)
        } catch {
            item = nil
        }
    }
}

#Preview("Empty") {
    NavigationStack {
        ItemDetailView(itemID: nil)
    }
    .environment(\.repositories, .makePreview())
}
