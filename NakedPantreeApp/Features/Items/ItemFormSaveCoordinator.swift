import Foundation
import NakedPantreeDomain

/// Plain-data snapshot of the editor's `@State` at save time. Keeps the
/// coordinator free of SwiftUI state types so tests can construct one
/// directly without `@State` ceremony.
///
/// `hasExpiry` + `expiresAt` mirror the form's "toggle off → no expiry"
/// affordance: the coordinator collapses them into the optional
/// `Item.expiresAt` exactly the way the view used to.
struct ItemFormDraft {
    /// Issue #134: target location for the item. On the create branch
    /// this seeds from the mode's `locationID` and may be reassigned
    /// by the form's location picker; on the edit branch this is the
    /// picker's current value, which can differ from the original
    /// item's `locationID` when the user is moving the item.
    var locationID: Location.ID
    var name: String
    var quantity: Int32
    var unit: NakedPantreeDomain.Unit
    var hasExpiry: Bool
    var expiresAt: Date
    var notes: String
    /// Issue #153: per-item restock threshold. `nil` means the user
    /// turned the toggle off (or never turned it on); the auto-flag-
    /// when-low rule in the repository skips items with a nil
    /// threshold. Threshold `0` is a valid non-nil value.
    var restockThreshold: Int32?

    /// Explicit init so the synthesized memberwise initializer doesn't
    /// force every call site to specify `restockThreshold` — the
    /// pre-#153 draft constructions (and pre-#153 tests) compile
    /// without edit and stay opt-in per the issue's "no surprise
    /// behavior on existing data" rule. SwiftLint's
    /// `implicit_optional_initialization` rule blocks the simpler
    /// `= nil` on the stored property, so the default lives on the
    /// init parameter instead.
    init(
        locationID: Location.ID,
        name: String,
        quantity: Int32,
        unit: NakedPantreeDomain.Unit,
        hasExpiry: Bool,
        expiresAt: Date,
        notes: String,
        restockThreshold: Int32? = nil
    ) {
        self.locationID = locationID
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.hasExpiry = hasExpiry
        self.expiresAt = expiresAt
        self.notes = notes
        self.restockThreshold = restockThreshold
    }
}

/// Save logic extracted from `ItemFormView` (issue #117). Lives here
/// rather than inside the view body so the create/edit branches, the
/// whitespace trimming, the empty-notes-to-nil collapse, and the
/// expiry-toggle-off-clears-date semantics can be unit-tested without
/// driving SwiftUI.
///
/// `@MainActor` because `NotificationScheduler` is `@MainActor`, and
/// the post-save `scheduleIfNeeded(for:)` call has to land on its
/// isolation. Tests run on the main actor too — `@Test` methods
/// inherit isolation from the enclosing type when none is specified,
/// and `@MainActor` calls are fine from a `@MainActor`-attributed
/// `@Test` function.
@MainActor
enum ItemFormSaveCoordinator {
    /// Whitespace-trim-then-empty check that mirrors what `save` does
    /// before persisting. Pulled out as a static so the view can use
    /// it for the save-button disable state and the predicate stays
    /// in lock-step with what the save itself enforces.
    static func isValid(name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Performs the save. Returns the persisted `Item` on success;
    /// rethrows whatever the repository raises on failure (the form
    /// surfaces it as the "Couldn't save. Try again." banner).
    ///
    /// On the create branch we mint a new `Item` with a fresh UUID and
    /// pass it to `repository.create`; on edit we copy the original
    /// (preserving `id`, `createdAt`, etc.) and only overwrite the
    /// editable fields. Either way, after a successful save we hand
    /// the persisted value to `scheduler.scheduleIfNeeded(for:)`,
    /// which handles both the "schedule with new expiry" and
    /// "cancel because expiry was cleared" cases idempotently.
    static func save(
        mode: ItemFormView.Mode,
        draft: ItemFormDraft,
        repository: any ItemRepository,
        scheduler: NotificationScheduler
    ) async throws -> Item {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNotes: String? = trimmedNotes.isEmpty ? nil : trimmedNotes
        let resolvedExpiry: Date? = draft.hasExpiry ? draft.expiresAt : nil

        let saved: Item
        switch mode {
        case .create:
            // Issue #134: the mode carries an initial `locationID` that
            // seeds the form's picker, but the picker's final value
            // (`draft.locationID`) is what gets saved — the user may
            // have changed it.
            let item = Item(
                locationID: draft.locationID,
                name: trimmedName,
                quantity: draft.quantity,
                unit: draft.unit,
                expiresAt: resolvedExpiry,
                notes: resolvedNotes,
                // Issue #153: pass the threshold through. The
                // repository's auto-flag rule will set
                // `needsRestocking` to true on insert if the initial
                // quantity is at or below threshold.
                restockThreshold: draft.restockThreshold
            )
            try await repository.create(item)
            saved = item
        case .edit(let original):
            var updated = original
            // Issue #134: edit mode now writes the picker's locationID
            // back, letting users reassign an item to a new location
            // without losing its history (id, createdAt, photos,
            // notes, expiry). `attachLocation` in the repository
            // re-points the relationship; cross-household moves are
            // not supported (see `Item.locationID` doc).
            updated.locationID = draft.locationID
            updated.name = trimmedName
            updated.quantity = draft.quantity
            updated.unit = draft.unit
            updated.expiresAt = resolvedExpiry
            updated.notes = resolvedNotes
            // Issue #153: edit mode rebinds the threshold too, so the
            // user can change the auto-flag value (or turn it off
            // entirely) without re-creating the item.
            updated.restockThreshold = draft.restockThreshold
            try await repository.update(updated)
            saved = updated
        }
        // Phase 4.1: schedule (or clear) the expiry notification off
        // the just-persisted item. `scheduleIfNeeded` handles the
        // nil-expiry case symmetrically with create vs edit — clearing
        // an expiry on edit cancels the pending request.
        await scheduler.scheduleIfNeeded(for: saved)
        return saved
    }
}
