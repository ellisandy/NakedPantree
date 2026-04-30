import NakedPantreeDomain
import SwiftUI

/// Issue #131: Settings-screen section that owns the create / edit /
/// delete affordances for the household's locations. Lives in
/// `SettingsView` instead of the sidebar toolbar — beta testers
/// consistently misread the sidebar's `+` as "add item" rather than
/// "add location", and locations are a rare-action surface that
/// doesn't deserve top-level real estate.
///
/// The sibling issue (#132) repurposes the freed sidebar `+` slot as
/// a "New Item" entry point. Until #132 lands, the sidebar has no
/// primary toolbar action — that's the documented in-between state.
///
/// **Reload semantics:** the `LocationFormView` callback and the
/// delete handler both reload by re-fetching `locations(in:)` on
/// completion. The sibling sidebar reloads on Settings sheet dismiss
/// (no shared store needed, no cross-component callback).
///
/// **Why a standalone view:** extracting this from `SettingsView`
/// makes the load / form-callback / reload cycle unit-testable
/// without standing up the whole Settings screen. Mirrors the
/// existing `RestockSection` pattern in `ItemDetailView`.
struct LocationsSection: View {
    /// Household whose locations this section manages. Settings
    /// resolves the household once (same `loadHousehold()` it uses for
    /// the household name row) and hands the ID down. `nil` while the
    /// load is in flight or if it failed — section renders nothing in
    /// that case rather than a stale list against the wrong household.
    let householdID: Household.ID?

    @Environment(\.repositories) private var repositories

    @State private var locations: [Location] = []
    @State private var formMode: LocationFormView.Mode?
    @State private var pendingDelete: Location?
    @State private var loadError: Error?

    var body: some View {
        Section {
            if let householdID {
                if locations.isEmpty {
                    Text("No locations yet — tap Add Location to set one up.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.locations.empty")
                }
                ForEach(locations) { location in
                    Button {
                        formMode = .edit(location)
                    } label: {
                        Label(location.name, systemImage: location.kind.systemImage)
                            .foregroundStyle(.primary)
                    }
                    .accessibilityIdentifier("settings.location.\(location.name)")
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDelete = location
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                Button {
                    formMode = .create(householdID: householdID)
                } label: {
                    Label("Add Location", systemImage: "plus.circle.fill")
                }
                .accessibilityIdentifier("settings.locations.add")
            }
        } header: {
            Text("Locations")
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
        .task(id: householdID) { await reload() }
    }

    private var deleteConfirmationTitle: String {
        if let pendingDelete {
            return "Delete \(pendingDelete.name)?"
        }
        return ""
    }

    /// `.confirmationDialog(isPresented:)` wants a `Bool` binding;
    /// we drive it off the optional `pendingDelete` so dismissing
    /// the dialog clears the row in one place.
    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { newValue in
                if !newValue { pendingDelete = nil }
            }
        )
    }

    /// Same swallow-and-fail-soft pattern as `SettingsView.loadHousehold`
    /// and `SidebarView.reload`: location reads are not user-fatal —
    /// the row count just stays stale. A real error banner is a
    /// follow-up if location operations ever surface failures we
    /// want the user to act on.
    private func reload() async {
        guard let householdID else {
            locations = []
            return
        }
        do {
            locations = try await repositories.location.locations(in: householdID)
            loadError = nil
        } catch {
            loadError = error
        }
    }

    private func delete(_ location: Location) async {
        pendingDelete = nil
        do {
            try await repositories.location.delete(id: location.id)
            await reload()
        } catch {
            loadError = error
        }
    }
}
