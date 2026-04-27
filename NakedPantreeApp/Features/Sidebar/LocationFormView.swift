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
    }

    let mode: Mode
    let onSaved: @MainActor () -> Void

    @Environment(\.repositories) private var repositories
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var kind: LocationKind = .pantry
    @State private var isSaving = false
    @State private var saveError: String?

    private let kindOptions: [LocationKind] = [.pantry, .fridge, .freezer, .dryGoods, .other]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Kitchen Pantry", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
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
                    .disabled(!isValid || isSaving)
                }
            }
            .onAppear(perform: prefill)
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

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func prefill() {
        if case .edit(let location) = mode {
            name = location.name
            kind = location.kind
        }
    }

    @MainActor
    private func save() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        defer { isSaving = false }

        do {
            switch mode {
            case .create(let householdID):
                let location = Location(householdID: householdID, name: trimmed, kind: kind)
                try await repositories.location.create(location)
            case .edit(let original):
                var updated = original
                updated.name = trimmed
                updated.kind = kind
                try await repositories.location.update(updated)
            }
            onSaved()
            dismiss()
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
