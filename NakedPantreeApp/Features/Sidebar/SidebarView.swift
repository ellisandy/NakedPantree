import NakedPantreeDomain
import SwiftUI

/// Two-section sidebar from `ARCHITECTURE.md` §7. Smart Lists are the
/// fixed top section; Locations is data-driven from `LocationRepository`.
struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @Environment(\.repositories) private var repositories

    @State private var locations: [Location] = []
    @State private var householdID: Household.ID?
    @State private var loadError: Error?
    @State private var formMode: LocationFormView.Mode?
    @State private var pendingDelete: Location?

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
                    Text("No locations yet. Tap + to add one.")
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
        }
        .sheet(item: $formMode) { mode in
            LocationFormView(mode: mode) {
                Task { await reload() }
            }
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
        .task { await reload() }
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
