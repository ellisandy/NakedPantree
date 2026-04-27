import NakedPantreeDomain
import SwiftUI

/// Two-section sidebar from `ARCHITECTURE.md` §7. Smart Lists are the
/// fixed top section; Locations is data-driven from `LocationRepository`.
struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @Environment(\.repositories) private var repositories
    @Environment(\.remoteChangeMonitor) private var remoteChangeMonitor

    @State private var locations: [Location] = []
    @State private var householdID: Household.ID?
    @State private var loadError: Error?
    @State private var formMode: LocationFormView.Mode?
    @State private var pendingDelete: Location?
    @State private var isPresentingSettings = false

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
                    // exit criterion).
                    Label("No locations yet. Tap + to add one.", systemImage: "tray")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(locations) { location in
                        Label(location.name, systemImage: location.kind.systemImage)
                            .tag(SidebarSelection.location(location.id))
                            .accessibilityIdentifier("sidebar.location.\(location.name)")
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDelete = location
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    formMode = .edit(location)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.indigo)
                            }
                    }
                }
            }
        }
        .navigationTitle("Naked Pantree")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let householdID {
                        formMode = .create(householdID: householdID)
                    }
                } label: {
                    Label("New Location", systemImage: "plus")
                }
                .disabled(householdID == nil)
            }
            // Phase 9.3 introduced the Settings entry point in the
            // secondary toolbar slot. Phase 10.1 (#60) folded household
            // sharing into Settings, so this is now the sidebar's only
            // secondary action. Always available — even in previews /
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
        .sheet(item: $formMode) { mode in
            LocationFormView(mode: mode) {
                Task { await reload() }
            }
        }
        .sheet(isPresented: $isPresentingSettings) {
            SettingsView()
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: deleteDialogBinding,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { location in
            Button("Delete", role: .destructive) {
                Task { await delete(location) }
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: { _ in
            Text("This also removes every item inside it.")
        }
        .task(id: remoteChangeMonitor.changeToken) { await reload() }
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

    private func reload() async {
        do {
            let house = try await repositories.household.currentHousehold()
            householdID = house.id
            locations = try await repositories.location.locations(in: house.id)
        } catch {
            loadError = error
        }
    }

    private func delete(_ location: Location) async {
        pendingDelete = nil
        if case .location(let selectedID) = selection, selectedID == location.id {
            selection = .smartList(.allItems)
        }
        do {
            try await repositories.location.delete(id: location.id)
            await reload()
        } catch {
            loadError = error
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
