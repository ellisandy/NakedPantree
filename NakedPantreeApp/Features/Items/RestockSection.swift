import NakedPantreeDomain
import SwiftUI

/// Issue #16: detail-view toggle for the "Needs Restocking" flag.
/// Carved out of `ItemDetailView` so the parent body stays under
/// SwiftLint's `type_body_length` ceiling, and so the persistence
/// path can fail-soft without dragging detail-view error UI into
/// the picture.
///
/// The toggle binds against a local `@State` mirror of `item.needsRestocking`
/// so the UI flips immediately on tap. The repository call runs in a
/// `Task` and persists via `setNeedsRestocking` — the partial-update
/// path. If the write fails (transient store hiccup) the local
/// optimistic value sticks; the next remote-change tick replaces
/// `item` and re-seeds the mirror, so canonical state always wins
/// eventually. This shape mirrors how `QuantityStepperControl` debounces
/// + reloads.
struct RestockSection: View {
    let item: Item
    @Environment(\.repositories) private var repositories
    @State private var optimistic: Bool?

    var body: some View {
        Section("Restock") {
            Toggle(
                "Needs restocking",
                isOn: Binding(
                    get: { optimistic ?? item.needsRestocking },
                    set: { newValue in
                        optimistic = newValue
                        Task { await persist(newValue) }
                    }
                )
            )
            .accessibilityIdentifier("itemDetail.needsRestocking")
        }
    }

    private func persist(_ newValue: Bool) async {
        do {
            try await repositories.item.setNeedsRestocking(
                id: item.id,
                needsRestocking: newValue
            )
        } catch {
            // Soft-fail — next remote-change tick reloads canonical
            // state. Same shape as `ItemsView.delete`'s catch arm.
        }
    }
}
