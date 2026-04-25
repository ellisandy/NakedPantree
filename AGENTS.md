# Naked Pantree — Agent Guide

> For the ones-and-zeros developers. Read this before writing code in this
> repo.

This document is the operating manual for AI coding agents (Claude Code,
Cursor, Copilot Workspace, etc.) working on Naked Pantree. Humans, see
`DEVELOPMENT.md`. Architecture, see `ARCHITECTURE.md`. Brand voice and
copy rules, see `DESIGN_GUIDELINES.md`.

> **Status:** stub. Expanded as conventions get exercised on real PRs.
> Sections marked **TBD** will fill in alongside the first code that needs
> them.

---

## 1. Read these first, in this order

1. `ARCHITECTURE.md` — the shape of the system. Don't propose changes
   that contradict it without flagging them as a deviation.
2. `DESIGN_GUIDELINES.md` — voice, copy, color, logo. Every user-facing
   string passes the §10 checklist.
3. This file — local conventions and traps.

---

## 2. Hard rules

These are non-negotiable. If you find yourself wanting to break one, stop
and ask the user first.

- **`NakedPantreeDomain` does not import `CoreData` or `UIKit`.** It hosts
  value types, enums, and the repository **protocols**. Concrete Core Data
  implementations live in `NakedPantreePersistence`. See
  `ARCHITECTURE.md` §11.
- **All storage access goes through repository protocols.** No view
  model, feature, scheduler, or CLI command talks to `NSManagedObject`
  subclasses or `NSPersistentCloudKitContainer` directly.
- **No new entities without updating `ARCHITECTURE.md` §4** in the same
  PR. Schema drift is the single fastest way to break sync.
- **No new enum without an `unknown(String)` catch-all** and a raw-value
  stability test in `NakedPantreeDomain`. Breaking a raw value silently
  corrupts older clients via CloudKit.
- **Voice rules apply to every user-facing string** including notification
  bodies, empty states, errors, and accessibility labels. When in doubt,
  re-read §3 and §9 of `DESIGN_GUIDELINES.md`.
- **Don't add a backend.** v1.0 is iCloud-only. If you find yourself
  reaching for a server, you're solving the wrong problem.

---

## 3. Conventions

### File layout

Match `ARCHITECTURE.md` §3 exactly. New SwiftUI features go under
`NakedPantreeApp/Features/<FeatureName>/`. New repository protocols go
under `Packages/Core/Sources/NakedPantreeDomain/Repositories/`.

### Naming

**TBD** — concrete naming conventions (view suffix, view-model suffix,
repository naming) will be locked in alongside the first feature PR.

### Tests

- Every public function in `NakedPantreeDomain` has a Swift Testing case.
- Every repository protocol has both a Core Data-backed implementation
  test (against an in-memory store) and an in-memory mock used by app-level
  tests.
- UI tests are smoke-only; they exercise navigation, not business logic.

### Commits

- Commit messages explain *why*, not *what*. Imperative mood. One change
  per commit when practical.
- Never push to `main` directly. Open a PR; wait for Xcode Cloud green.

---

## 4. Things that look fine but aren't

A short list of traps that have already cost time:

- **Adding a unique constraint in the Core Data model.** CloudKit-mirrored
  stores reject these — the app will crash on first migration. Enforce
  uniqueness in code at insert time, on `id: UUID`.
- **Making a relationship required.** CloudKit needs every relationship
  optional and bidirectional. The model editor will let you do it; sync
  will reject it.
- **Using SwiftData.** It still doesn't expose the CloudKit shared
  database on iOS 26. Sharing is the product. Don't.
- **Reaching for `TabView` at the root.** Locations + Smart Lists *are*
  the navigation; see `ARCHITECTURE.md` §7.
- **Putting humor in error messages, permission requests, billing, or
  legal text.** See `DESIGN_GUIDELINES.md` §9 — those are off-limits.

---

## 5. When you're stuck

- If a change requires deviating from `ARCHITECTURE.md`, propose the
  deviation in the PR description and wait for sign-off rather than
  silently doing it.
- If you can't tell whether something is in scope for v1.0, check
  `ARCHITECTURE.md` §1 (Goals) and §12 (Future Considerations) before
  writing code.
- If `DESIGN_GUIDELINES.md` and a UX choice seem to conflict, the
  guidelines win.
