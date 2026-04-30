import NakedPantreeDomain
import SwiftUI

/// Modal form for creating or editing a `Location`. Used from
/// `SidebarView`'s "+" toolbar action and its row-edit affordance.
struct LocationFormView: View {
    enum Mode: Identifiable, Hashable {
        case create(householdID: Household.ID)
        case edit(Location)

        var id: String {
            switch self {
            case .create(let id): "create-\(id.uuidString)"
            case .edit(let location): "edit-\(location.id.uuidString)"
            }
        }

        var householdID: Household.ID {
            switch self {
            case .create(let id): id
            case .edit(let location): location.householdID
            }
        }

        /// `nil` on create (no row to skip); the row's id on edit so
        /// the duplicate-name check doesn't false-positive on the
        /// row's own current name.
        var editingLocationID: Location.ID? {
            switch self {
            case .create: nil
            case .edit(let location): location.id
            }
        }
    }

    let mode: Mode
    let onSaved: @MainActor () -> Void

    @Environment(\.repositories) private var repositories
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var kind: LocationKind = .pantry
    @State private var isSaving = false
    @State private var saveError: String?
    /// Issue #133: snapshot of the household's existing locations,
    /// loaded once when the form appears. Used for live duplicate-name
    /// validation. Filtered to exclude the row being edited so a
    /// no-rename "save" doesn't false-positive against itself.
    @State private var existingNormalizedNames: Set<String> = []

    private let kindOptions: [LocationKind] = [.pantry, .fridge, .freezer, .dryGoods, .other]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Kitchen Pantry", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                    // Inline duplicate-name error per #133. Sits in the
                    // same Section as the field so it reads as field-
                    // scoped feedback. Hidden when the name is empty
                    // (the empty-name disable is enough signal there)
                    // or when the name doesn't collide.
                    if let duplicateMessage = duplicateNameMessage {
                        Label(duplicateMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("location.duplicateNameError")
                    }
                }

                Section("Type") {
                    Picker("Type", selection: $kind) {
                        ForEach(kindOptions, id: \.self) { option in
                            Label(option.displayName, systemImage: option.systemImage)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if let saveError {
                    Section {
                        // Icon + text per `DESIGN_GUIDELINES.md` §10 /
                        // Phase 6 exit criterion — never color alone.
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.surface)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveButtonTitle) {
                        Task { await save() }
                    }
                    .disabled(!isSaveAllowed || isSaving)
                }
            }
            .onAppear(perform: prefill)
            .task { await loadExistingNames() }
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .create: "New Location"
        case .edit: "Edit Location"
        }
    }

    private var saveButtonTitle: String {
        switch mode {
        case .create: "Add"
        case .edit: "Save"
        }
    }

    /// `true` when the typed name is non-empty AND not a duplicate.
    /// The duplicate check is the issue-#133 live-validation gate;
    /// the non-empty check came from #117's existing
    /// `LocationFormSaveCoordinator.isValid`.
    private var isSaveAllowed: Bool {
        LocationFormSaveCoordinator.isValid(name: name) && duplicateNameMessage == nil
    }

    /// Returns user-facing copy when the trimmed/case-folded name
    /// collides with another location in the household; otherwise
    /// `nil`. The check is local-only — it consults the snapshot
    /// loaded in `loadExistingNames`. The repository remains the
    /// authoritative gate (catches CloudKit-sync races where another
    /// device added a duplicate after the snapshot loaded), but
    /// surfacing the error inline keeps the typical case fast.
    private var duplicateNameMessage: String? {
        let normalized = normalizedLocationName(name)
        guard !normalized.isEmpty,
            existingNormalizedNames.contains(normalized)
        else {
            return nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return "A location named \"\(trimmed)\" already exists."
    }

    private func prefill() {
        if case .edit(let location) = mode {
            name = location.name
            kind = location.kind
        }
    }

    /// Loads the household's existing location names into a Set,
    /// filtered to exclude the row currently being edited. Failures
    /// fall through silently — the worst case is the user typing a
    /// duplicate, hitting Save, and getting the repository error as
    /// the saveError banner instead of inline. That's the same shape
    /// as a CloudKit-sync race; harmless.
    private func loadExistingNames() async {
        do {
            let all = try await repositories.location.locations(in: mode.householdID)
            let editingID = mode.editingLocationID
            existingNormalizedNames = Set(
                all
                    .filter { $0.id != editingID }
                    .map { normalizedLocationName($0.name) }
            )
        } catch {
            existingNormalizedNames = []
        }
    }

    @MainActor
    private func save() async {
        // Issue #117: persistence lives in `LocationFormSaveCoordinator`;
        // view keeps the spinner / banner / dismiss responsibilities.
        let draft = LocationFormDraft(name: name, kind: kind)
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await LocationFormSaveCoordinator.save(
                mode: mode,
                draft: draft,
                repository: repositories.location
            )
            onSaved()
            dismiss()
        } catch let LocationRepositoryError.duplicateName(collidingName) {
            // Issue #133: the repository caught a duplicate that the
            // local snapshot missed (e.g. CloudKit-sync race). Surface
            // the same field-scoped copy as the live check so the
            // user can correct it.
            let trimmed = collidingName.trimmingCharacters(in: .whitespacesAndNewlines)
            saveError = "A location named \"\(trimmed)\" already exists."
        } catch {
            saveError = "Couldn't save. Try again."
        }
    }
}

extension LocationKind {
    /// Capitalized human label used in pickers and detail headers.
    var displayName: String {
        switch self {
        case .pantry: "Pantry"
        case .fridge: "Fridge"
        case .freezer: "Freezer"
        case .dryGoods: "Dry Goods"
        case .other: "Other"
        case .unknown(let raw): raw.capitalized
        }
    }
}

#Preview("Create") {
    LocationFormView(mode: .create(householdID: UUID()), onSaved: {})
        .environment(\.repositories, .makePreview())
}

#Preview("Edit") {
    LocationFormView(
        mode: .edit(
            Location(householdID: UUID(), name: "Kitchen", kind: .pantry)
        ),
        onSaved: {}
    )
    .environment(\.repositories, .makePreview())
}
