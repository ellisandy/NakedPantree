import NakedPantreeDomain
import SwiftUI

/// Issue #16: leading-edge swipe action that flips an item's
/// `needsRestocking` flag. The label and icon swap based on the
/// current state — same self-describing pattern Apple Mail uses for
/// "Mark as Read" / "Mark as Unread".
///
/// Used by every items list (per-location `ItemsView`, the smart-list
/// content views, search results, and the `Needs Restocking` smart
/// list itself). Lives in its own file so a copy / icon / color tweak
/// touches one site instead of six.
///
/// `onToggle` is called with the *new* value the caller should
/// persist. Persistence is the caller's responsibility — it has the
/// repository handle and knows how to reload its own list state.
@MainActor
struct RestockSwipeButton: View {
    let item: Item
    let onToggle: @MainActor (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!item.needsRestocking)
        } label: {
            // Icon + text per `DESIGN_GUIDELINES.md` §10 — never color
            // alone. Voice rule: short, useful. "Restock" / "Got it"
            // both fit the one-word swipe-button real estate.
            Label(
                item.needsRestocking ? "Got it" : "Restock",
                systemImage: item.needsRestocking
                    ? "checkmark.circle"
                    : "cart.badge.plus"
            )
        }
        .tint(item.needsRestocking ? .green : .blue)
    }
}
