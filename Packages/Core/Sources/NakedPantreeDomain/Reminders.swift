import Foundation

/// Issue #155 — value types for the one-way push from the
/// "Needs Restocking" smart list into Apple Reminders. All types here
/// are pure data; the reconciler in `RemindersReconciler.swift`
/// consumes them, the EventKit adapter in the App target produces the
/// snapshots and applies the plans.
///
/// Why these live in Domain rather than the App target:
///
/// - The reconciler is pure. Testing it must not require EventKit, an
///   `EKEventStore`, simulator entitlements, or pre-granted TCC.
/// - The adapter resolves "is this our reminder?" privately (URL field
///   primary, notes-sentinel fallback) and surfaces a single
///   `nakedPantreeID: UUID?` to the reconciler. That keeps the reconciler
///   field-agnostic — if Apple ever fixes the URL round-trip, the
///   adapter changes its parser, the reconciler doesn't move.

/// Lightweight description of a Reminders list (`EKCalendar`). The
/// adapter projects an `EKCalendar` into this so the picker UI can
/// render without importing EventKit. `id` is the raw
/// `EKCalendar.calendarIdentifier`; persistence uses it verbatim.
public struct RemindersListSummary: Sendable, Hashable, Identifiable {
    public let id: String
    public var title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// Sendable projection of an existing Reminders entry, captured at
/// reconciliation time. `nakedPantreeID` is the adapter's resolution
/// of "which Item.id, if any, does this reminder represent?" — `nil`
/// means the user wrote it by hand and the reconciler must leave it
/// alone.
public struct ReminderSnapshot: Sendable, Hashable {
    /// The `EKReminder.calendarItemIdentifier`. Stable across fetches
    /// in the same store; the adapter passes it back into `apply` to
    /// target a specific row for a title-update or completion mutation.
    public let calendarItemIdentifier: String
    /// Resolved by the adapter from `EKReminder.url` (primary) or a
    /// `[NP-ID:<UUID>]` substring in `EKReminder.notes` (fallback).
    /// `nil` for hand-added reminders the user owns directly.
    public let nakedPantreeID: UUID?
    public let title: String
    public let isCompleted: Bool

    public init(
        calendarItemIdentifier: String,
        nakedPantreeID: UUID?,
        title: String,
        isCompleted: Bool
    ) {
        self.calendarItemIdentifier = calendarItemIdentifier
        self.nakedPantreeID = nakedPantreeID
        self.title = title
        self.isCompleted = isCompleted
    }
}

/// Outbound payload for a reminder the reconciler wants the adapter to
/// create. Fields map 1:1 to `EKReminder` properties; the adapter is a
/// thin assignment loop.
///
/// The notes string already contains the `[NP-ID:<UUID>]` sentinel —
/// the reconciler is the encoder, the adapter writes it verbatim. Same
/// for `url`: the reconciler builds it via `ReminderTag.url(for:)` so
/// the adapter doesn't have to know the scheme.
public struct ReminderPayload: Sendable, Hashable {
    public let title: String
    public let notes: String
    public let url: URL?
    /// Surface the source `Item.id` for the adapter's logging /
    /// debugging — the reconciler already baked it into `notes` and
    /// `url`, but a typed field is friendlier than re-parsing.
    public let nakedPantreeID: UUID

    public init(title: String, notes: String, url: URL?, nakedPantreeID: UUID) {
        self.title = title
        self.notes = notes
        self.url = url
        self.nakedPantreeID = nakedPantreeID
    }
}

/// The reconciler's three operation buckets. Adapter applies them in
/// `creates → titleUpdates → completions` order. The buckets are
/// stable-sorted so the adapter's apply order is deterministic
/// regardless of how the input arrays were ordered — useful for
/// logging and for the snapshot-test acceptance criterion.
public struct ReminderPlan: Sendable, Hashable {
    public struct Create: Sendable, Hashable {
        public let payload: ReminderPayload
        public init(payload: ReminderPayload) { self.payload = payload }
    }

    public struct UpdateTitle: Sendable, Hashable {
        public let calendarItemIdentifier: String
        public let newTitle: String
        public init(calendarItemIdentifier: String, newTitle: String) {
            self.calendarItemIdentifier = calendarItemIdentifier
            self.newTitle = newTitle
        }
    }

    public struct MarkCompleted: Sendable, Hashable {
        public let calendarItemIdentifier: String
        public init(calendarItemIdentifier: String) {
            self.calendarItemIdentifier = calendarItemIdentifier
        }
    }

    public let creates: [Create]
    public let titleUpdates: [UpdateTitle]
    public let completions: [MarkCompleted]

