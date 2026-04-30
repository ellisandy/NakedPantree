import Foundation
import NakedPantreeDomain

/// Plain-data snapshot of `LocationFormView`'s editor state at save
/// time. Same role as `ItemFormDraft` — see that type for the rationale.
struct LocationFormDraft {
    var name: String
    var kind: LocationKind
}

/// Save logic extracted from `LocationFormView` (issue #117). The
/// shape mirrors `ItemFormSaveCoordinator` minus the notification
/// scheduler: locations don't carry expiries.
///
/// `@MainActor` is incidental here (no MainActor-isolated dependencies),
/// but kept consistent with `ItemFormSaveCoordinator` so callers don't
/// have to reason about whether the namespace they're using needs
/// hopping or not.
@MainActor
enum LocationFormSaveCoordinator {
    /// Same trim-then-empty predicate as the item form. Pulled out so
    /// the view's save-button disable state stays in lock-step with
    /// what the save itself enforces.
    static func isValid(name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Performs the save. Returns the persisted `Location`; rethrows
    /// repository errors so the form can surface its banner.
    static func save(
        mode: LocationFormView.Mode,
        draft: LocationFormDraft,
        repository: any LocationRepository
    ) async throws -> Location {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .create(let householdID):
            let location = Location(
                householdID: householdID,
                name: trimmedName,
                kind: draft.kind
            )
            try await repository.create(location)
            return location
        case .edit(let original):
            var updated = original
            updated.name = trimmedName
            updated.kind = draft.kind
            try await repository.update(updated)
            return updated
        }
    }
}
