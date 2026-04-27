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
/// we gate the whole shell on `bootstrapComplete`. The pre-bootstrap
/// state shows `LaunchView` (Phase 9.2) so the user sees the wordmark
/// + a progress indicator instead of a blank cream surface — Phase 8.2
/// bootstrap-defer made the wait long enough on fresh install + slow
/// sync that a static color reads as a hung app.
struct RootView: View {
    // Initial selection is `nil` so iPhone (compact `NavigationSplitView`)
    // lands the user on the sidebar — defaulting to a smart list there
    // auto-collapses to the content column on first launch, hiding the
    // sidebar entirely until they tap Back. iPad (regular) still shows
    // both columns; the placeholder in `ItemsView` covers the nil case.
    @State private var sidebarSelection: SidebarSelection?
    @State private var selectedItemID: Item.ID?
    @State private var searchQuery: String = ""
    @State private var bootstrapComplete = false
    @State private var isShowingMissingItemAlert = false
    @Environment(\.repositories) private var repositories
    @Environment(\.accountStatusMonitor) private var accountStatusMonitor
    @Environment(\.notificationRouting) private var notificationRouting
    @Environment(\.remoteChangeMonitor) private var remoteChangeMonitor
    @Environment(\.notificationScheduler) private var notificationScheduler

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
                            searchQuery: searchQuery,
                            selectedItemID: $selectedItemID
                        )
                    } detail: {
                        ItemDetailView(itemID: selectedItemID)
                    }
                    // Phase 6.2b: cross-household search lives on the
                    // sidebar so a non-empty query routes the content
                    // column to a peer "search results" mode without
                    // adding a `SidebarSelection` case. Compact iPhone
                    // collapses `.sidebar` placement to the navigation
                    // bar drawer for free.
                    .searchable(
                        text: $searchQuery,
                        placement: .sidebar,
                        prompt: "Search items"
                    )
                }
                // Phase 10.5c: brand-cream canvas under the whole shell.
                // Each `List` / `Form` clears its own scroll background
                // and re-fills with `Color.surface`, but the surrounding
                // `VStack` still needs the brand fill so the safe-area
                // insets and any compact-mode chrome read as canvas
                // rather than the system default. Resolves via
                // `BrandWarmCream.colorset` so dark mode lifts to
                // `#1C1B17` without per-view branching.
                .background(Color.surface.ignoresSafeArea())
                // Phase 4.3: every remote-change tick (including the
                // first cold-launch one) reconciles pending expiry
                // notifications with the current item set. Lives inside
                // the `bootstrapComplete` branch so it never runs before
                // `currentHousehold()` has anything to return.
                .task(id: remoteChangeMonitor.changeToken) {
                    await resyncExpiryNotifications()
                }
            } else {
                LaunchView()
            }
        }
        .task {
            await runBootstrap()
            bootstrapComplete = true
            // Cold-launch path: a tap before the view appeared will have
            // already published `pendingItemID`. `.onChange` only fires
            // on changes after the view is alive, so we apply once here.
            // Clear *before* awaiting so a second tap during the
            // suspended apply queues into `pendingItemID` instead of
            // being lost.
            if let pending = notificationRouting.pendingItemID {
                notificationRouting.pendingItemID = nil
                await applyDeepLink(itemID: pending)
            }
        }
        .onChange(of: notificationRouting.pendingItemID) { _, newValue in
            // Warm-tap path: app already running, user taps a banner.
            // Bootstrap-complete gate keeps the cold-launch case from
            // double-applying — the `.task` block above handles that
            // and clears `pendingItemID` before the change observer
            // would fire on the cleared-back-to-nil value.
            guard bootstrapComplete, let id = newValue else { return }
            // Same ordering rationale as the cold-launch path: clear
            // before awaiting so a second tap during the suspended
            // apply re-publishes onto `pendingItemID` rather than
            // racing with this completion.
            notificationRouting.pendingItemID = nil
            Task {
                await applyDeepLink(itemID: id)
            }
        }
        .alert("That item is gone.", isPresented: $isShowingMissingItemAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    private func runBootstrap() async {
        let bootstrap = BootstrapService(
            household: repositories.household,
            location: repositories.location,
            waitForRemoteChange: makeRemoteChangeWaiter()
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

    /// Builds the closure that `BootstrapService` awaits on a fresh
    /// install: it resolves on the first `RemoteChangeMonitor` tick
    /// (sync has begun importing) so bootstrap can re-peek for an
    /// existing household before creating a duplicate. Returns
    /// immediately when iCloud is signed-out / restricted — there's
    /// no sync coming, no point burning the bootstrap timeout on the
    /// splash.
    ///
    /// Implementation note: `RemoteChangeMonitor.changeToken` is
    /// `@Observable`, so polling it via `withObservationTracking` would
    /// give a one-shot `onChange` callback — but the continuation
    /// must also be resumed if the surrounding task is cancelled by
    /// `BootstrapService`'s timeout race, otherwise we'd leak the
    /// continuation. A short polling loop with `Task.sleep` is the
    /// simplest shape that handles both paths cleanly: cancellation
    /// throws out of the sleep, and the loop exits.
    private func makeRemoteChangeWaiter() -> @Sendable () async -> Void {
        let monitor = remoteChangeMonitor
        let statusMonitor = accountStatusMonitor
        return {
            // No-op monitor (preview / snapshot / EMPTY_STORE / unit
            // test host paths) → no remote-change tick will ever
            // arrive. Skip the wait so bootstrap falls through to
            // create immediately rather than burning the timeout
            // every cold launch in those configurations.
            guard monitor.isObserving else { return }
            let isAvailable = await MainActor.run { statusMonitor.status == .available }
            guard isAvailable else { return }
            let initial = await MainActor.run { monitor.changeToken }
            // Poll every ~75ms until the token bumps or the task is
            // cancelled by the bootstrap timeout. The monitor's own
            // 120ms debounce dominates the worst-case wakeup latency
            // anyway — a tighter poll buys nothing real.
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(75))
                } catch {
                    return
                }
                let current = await MainActor.run { monitor.changeToken }
                if current != initial { return }
            }
        }
    }

    /// Resolves a notification-tap deep link. Sets the sidebar to the
    /// item's location and selects the item; if the item has been
    /// deleted (e.g. another household member tossed it before the
    /// tap landed) lands on the Expiring Soon smart list and shows
    /// the "That item is gone." alert per `ARCHITECTURE.md` §8.
    private func applyDeepLink(itemID: Item.ID) async {
        do {
            guard let item = try await repositories.item.item(id: itemID) else {
                sidebarSelection = .smartList(.expiringSoon)
                selectedItemID = nil
                isShowingMissingItemAlert = true
                return
            }
            sidebarSelection = .location(item.locationID)
            selectedItemID = item.id
        } catch {
            // Repository read failed — most likely a transient store
            // hiccup. Keep the user where they were rather than dumping
            // them into an alert; if it was a real bug, the next tap or
            // remote-change tick will reload state.
        }
    }

    /// Reconciles pending notification requests with the current item
    /// set. A read failure leaves the existing requests alone — better
    /// than nuking pending notifications on a transient hiccup.
    private func resyncExpiryNotifications() async {
        do {
            let household = try await repositories.household.currentHousehold()
            let items = try await repositories.item.allItems(in: household.id)
            await notificationScheduler.resync(currentItems: items)
        } catch {
            // Swallow — see comment above. The next changeToken tick
            // will retry.
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
