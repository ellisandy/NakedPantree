import NakedPantreeDomain
import SwiftUI

/// Modal form for creating or editing an `Item`.
struct ItemFormView: View {
    enum Mode: Identifiable, Hashable {
        case create(locationID: Location.ID)
        case edit(Item)

        var id: String {
            switch self {
            case .create(let id): "create-\(id.uuidString)"
            case .edit(let item): "edit-\(item.id.uuidString)"
            }
        }
    }

    let mode: Mode
    let onSaved: @MainActor () -> Void

    @Environment(\.repositories) private var repositories
    @Environment(\.notificationScheduler) private var notificationScheduler
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var quantity: Int32 = 1
    @State private var unit: NakedPantreeDomain.Unit = .count
    @State private var hasExpiry: Bool = false
    @State private var expiresAt: Date = .now.addingTimeInterval(TimeInterval(60 * 60 * 24 * 7))
    @State private var notes: String = ""
    @State private var isSaving = false
    @State private var saveError: String?

    private let unitOptions: [NakedPantreeDomain.Unit] = [
        .count, .gram, .kilogram, .ounce, .pound,
        .milliliter, .liter, .fluidOunce, .package,
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Tomatoes", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled()
                }

                Section("Quantity") {
                    Stepper(value: $quantity, in: 1...9999) {
                        Text("\(quantity) \(unit.displayLabel)")
                    }
                    Picker("Unit", selection: $unit) {
                        ForEach(unitOptions, id: \.self) { option in
                            Text(option.pickerLabel).tag(option)
                        }
                    }
                }

                Section("Expiry") {
                    Toggle("Has expiry date", isOn: $hasExpiry)
                    if hasExpiry {
                        DatePicker(
                            "Expires",
                            selection: $expiresAt,
                            displayedComponents: .date
                        )
                    }
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
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
        case .create: "New Item"
        case .edit: "Edit Item"
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
        if case .edit(let item) = mode {
            name = item.name
            quantity = item.quantity
            unit = item.unit
            if let expiry = item.expiresAt {
                hasExpiry = true
                expiresAt = expiry
            }
            notes = item.notes ?? ""
        }
    }

    @MainActor
    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNotes: String? = trimmedNotes.isEmpty ? nil : trimmedNotes
        let resolvedExpiry: Date? = hasExpiry ? expiresAt : nil

        isSaving = true
        defer { isSaving = false }

        do {
            let saved: Item
            switch mode {
            case .create(let locationID):
                let item = Item(
                    locationID: locationID,
                    name: trimmedName,
                    quantity: quantity,
                    unit: unit,
                    expiresAt: resolvedExpiry,
                    notes: resolvedNotes
                )
                try await repositories.item.create(item)
                saved = item
            case .edit(let original):
                var updated = original
                updated.name = trimmedName
                updated.quantity = quantity
                updated.unit = unit
                updated.expiresAt = resolvedExpiry
                updated.notes = resolvedNotes
                try await repositories.item.update(updated)
                saved = updated
            }
            // Phase 4.1: schedule (or clear) the expiry notification
            // off the just-persisted item. `scheduleIfNeeded` handles
            // the nil-expiry case symmetrically with create vs edit —
            // clearing an expiry on edit cancels the pending request.
            await notificationScheduler.scheduleIfNeeded(for: saved)
            onSaved()
            dismiss()
        } catch {
            saveError = "Couldn't save. Try again."
        }
    }
}

extension NakedPantreeDomain.Unit {
    /// Longer label used in dropdowns, where "g" alone is too cryptic.
    var pickerLabel: String {
        switch self {
        case .count: "Count"
        case .gram: "Grams (g)"
        case .kilogram: "Kilograms (kg)"
        case .ounce: "Ounces (oz)"
        case .pound: "Pounds (lb)"
        case .milliliter: "Milliliters (ml)"
        case .liter: "Liters (L)"
        case .fluidOunce: "Fluid ounces (fl oz)"
        case .package: "Package"
        case .unknown(let raw): raw.capitalized
        }
    }
}

#Preview("Create") {
    ItemFormView(mode: .create(locationID: UUID()), onSaved: {})
        .environment(\.repositories, .makePreview())
}

#Preview("Edit") {
    ItemFormView(
        mode: .edit(
            Item(
                locationID: UUID(),
                name: "Sourdough",
                quantity: 2,
                unit: .count,
                expiresAt: .now.addingTimeInterval(TimeInterval(60 * 60 * 24 * 3)),
                notes: "Last loaf in the freezer"
            )
        ),
        onSaved: {}
    )
    .environment(\.repositories, .makePreview())
}
