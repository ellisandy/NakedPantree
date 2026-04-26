import NakedPantreeDomain
import SwiftUI

/// Three-column `NavigationSplitView` per `ARCHITECTURE.md` §7. Sidebar
/// selection drives what the content column shows; content selection
/// drives what the detail column shows.
struct RootView: View {
    @State private var sidebarSelection: SidebarSelection? = .smartList(.allItems)
    @State private var selectedItemID: Item.ID?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
        } content: {
            ItemsView(
                selection: sidebarSelection,
                selectedItemID: $selectedItemID
            )
        } detail: {
            ItemDetailView(itemID: selectedItemID)
        }
    }
}

/// What the user has selected in the sidebar. The two cases mirror the
/// two sidebar sections; `nil` selection drops the content column to a
/// placeholder.
enum SidebarSelection: Hashable, Sendable {
    case smartList(SmartList)
    case location(Location.ID)
}

/// Sidebar Smart Lists. Only the structure lands in Phase 1.3; the
/// actual computed projections (`expiresAt` within 7 days,
/// recency, cross-location list) arrive with the Smart Lists feature in
/// Phase 6. Until then, selecting one shows an empty state.
enum SmartList: String, CaseIterable, Identifiable, Sendable {
    case expiringSoon
    case allItems
    case recentlyAdded

    var id: Self { self }

    var title: String {
        switch self {
        case .expiringSoon: "Expiring Soon"
        case .allItems: "All Items"
        case .recentlyAdded: "Recently Added"
        }
    }

    var systemImage: String {
        switch self {
        case .expiringSoon: "clock.badge.exclamationmark"
        case .allItems: "tray.full"
        case .recentlyAdded: "sparkles"
        }
    }
}

#Preview("Empty store") {
    RootView()
        .environment(\.repositories, .makePreview())
}
