import Foundation

/// Issue #155 — pure plan computation for the "Push to Reminders"
/// action. Given the items currently flagged for restocking and the
/// reminders that already exist in the chosen list, produce a
/// `ReminderPlan` of creates / title-updates / completions that the
/// adapter can apply mechanically.
///
/// The reconciler is deliberately field-agnostic about *how* a
/// snapshot got its `nakedPantreeID` — that's the adapter's job
/// (URL-primary, notes-sentinel fallback). Same shape lets the
/// reconciler stay fully testable without EventKit, and the URL-vs-
/// notes question stays a private adapter detail per the #155 spike's
/// findings.
///
/// **Reconciliation rules (per issue #155 spec).**
///
/// For each `Item` with `needsRestocking == true`:
/// - Existing reminder found and not completed → leave it. If the
///   item's name has changed since the last push, queue a
///   `UpdateTitle` op so the reminder catches up.
/// - Existing reminder found and completed → skip. The user already
///   crossed it off; we don't resurrect it. (If the flag stays true,
///   the user can clear-and-reflag in the app to push a fresh copy.)
/// - No existing reminder → queue a `Create` with title = item.name,
///   notes = `<location>\n\n[NP-ID:<UUID>]` (location-only body
///   above a blank-line-separated parser anchor; sentinel-only when
///   no location resolves), url = `nakedpantree://item/<UUID>`.
///
/// For each existing reminder whose `nakedPantreeID` resolves to an
/// `Item.id` that's **not** on the current Needs Restocking list (the
/// flag was cleared or the item was deleted):
/// - Not completed → mark completed. The user can see "ah, that one
///   came off the list" without us deleting their record.
/// - Already completed → no-op.
///
/// Reminders with `nakedPantreeID == nil` (hand-added by the user)
/// are ignored entirely. Keeping our hands off them is the whole
/// reason for the tag.
public enum RemindersReconciler {
    /// Default formatter for `Item.unit` inside a reminder's notes.
    /// Matches the App-target `Unit.displayLabel` (defined in
    /// `ItemsView.swift`) so the in-app and Reminders-side text agree.
    /// Lives in Domain because the reconciler runs here; duplicating
    /// the cases is cheap and avoids a cross-package import.
    public static let defaultUnitFormatter: @Sendable (Unit) -> String = { unit in
        switch unit {
        case .count: ""
        case .gram: "g"
        case .kilogram: "kg"
        case .ounce: "oz"
        case .pound: "lb"
        case .milliliter: "ml"
        case .liter: "L"
        case .fluidOunce: "fl oz"
        case .package: "pkg"
        case .unknown(let raw): raw
        }
    }

    /// Produce a plan from a current snapshot of items + existing
    /// reminders. Pure: same inputs → same outputs, no side effects,
    /// no time / IO / random / global state.
    ///
    /// `locationsByID` is the caller's responsibility — pass the
    /// already-loaded `Dictionary(uniqueKeysWithValues: ...)` from
    /// `LocationRepository.locations(in:)`. A missing entry means the
    /// notes line drops the location segment; we don't fabricate a
    /// placeholder.
    public static func plan(
        items: [Item],
        existing: [ReminderSnapshot],
        locationsByID: [Location.ID: Location],
        unitFormatter: @Sendable (Unit) -> String = defaultUnitFormatter
    ) -> ReminderPlan {
        let tagged = existing.taggedByItemID()
        let activeItemIDs = Set(items.map(\.id))

        var creates: [ReminderPlan.Create] = []
        var titleUpdates: [ReminderPlan.UpdateTitle] = []
        var completions: [ReminderPlan.MarkCompleted] = []

        for item in items {
            if let snapshot = tagged[item.id] {
                if snapshot.isCompleted {
                    // User already crossed it off — leave alone.
                    continue
                }
                if snapshot.title != item.name {
                    titleUpdates.append(
                        ReminderPlan.UpdateTitle(
                            calendarItemIdentifier: snapshot.calendarItemIdentifier,
                            newTitle: item.name
                        )
                    )
                }
            } else {
                creates.append(
                    ReminderPlan.Create(
                        payload: payload(
                            for: item,
                            locationsByID: locationsByID,
                            unitFormatter: unitFormatter
                        )
                    )
                )
            }
        }

        for snapshot in existing {
            // Untagged reminders (hand-added) are off-limits.
            guard let nakedPantreeID = snapshot.nakedPantreeID else { continue }
            // If the tagged ID still appears on the current restock
            // list, we already handled it above.
            if activeItemIDs.contains(nakedPantreeID) { continue }
            // Item came off the list. Mark complete unless already so.
            if !snapshot.isCompleted {
                completions.append(
                    ReminderPlan.MarkCompleted(
                        calendarItemIdentifier: snapshot.calendarItemIdentifier
                    )
                )
            }
        }

        return ReminderPlan(
            creates: creates.sorted { $0.payload.title < $1.payload.title },
            titleUpdates: titleUpdates.sorted {
                $0.calendarItemIdentifier < $1.calendarItemIdentifier
            },
            completions: completions.sorted {
                $0.calendarItemIdentifier < $1.calendarItemIdentifier
            }
        )
    }

