import NakedPantreeDomain
import SwiftUI

/// Three-column `NavigationSplitView` per `ARCHITECTURE.md` §7. Sidebar
/// selection drives what the content column shows; content selection
/// drives what the detail column shows.
///
/// Children that read repositories (`SidebarView`, `ItemsView`,
/// `AllItemsView`) cache their fetch in `@State` and only refetch on
/// their own `.task`. To keep first-launch bootstrap from racing those
/// caches — the original Kitchen-doesn't-appear-on-fresh-install bug —
/// we gate the whole shell on `bootstrapComplete`. The brief
/// brand-color splash is acceptable for an in-memory + one-row
/// Core Data write that completes in single-digit milliseconds.
struct RootView: View {
    // Initial selection is `nil` so iPhone (compact `NavigationSplitView`)
    // lands the user on the sidebar — defaulting to a smart list there
    // auto-collapses to the content column on first launch, hiding the
    // sidebar entirely until they tap Back. iPad (regular) still shows
    // both columns; the placeholder in `ItemsView` covers the nil case.
    @State private var sidebarSelection: SidebarSelection?
    @State private var selectedItemID: Item.ID?
    @State private var bootstrapComplete = false
    @Environment(\.repositories) private var repositories
    @Environment(\.accountStatusMonitor) private var accountStatusMonitor

    var body: some View {
        Group {
            if bootstrapComplete {
                VStack(spacing: 0) {
                    AccountStatusBanner(status: accountStatusMonitor.status)
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
            } else {
                Color.brandWarmCream
                    .ignoresSafeArea()
            }
        }
        .task {
            await runBootstrap()
            bootstrapComplete = true
        }
    }

    private func runBootstrap() async {
        let bootstrap = BootstrapService(
            household: repositories.household,
            location: repositories.location
        )
        try? await bootstrap.bootstrapIfNeeded()

        // Snapshot mode: respect any deep-link env vars so the screenshot
        // captures the requested surface without UI taps. A no-op outside
        // snapshot mode.
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
