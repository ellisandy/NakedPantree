import NakedPantreeDomain
import SwiftUI

/// Two-section sidebar from `ARCHITECTURE.md` §7. Smart Lists are the
/// fixed top section; Locations is data-driven from `LocationRepository`.
///
/// **Issue #131:** location create / edit / delete affordances moved
/// out of the sidebar into Settings. Beta testers consistently misread
/// the sidebar's `+` as "add item" rather than "add location", and
/// locations are a rare-action surface. The sidebar keeps the
/// locations list for navigation; mutations live exclusively in
/// Settings.
///
/// **Issue #132:** the freed primary toolbar slot is now "New Item" —
/// the action testers actually expected from a `+`. Tap branches on
/// location count: zero → guidance alert, one → straight to the form,
/// two-plus → action sheet to pick a location. After save the sidebar
/// snaps to that location so the user sees the item they just added.
struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @Environment(\.repositories) private var repositories
    @Environment(\.remoteChangeMonitor) private var remoteChangeMonitor

    @State private var locations: [Location] = []
    @State private var loadError: Error?
    @State private var isPresentingSettings = false
    /// Issue #132: drives the New Item form sheet. `nil` while the
    /// sheet is dismissed; set to `.create(locationID:)` once the
    /// user has picked (or auto-picked) a target location.
    @State private var itemFormMode: ItemFormView.Mode?
    /// Drives the multi-location action sheet — only used when the
    /// household has 2+ locations.
    @State private var isPresentingLocationPicker = false
    /// Drives the zero-locations guidance alert.
    @State private var isPresentingNoLocationsAlert = false

    var body: some View {
        List(selection: $selection) {
            Section("Smart Lists") {
                ForEach(SmartList.allCases) { list in
                    Label(list.title, systemImage: list.systemImage)
                        .tag(SidebarSelection.smartList(list))
                        .accessibilityIdentifier("sidebar.smartList.\(list.rawValue)")
                }
            }

            Section("Locations") {
                if locations.isEmpty {
                    // Phase 6.4: icon + text for the empty-state row so
                    // the sidebar matches the rest of the app's empty-
                    // state pattern (`DESIGN_GUIDELINES.md` §10 / Phase 6
                    // exit criterion). Issue #131 repointed the copy
                    // away from the (removed) toolbar `+` toward the
                    // gear icon — Settings now owns location creation.
                    Label("No locations yet — tap the gear to add one.", systemImage: "tray")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(locations) { location in
                        Label(location.name, systemImage: location.kind.systemImage)
                            .tag(SidebarSelection.location(location.id))
                            .accessibilityIdentifier("sidebar.location.\(location.name)")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.surface)
        .navigationTitle("Naked Pantree")
        .toolbar {
            // Issue #132: primary slot is now "New Item" (was "New
            // Location" pre-#131). Tap branches on location count;
            // see `handleNewItemTap()`. Disabled while locations are
            // still loading so a fast-finger tap before bootstrap
            // doesn't fire the zero-locations alert spuriously.
            ToolbarItem(placement: .primaryAction) {
                Button {
                    handleNewItemTap()
                } label: {
                    Label("New Item", systemImage: "plus")
                }
                .accessibilityIdentifier("sidebar.newItem")
            }
            // Phase 9.3 introduced the Settings entry point in the
            // secondary toolbar slot. Phase 10.1 (#60) folded household
            // sharing into Settings; #131 folded location management in
            // alongside it. Always available — even in previews /
            // tests, where the no-op `NotificationSettings` default
            // lets the screen render without a real UserDefaults
            // backing.
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    isPresentingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("settings.toolbar.entry")
            }
        }
        .sheet(isPresented: $isPresentingSettings) {
            SettingsView()
        }
        // Issue #132: New Item form sheet. `onSaved` snaps the sidebar
        // selection to the location the user added to — that's the
        // most useful place to land them per the issue's spec.
        // `mode` capture lets us recover the locationID without
        // duplicating it in `@State`.
        .sheet(item: $itemFormMode) { mode in
            ItemFormView(mode: mode) {
                if case .create(let locationID) = mode {
                    selection = .location(locationID)
                }
            }
        }
        // Multi-location picker — only presented when the household
        // has 2+ locations. Single-location users skip this entirely
        // (see `handleNewItemTap`).
        .confirmationDialog(
            "Add to which location?",
            isPresented: $isPresentingLocationPicker,
            titleVisibility: .visible
        ) {
            ForEach(locations) { location in
                Button(location.name) {
                    itemFormMode = .create(locationID: location.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        // Zero-locations guidance — points at Settings (which is one
        // tap away on the toolbar). Voice rule §10: short, useful,
        // no humor for the broken-flow nudge.
        .alert(
            "No locations yet",
            isPresented: $isPresentingNoLocationsAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add a location in Settings to start tracking items.")
        }
        // Cross-device reload: `RemoteChangeMonitor` skips local-author
        // writes, so this only fires when another device (or a freshly-
        // imported share) bumps the token.
        .task(id: remoteChangeMonitor.changeToken) { await reload() }
        // Same-device reload: Settings now owns location create/edit/
        // delete (#131), so the local-author skip above means the
        // sidebar wouldn't otherwise reflect changes made in the
        // sheet. Reload when Settings dismisses so the user comes
        // back to a fresh list. If a deleted location was the active
        // selection, snap back to All Items so the content column
        // doesn't render against a stale ID.
        .onChange(of: isPresentingSettings) { _, newValue in
            guard !newValue else { return }
            Task { await reloadAndReconcileSelection() }
        }
    }

    /// Issue #132: branches on the loaded locations array. The sidebar
    /// already keeps `locations` in `@State` for navigation, so the
    /// branch is synchronous — no second fetch on tap. Single-
    /// location households skip the picker and pay one fewer tap.
    private func handleNewItemTap() {
        switch locations.count {
        case 0:
            isPresentingNoLocationsAlert = true
        case 1:
            // Force-unwrap-equivalent via subscript is safe under
            // `count == 1`; using `first` keeps the optional-chain
            // explicit for readability.
            if let only = locations.first {
                itemFormMode = .create(locationID: only.id)
            }
        default:
            isPresentingLocationPicker = true
        }
    }

    private func reload() async {
        do {
            let house = try await repositories.household.currentHousehold()
            locations = try await repositories.location.locations(in: house.id)
        } catch {
            loadError = error
        }
    }

    /// Reload + drop the active selection if the user deleted the
    /// currently-selected location from Settings.
    private func reloadAndReconcileSelection() async {
        await reload()
        if case .location(let selectedID) = selection,
            !locations.contains(where: { $0.id == selectedID })
        {
            selection = .smartList(.allItems)
        }
    }
}

extension LocationKind {
    /// SF Symbol used in sidebar rows. Tokens here are functional, not
    /// brand-styled — full design pass for Locations icons is a Phase 6
    /// polish item per `DESIGN_GUIDELINES.md`.
    var systemImage: String {
        switch self {
        case .pantry: "shippingbox"
        case .fridge: "refrigerator"
        case .freezer: "snowflake"
        case .dryGoods: "bag"
        case .other: "square.grid.2x2"
        case .unknown: "questionmark.square"
        }
    }
}

#Preview {
    @Previewable @State var selection: SidebarSelection? = .smartList(.allItems)
    NavigationSplitView {
        SidebarView(selection: $selection)
    } detail: {
        Text("Detail")
    }
    .environment(\.repositories, .makePreview())
}