    /// Build the outbound `ReminderPayload` for a given item. Public so
    /// tests can pin the payload shape (title / notes / url) directly,
    /// and so the adapter can reuse the encoder when the reconciler
    /// queues a create.
    ///
    /// **Notes shape (revisited).** Earlier the body led with quantity
    /// + unit + location (`"1 — Old Garage Pantry"`) and the sentinel
    /// went *first*, before the body. A user looking at the reminder
    /// in Apple's Reminders.app saw the `[NP-ID:UUID]` line as the
    /// primary content with a confusing `"1 — Old Garage Pantry"`
    /// underneath — quantity in our domain means "how many I have,"
    /// which has no useful interpretation as a shopping-list line.
    ///
    /// The current shape:
    /// - body = the location name only, when one resolves
    /// - sentinel goes at the *end* of the notes after a blank line
    /// - sentinel-only notes when no location resolves
    ///
    /// The sentinel STRING (`[NP-ID:<UUID>]`) is unchanged — it's the
    /// notes-fallback parser anchor and changing it would orphan
    /// already-pushed reminders. Only its placement moves.
    ///
    /// `unitFormatter` is retained as a parameter for source/test
    /// compatibility, but the new body doesn't reference units; tests
    /// can drop their formatter argument or keep passing the default.
    public static func payload(
        for item: Item,
        locationsByID: [Location.ID: Location],
        unitFormatter: @Sendable (Unit) -> String = defaultUnitFormatter
    ) -> ReminderPayload {
        _ = unitFormatter  // retained for API compatibility; see doc.
        let locationName = locationsByID[item.locationID]?.name
        let body = notesBody(locationName: locationName)
        let sentinel = ReminderTag.notesSentinel(for: item.id)
        let notes: String
        if body.isEmpty {
            notes = sentinel
        } else {
            notes = "\(body)\n\n\(sentinel)"
        }
        return ReminderPayload(
            title: item.name,
            notes: notes,
            url: ReminderTag.url(for: item.id),
            nakedPantreeID: item.id
        )
    }

    /// User-facing notes body — currently the trimmed location name,
    /// or `""` when no location resolves. Centralised so the format
    /// can be changed in one place without the test surface drifting
    /// out of sync.
    private static func notesBody(locationName: String?) -> String {
        locationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

extension Array where Element == ReminderSnapshot {
    /// Index by resolved `Item.id`, dropping untagged rows. If two
    /// snapshots tag the same item (rare; user duplicated it by hand
    /// after a push), the first wins — the second becomes "untagged"
    /// from the reconciler's point of view, and the cleanup pass
    /// either marks it completed or leaves it for the user. Either
    /// behavior is acceptable; surfacing the dup explicitly is YAGNI.
    fileprivate func taggedByItemID() -> [UUID: ReminderSnapshot] {
        var result: [UUID: ReminderSnapshot] = [:]
        for snapshot in self {
            guard let itemID = snapshot.nakedPantreeID else { continue }
            if result[itemID] == nil {
                result[itemID] = snapshot
            }
        }
        return result
    }
}
