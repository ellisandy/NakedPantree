import NakedPantreeDomain
import SwiftUI

/// Issue #131: Settings-screen section that owns the create / edit /
/// delete affordances for the household's locations. Lives in
/// `SettingsView` instead of the sidebar toolbar — beta testers
/// consistently misread the sidebar's `+` as "add item" rather than
/// "add location", and locations are a rare-action surface that
/// doesn't deserve top-level real estate.
///
/// **Why the section can't present its own form sheet (build #52
/// regression).** The original implementation attached
/// `.sheet(item: $formMode)` directly to the section, deep under a
/// Form's Section. SwiftUI's presentation-context resolution couldn't
/// tell which sheet was being asked to present from a Section-attached
/// `.sheet` and would dismiss the entire sheet stack — including the
/// parent Settings sheet — the moment the form tried to appear. Build
/// #52 reproduced this every time. Fix: lift the `.sheet(item:)`
/// modifier to `SettingsView`'s NavigationStack, where the
/// presentation context is unambiguous. The section keeps its
/// own state for delete-confirmation (a `confirmationDialog`,
/// which is action-sheet-shaped and doesn't have the same
/// presentation-context bug).
///
/// **Why a callback rather than a binding (issue #162).** Earlier
/// the section took `@Binding var formMode` and wrote into it on Add
/// / Edit taps; the parent watched that binding to drive its sheet.
/// That works in isolation but means the parent has to expose
/// `formMode` as a sheet driver — and once Settings grew a third
/// sheet (the Reminders picker), three independent `.sheet` modifiers
/// were stacked on the NavigationStack and SwiftUI could no longer
/// resolve the unique presentation. The probe in PR #165 confirmed
/// the picker auto-dismissed within ~553 ms. Issue #162 folded all
/// three presentations through a single `.sheet(item: $presentedSheet)`
/// in the parent. The section now hands a `LocationFormView.Mode` up
/// via the `presentForm` callback, and the parent maps that into the
/// shared sheet enum.
///
/// **Reload semantics.** With the binding removed the section can no
/// longer observe its own `formMode` going nil to re-fetch. Instead
/// the parent bumps `reloadToken` after `presentedSheet` flips back to
/// nil with the form having been the last presented sheet; the
/// section's `.onChange(of: reloadToken)` triggers the reload.
///
/// **Why a standalone view:** extracting this from `SettingsView`
/// keeps the load / form-callback / reload cycle decoupled from the
/// Settings screen as a whole. Mirrors the existing `RestockSection`
/// pattern in `ItemDetailView`.
struct LocationsSection: View {
    /// Household whose locations this section manages. Settings
    /// resolves the household once (same `loadHousehold()` it uses for
    /// the household name row) and hands the ID down. `nil` while the
    /// load is in flight or if it failed — section renders nothing in
    /// that case rather than a stale list against the wrong household.
    let householdID: Household.ID?

    /// Issue #162 — request the parent to present the create/edit
    /// form sheet for the given mode. Replaces the prior `@Binding`
    /// pattern; see the type doc for the full root-cause writeup.
    let presentForm: (LocationFormView.Mode) -> Void

    /// Issue #162 — bumped by the parent any time the section should
    /// re-fetch (specifically: after the lifted form sheet dismisses).
    /// Replaces the prior self-observed `.onChange(of: formMode)`
    /// trigger.
    let reloadToken: Int

    @Environment(\.repositories) private var repositories

    @State private var locations: [Location] = []
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
                        presentForm(.edit(location))
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
                    presentForm(.create(householdID: householdID))
                } label: {
                    Label("Add Location", systemImage: "plus.circle.fill")
                }
                .accessibilityIdentifier("settings.locations.add")
            }
        } header: {
            Text("Locations")
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
        // Issue #162: parent bumps `reloadToken` after the lifted form
        // sheet dismisses. We reload regardless of whether the user
        // saved or cancelled — same belt-and-suspenders behaviour as
        // before the binding was removed.
        .onChange(of: reloadToken) { _, _ in
            Task { await reload() }
        }
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