    public init(
        creates: [Create] = [],
        titleUpdates: [UpdateTitle] = [],
        completions: [MarkCompleted] = []
    ) {
        self.creates = creates
        self.titleUpdates = titleUpdates
        self.completions = completions
    }

    /// `true` when the plan would not mutate any reminder. Callers use
    /// this to skip the apply round-trip and short-circuit straight to
    /// "nothing to push" UX (which can still be a useful confirmation
    /// in the post-push toast).
    public var isEmpty: Bool {
        creates.isEmpty && titleUpdates.isEmpty && completions.isEmpty
    }
}

/// Encoder + parser for the two NakedPantree-owned identity fields on
/// an `EKReminder`. Both encode the same `Item.id`; the adapter writes
/// both on create, reads URL-first / notes-fallback when projecting a
/// fetched reminder into a `ReminderSnapshot`.
///
/// The notes-sentinel fallback exists because Apple developer forums
/// (still unanswered as of iOS 18) report that `EKReminder.url` may
/// not round-trip via fetch — see `RemindersURLRoundTripSpike` for the
/// probe. Belt-and-suspenders: write both, read whichever comes back.
public enum ReminderTag {
    /// `nakedpantree://item/<UUID>` — the deep-link form. Survives sync
    /// (Apple's docs claim this), surfaces in Reminders.app as a tappable
    /// chip, and is rarely set by hand-added reminders. Primary key for
    /// reconciliation when present.
    public static let urlScheme = "nakedpantree"
    public static let urlHost = "item"

    /// Substring that bookends a UUID inside `EKReminder.notes`. The
    /// reconciler emits a notes string of the form:
    ///
    ///     [NP-ID:<UUID>]
    ///     <user-friendly text>
    ///
    /// — the sentinel on its own line lets the user keep editing the
    /// rest without breaking our parser. A user who deletes the line
    /// orphans the reminder (we'll create a new one on next push), but
    /// that's a rare edit and the recovery path is benign.
    public static let notesSentinelPrefix = "[NP-ID:"
    public static let notesSentinelSuffix = "]"

    /// Build the deep-link URL form. Returns `nil` only on a UUID that
    /// can't be expressed as a URL — which never happens for valid
    /// `UUID`s, but the optional propagates so callers don't have to
    /// force-unwrap. Callers use the returned URL as `EKReminder.url`.
    public static func url(for itemID: UUID) -> URL? {
        URL(string: "\(urlScheme)://\(urlHost)/\(itemID.uuidString)")
    }

    /// Build the notes-sentinel substring for an item id. Bare —
    /// callers append the user-friendly notes body after this.
    public static func notesSentinel(for itemID: UUID) -> String {
        "\(notesSentinelPrefix)\(itemID.uuidString)\(notesSentinelSuffix)"
    }

    /// Parse the URL form into an `Item.id`. Returns `nil` for any URL
    /// that doesn't match the scheme + host shape, or whose path
    /// segment isn't a parseable UUID. Hand-added reminders (the user
    /// dropped a `https://` link in the URL field) miss the scheme
    /// check and return `nil`, which is what we want.
    public static func itemID(fromURL url: URL?) -> UUID? {
        guard let url, url.scheme == urlScheme else { return nil }
        // `URL.path` for `nakedpantree://item/<UUID>` is `/<UUID>`.
        let trimmed = url.path.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
        return UUID(uuidString: trimmed)
    }

    /// Parse the notes-sentinel form. Searches anywhere in the string
    /// (not just the start) so a reminder the user has edited still
    /// matches as long as the sentinel line survives. Multiple
    /// sentinels match the first; production code only ever writes
    /// one, so the ambiguity is theoretical.
    public static func itemID(fromNotes notes: String?) -> UUID? {
        guard let notes else { return nil }
        guard let prefixRange = notes.range(of: notesSentinelPrefix) else {
            return nil
        }
        let afterPrefix = notes[prefixRange.upperBound...]
        guard let suffixRange = afterPrefix.range(of: notesSentinelSuffix) else {
            return nil
        }
        let candidate = String(afterPrefix[..<suffixRange.lowerBound])
        return UUID(uuidString: candidate)
    }

    /// Convenience that mirrors the adapter's resolution order: URL
    /// first, notes-sentinel fallback. Centralized so the precedence
    /// is documented in one place — flipping the priority later (if
    /// the URL field's behavior changes) is a one-line edit.
    public static func resolveItemID(url: URL?, notes: String?) -> UUID? {
        itemID(fromURL: url) ?? itemID(fromNotes: notes)
    }
}
