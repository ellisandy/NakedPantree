import NakedPantreeDomain
import SwiftUI

/// Three-column `NavigationSplitView` per `ARCHITECTURE.md` §7. Sidebar
/// selection drives what the content column shows; content selection
/// drives what the detail column shows.
struct RootView: View {
    @State private var sidebarSelection: SidebarSelection? = .smartList(.allItems)
    @State private var selectedItemID: Item.ID?
    @Environment(\.repositories) private var repositories

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
        .task {
            // First-launch bootstrap per ARCHITECTURE.md §6: ensure the
            // user lands in a household with at least one location. The
            // service is idempotent — no-op on every subsequent launch.
            let bootstrap = BootstrapService(
                household: repositories.household,
                location: repositories.location
            )
            try? await bootstrap.bootstrapIfNeeded()

            // Snapshot mode: respect any deep-link env vars so the
            // screenshot captures the requested surface without UI
            // taps. A no-op outside snapshot mode.
            if SnapshotFixtures.isSnapshotMode {
                if let initial = await SnapshotFixtures.resolveInitialSidebar(in: repositories) {
                    sidebarSelection = initial
                }
                if let itemID = await SnapshotFixtures.resolveInitialItem(in: repositories) {
                    selectedItemID = itemID
                }
            }
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

/// Sidebar Smart Lists. `All Items` is wired up in Phase 1.5 (cross-
/// location list with search). The other projections (`expiresAt` within
/// 7 days, recently-added) arrive with the Smart Lists feature in
/// Phase 6 — selecting one of those shows a placeholder until then.
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
