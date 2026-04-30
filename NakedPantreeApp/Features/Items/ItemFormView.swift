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
    /// Issue #134: target location. Seeded from the mode in `prefill()`
    /// (create → passed-in id; edit → existing item's id) and rebound
    /// by the location picker. Optional so the section's empty-load
    /// state and the picker's "no selection" rendering converge.
    @State private var selectedLocationID: Location.ID?
    /// Issue #134: locations the picker chooses from. Loaded once on
    /// appear via `repositories.location.locations(in:)`. Empty array
    /// (load not yet completed, or single-location household) hides
    /// the picker — there's nowhere to move the item to.
    @State private var locations: [Location] = []
    /// Issue #153: master toggle for the per-item restock threshold.
    /// `false` means "no auto-flag," equivalent to `restockThreshold == nil`.
    /// Splitting the toggle from the value keeps the UX simple — when the
    /// user flips the threshold off, we don't lose their last value.
    @State private var hasRestockThreshold: Bool = false
    /// Issue #153: the auto-flag-when-low value. Persisted as
    /// `Item.restockThreshold` only when `hasRestockThreshold == true`.
    /// Default seed of 1 — the most common reorder-on-last-one case.
    @State private var restockThreshold: Int32 = 1

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

                // Issue #153: per-item restock threshold. Toggle drives
                // the `nil` vs Int32 split — when off, the persisted
                // `Item.restockThreshold` is nil and the auto-flag rule
                // doesn't run. Threshold `0` is a valid value (flips at
                // zero, matching the existing out-of-stock signal but
                // explicit per-item).
                Section {
                    Toggle("Remind me when low", isOn: $hasRestockThreshold)
                        .accessibilityIdentifier("itemForm.restockThreshold.toggle")
                    if hasRestockThreshold {
                        Stepper(value: $restockThreshold, in: 0...9999) {
                            Text("Flag when quantity reaches \(restockThreshold)")
                        }
                        .accessibilityIdentifier("itemForm.restockThreshold.stepper")
                    }
                } header: {
                    Text("Restock alert")
                } footer: {
                    if hasRestockThreshold {
                        // Once-and-for-all explanation of the one-way
                        // semantic. Voice rule §10 — short, useful, no
                        // surprise behaviour for the user.
                        Text(
                            "We'll flag this item for restocking automatically. "
                                + "Clear the flag yourself when you've shopped — it never auto-clears."
                        )
                    }
                }

                // Issue #134: Location picker. Hidden when the
                // household has zero or one locations — single-
                // location users have nowhere to move to, and the
                // initial-load case (locations not yet fetched)
                // shouldn't flash an empty picker. The non-optional
                // tag below pairs with `Location.ID?` selection so
                // the no-selection state is representable.
                if locations.count > 1 {
                    Section("Location") {
                        Picker("Location", selection: $selectedLocationID) {
                            ForEach(locations) { location in
                                Label(location.name, systemImage: location.kind.systemImage)
                                    .tag(Optional(location.id))
                            }
                        }
                        .accessibilityIdentifier("itemForm.location.picker")
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
            .task { await loadLocations() }
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
        ItemFormSaveCoordinator.isValid(name: name)
    }

    /// Issue #134: canonical fallback for `selectedLocationID` if the
    /// `prefill()` seed is ever clobbered (e.g. an async race that
    /// nils `@State` between appear and save). Mirror of `prefill`'s
    /// initial assignment — keep them in sync if the mode seeding
    /// rules ever change.
    private func defaultLocationID() -> Location.ID {
        switch mode {
        case .create(let id): id
        case .edit(let item): item.locationID
        }
    }

    private func prefill() {
        // Issue #134: seed the location picker from the mode. Create
        // mode carries the entry-point's locationID (sidebar `+`
        // already resolved a target via the picker / 1-location
        // shortcut, or `ItemsView`'s per-location `+` passes its
        // current location). Edit mode prefills from the existing
        // item's current location.
        switch mode {
        case .create(let locationID):
            selectedLocationID = locationID
        case .edit(let item):
            selectedLocationID = item.locationID
            name = item.name
            quantity = item.quantity
            unit = item.unit
            if let expiry = item.expiresAt {
                hasExpiry = true
                expiresAt = expiry
            }
            notes = item.notes ?? ""
            // Issue #153: prefill the threshold UI from the existing
            // item. `nil` → toggle off, last-edited value re-seeded
            // to 1 (the default for first-time toggle-on).
            if let threshold = item.restockThreshold {
                hasRestockThreshold = true
                restockThreshold = threshold
            }
        }
    }

    /// Issue #134: fetches the current household's locations so the
    /// picker has options. Same swallow-on-fail pattern as
    /// `SidebarView.reload` / `LocationsSection.reload` — if the
    /// load errors, the picker stays hidden (single-location
    /// fallback) and save still works against `selectedLocationID`
    /// from `prefill()`.
    @MainActor
    private func loadLocations() async {
        do {
            let household = try await repositories.household.currentHousehold()
            locations = try await repositories.location.locations(in: household.id)
        } catch {
            // Silent — picker stays hidden, original locationID still
            // saves through fine.
        }
    }

    @MainActor
    private func save() async {
        // Issue #117: persistence + post-save scheduling now live in
        // `ItemFormSaveCoordinator`. The view stays responsible for the
        // SwiftUI surface (saving spinner, error banner, dismiss).
        // Issue #134: `selectedLocationID` is seeded by `prefill()`
        // before the form can be interacted with, so the `??` fallback
        // is defensive — if it ever fires, fall back to the mode's
        // canonical id (create's seed, or the item's current location
        // on edit).
        let resolvedLocationID = selectedLocationID ?? defaultLocationID()
        // Issue #153: collapse the toggle + stepper into the optional
        // domain field. Toggle off → nil; toggle on → the picker's
        // current value (including 0).
        let resolvedThreshold: Int32? = hasRestockThreshold ? restockThreshold : nil
        let draft = ItemFormDraft(
            locationID: resolvedLocationID,
            name: name,
            quantity: quantity,
            unit: unit,
            hasExpiry: hasExpiry,
            expiresAt: expiresAt,
            notes: notes,
            restockThreshold: resolvedThreshold
        )
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await ItemFormSaveCoordinator.save(
                mode: mode,
                draft: draft,
                repository: repositories.item,
                scheduler: notificationScheduler
            )
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
