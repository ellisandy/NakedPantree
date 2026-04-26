import NakedPantreeDomain
import SwiftUI

/// Detail column. Read-only in Phase 1.3 — editing arrives in 1.4.
struct ItemDetailView: View {
    let itemID: Item.ID?

    @Environment(\.repositories) private var repositories
    @State private var item: Item?

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
        .task(id: itemID) {
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
