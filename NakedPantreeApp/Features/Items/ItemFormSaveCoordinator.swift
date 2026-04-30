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
    var name: String
    var quantity: Int32
    var unit: NakedPantreeDomain.Unit
    var hasExpiry: Bool
    var expiresAt: Date
    var notes: String
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
        case .create(let locationID):
            let item = Item(
                locationID: locationID,
                name: trimmedName,
                quantity: draft.quantity,
                unit: draft.unit,
                expiresAt: resolvedExpiry,
                notes: resolvedNotes
            )
            try await repository.create(item)
            saved = item
        case .edit(let original):
            var updated = original
            updated.name = trimmedName
            updated.quantity = draft.quantity
            updated.unit = draft.unit
            updated.expiresAt = resolvedExpiry
            updated.notes = resolvedNotes
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
