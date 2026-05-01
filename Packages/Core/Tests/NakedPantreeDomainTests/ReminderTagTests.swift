import Foundation
import Testing
@testable import NakedPantreeDomain

/// Issue #155 — pin the URL + notes-sentinel encoder/decoder. The
/// reconciler relies on these helpers being symmetric: a value
/// encoded by `url(for:)` / `notesSentinel(for:)` must round-trip
/// through `itemID(fromURL:)` / `itemID(fromNotes:)`.
@Suite("ReminderTag")
struct ReminderTagTests {
    @Test("URL form round-trips an item id")
    func urlRoundTrips() throws {
        let id = UUID()
        let url = try #require(ReminderTag.url(for: id))
        #expect(url.scheme == "nakedpantree")
        #expect(ReminderTag.itemID(fromURL: url) == id)
    }

    @Test("Notes-sentinel round-trips an item id")
    func notesRoundTrips() {
        let id = UUID()
        let sentinel = ReminderTag.notesSentinel(for: id)
        #expect(ReminderTag.itemID(fromNotes: sentinel) == id)
    }

    @Test("Notes parser tolerates trailing user content after the sentinel")
    func notesWithTrailingBody() {
        let id = UUID()
        let sentinel = ReminderTag.notesSentinel(for: id)
        let notes = "\(sentinel)\n2 ct — Kitchen Pantry\nUser added a follow-up line."
        #expect(ReminderTag.itemID(fromNotes: notes) == id)
    }

    @Test("URL parser rejects unrelated schemes")
    func urlRejectsForeignScheme() {
        let foreign = URL(string: "https://example.com/some/uuid")
        #expect(ReminderTag.itemID(fromURL: foreign) == nil)
    }

    @Test("URL parser rejects malformed UUID path")
    func urlRejectsMalformedUUID() {
        let bad = URL(string: "nakedpantree://item/not-a-uuid")
        #expect(ReminderTag.itemID(fromURL: bad) == nil)
    }

    @Test("Notes parser returns nil on input with no sentinel")
    func notesRejectsMissingSentinel() {
        #expect(ReminderTag.itemID(fromNotes: "Just user text.") == nil)
        #expect(ReminderTag.itemID(fromNotes: nil) == nil)
        #expect(ReminderTag.itemID(fromNotes: "") == nil)
    }

    @Test("Resolution prefers URL over notes when both are present")
    func resolutionPrefersURL() throws {
        let urlID = UUID()
        let notesID = UUID()
        let url = try #require(ReminderTag.url(for: urlID))
        let notes = ReminderTag.notesSentinel(for: notesID)
        #expect(ReminderTag.resolveItemID(url: url, notes: notes) == urlID)
    }

    @Test("Resolution falls back to notes when URL is nil or unrecognized")
    func resolutionFallsBackToNotes() {
        let id = UUID()
        let notes = ReminderTag.notesSentinel(for: id)
        #expect(ReminderTag.resolveItemID(url: nil, notes: notes) == id)
        let foreignURL = URL(string: "https://example.com/")
        #expect(ReminderTag.resolveItemID(url: foreignURL, notes: notes) == id)
    }

    @Test("Resolution returns nil when neither field carries a tag")
    func resolutionAllNilReturnsNil() {
        let foreignURL = URL(string: "https://example.com/")
        #expect(ReminderTag.resolveItemID(url: foreignURL, notes: "user text") == nil)
        #expect(ReminderTag.resolveItemID(url: nil, notes: nil) == nil)
    }
}
