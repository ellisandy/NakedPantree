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
    /// **Notes shape (revisited again — issue #155 follow-up).** A user
    /// reported that the URL chip on the dedicated URL row of pushed
    /// reminders renders blank in Apple's Reminders.app, even though
    /// `EKReminder.url` is set on save (confirmed via `url-post-save`
    /// log) and even though the `nakedpantree://` scheme is registered
    /// (PR #168). A manually-pasted URL into the same field on a
    /// hand-edited reminder *does* persist + render — proving the
    /// field accepts the scheme, but our writes don't survive the
    /// iCloud round-trip (or the chip render) for reasons we haven't
    /// fully isolated.
    ///
    /// Workaround: embed the deep-link URL inline in the notes body.
    /// Reminders.app auto-detects URLs anywhere in notes and renders
    /// them as tappable chips inline — that path *does* persist for
    /// our writes (notes are surviving the round-trip; the original
    /// "Garage" body screenshot proved it). We still write
    /// `EKReminder.url` too so the dedicated-row chip lights up the
    /// day Apple/iCloud sorts out whatever's stripping it on our path.
    ///
    /// The current shape:
    /// ```
    /// <location>
    ///
    /// nakedpantree://item/<UUID>
    ///
    /// [NP-ID:<UUID>]
    /// ```
    /// - location body line drops if no location resolves
    /// - URL line is always present (item.id is always known)
    /// - sentinel always last for the parser anchor
    /// - blank lines between sections so each renders as its own
    ///   visual block
    ///
    /// The sentinel STRING (`[NP-ID:<UUID>]`) is unchanged — orphaning
    /// already-pushed reminders by changing the anchor would force
    /// duplicate creates. Same belt-and-suspenders rationale as before.
    ///
    /// `unitFormatter` is retained as a parameter for source/test
    /// compatibility but isn't referenced — units don't make it into
    /// the body.
    public static func payload(
        for item: Item,
        locationsByID: [Location.ID: Location],
        unitFormatter: @Sendable (Unit) -> String = defaultUnitFormatter
    ) -> ReminderPayload {
        _ = unitFormatter  // retained for API compatibility; see doc.
        let locationName = locationsByID[item.locationID]?.name
        let location = notesBody(locationName: locationName)
        let deepLink = ReminderTag.url(for: item.id)?.absoluteString
        let sentinel = ReminderTag.notesSentinel(for: item.id)
        // Order: location (optional) → deep-link URL → sentinel. Each
        // section separated by a blank line so Reminders.app treats
        // them as distinct visual blocks.
        let sections = [
            location.isEmpty ? nil : location,
            deepLink,
            sentinel,
        ].compactMap { $0 }
        let notes = sections.joined(separator: "\n\n")
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
