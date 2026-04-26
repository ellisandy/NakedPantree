# Naked Pantree — Roadmap

> Eight phases between an empty repo and a TestFlight build. One direction.

This document is the source of truth for **what** we build and **in what
order**. Granular work tracking happens in GitHub Issues; this doc gives
those issues a frame of reference and an exit gate.

For the architectural shape of each phase, see `ARCHITECTURE.md`. For
voice rules on every user-facing string we add, see `DESIGN_GUIDELINES.md`.

---

## How to use this

- **Phases are sequential**, with one explicit exception called out in
  Phase 5.
- **Each phase is a GitHub Milestone** with the same name and number.
  Issues are filed against a milestone; PRs close issues with `Closes #N`.
- **A phase isn't done until every exit criterion is met.** Adding more
  scope to a phase is fine; loosening exit criteria isn't.
- **`ARCHITECTURE.md` is amended in the same PR** as any change that
  alters the schema, an enum, or a repository protocol — see
  `AGENTS.md` §2.

---

## Phase 0 — Project scaffolding ✅

**Status:** Complete (merged on `main`).

**Goal:** an empty Xcode project that builds, tests, and lints cleanly.
Every later phase assumes this skeleton exists.

**In scope**

- Xcode workspace + iOS app target.
- Local SwiftPM `Packages/Core/` with two empty modules:
  `NakedPantreeDomain`, `NakedPantreePersistence`. App target depends on
  both.
- `.swift-format` and `.swiftlint.yml` at repo root, plus a pre-commit
  hook script under `scripts/`.
- GitHub Actions workflow that runs lint on every PR.
- App icon assets generated from the brand spec at all required sizes
  (`DESIGN_GUIDELINES.md` §7).
- Brand color tokens from `assets/brand/colors.json` exposed as a Swift
  enum or asset catalog.
- Hello-world `ContentView` that renders one branded color, proving the
  project is wired up.

**Out of scope**

- Any domain logic, persistence, navigation, or features.

**Exit criteria**

- [x] `xcodebuild` builds the app target on a clean checkout.
- [x] `swift test --package-path Packages/Core` passes (with a single
      placeholder test in each module).
- [x] `swift-format lint` and `swiftlint` exit zero on the repo.
- [x] `DEVELOPMENT.md` first-time setup section is filled in.

---

## Phase 1 — Single-user MVP (local only) ✅

**Status:** Complete (see sub-milestones below).

**Goal:** a usable inventory app on one device. No iCloud yet.

**In scope**

- Core Data model with the four entities and constraints from
  `ARCHITECTURE.md` §4 — local SQLite only, no CloudKit container.
- Repository protocols in `NakedPantreeDomain`; Core Data implementations
  in `NakedPantreePersistence`.
- `NavigationSplitView` shell with the three columns from `ARCHITECTURE.md` §7.
- CRUD: create / rename / delete `Location`s; create / edit / delete
  `Item`s with name, quantity, unit, expiry, notes.
- Search across all locations.
- Bootstrap: implicit default `Household` named "My Pantry" and a default
  `Location` named "Kitchen" on first launch.
- Voice rules applied to every string the phase introduces (empty states,
  toasts, accessibility labels).

**Out of scope**

- iCloud / CloudKit. Photos. Notifications. Sharing.

**Exit criteria**

- [x] App launches to the default household with one location.
- [x] User can add, rename, and delete locations and items with no
      crashes and no console warnings.
- [x] Search returns results across all locations.
- [x] Every user-facing string passes the `DESIGN_GUIDELINES.md` §10
      checklist.
- [x] Repository protocol tests pass with both the Core Data
      implementation and an in-memory mock.

**Sub-milestones**

The phase is large enough to land in chunks. Each row tracks one PR.

| # | Title | Status |
| --- | --- | --- |
| 1.1 | Domain types + repository protocols | ✅ Merged ([apps#10](https://github.com/ellisandy/NakedPantree/pull/10)) |
| 1.2a | Core Data stack + `Household` and `Location` repos | ✅ Merged ([apps#11](https://github.com/ellisandy/NakedPantree/pull/11)) |
| 1.2b | `Item` and `ItemPhoto` repos + cascade-delete tests | ✅ Merged ([apps#13](https://github.com/ellisandy/NakedPantree/pull/13)) |
| 1.3 | `NavigationSplitView` shell (sidebar / content / detail) | ✅ Merged ([apps#14](https://github.com/ellisandy/NakedPantree/pull/14)) |
| 1.4 | CRUD wiring for `Location`s and `Item`s | ✅ Merged ([apps#15](https://github.com/ellisandy/NakedPantree/pull/15)) |
| 1.5 | Search across locations + first-launch bootstrap | ✅ Merged ([apps#17](https://github.com/ellisandy/NakedPantree/pull/17)) |

> The split is not load-bearing — it's a guide. If a piece of work
> doesn't fit cleanly, retitle a row or add one. Don't force scope into
> the wrong row.

---

## Phase 2 — CloudKit sync (private database only) 🟡

**Status:** In progress.

**Goal:** two devices on the same iCloud account stay in sync.

**In scope**

- Replace plain Core Data stack with `NSPersistentCloudKitContainer`.
- Add the second `NSPersistentStoreDescription` for the shared store —
  wired but unused yet.
- `NSMergeByPropertyObjectTrumpMergePolicy` everywhere.
- Observer for `NSPersistentStoreRemoteChange` that drives view updates.
- Offline-write banner if the container reports account problems
  (`ARCHITECTURE.md` §5).
- Initial CloudKit schema deploy to the development environment.

**Out of scope**

- Sharing across iCloud accounts (Phase 3). Photos (Phase 5).

**Exit criteria**

- [ ] Two devices signed into the same iCloud account see inserts within
      ~5s of each other.
- [ ] Airplane-mode write replays cleanly on reconnect with no
      duplicates.
- [ ] No `unique constraint` errors at runtime — uniqueness is enforced
      in code at insert time.
- [ ] CloudKit dev schema matches the model exactly.

**Sub-milestones**

| # | Title | Status |
| --- | --- | --- |
| 2.1 | CloudKit container + entitlements + private-store assignment | ✅ Merged ([apps#24](https://github.com/ellisandy/NakedPantree/pull/24)) |
| 2.2 | `NSPersistentStoreRemoteChange` observer + view auto-refresh | ✅ Merged ([apps#25](https://github.com/ellisandy/NakedPantree/pull/25)) |
| 2.3 | Account-status banner | ✅ Merged ([apps#26](https://github.com/ellisandy/NakedPantree/pull/26)) |
| 2.4 | CloudKit dev schema deploy verification | 🟡 In review |

---

## Phase 3 — Sharing across households

**Goal:** two different iCloud accounts can collaborate on one
household.

**In scope**

- Create / fetch a `CKShare` rooted at the active `Household` record.
- `UICloudSharingController` SwiftUI bridge.
- Share-acceptance handler in the scene delegate
  (`windowScene(_:userDidAcceptCloudKitShareWith:)`).
- "Share Household" button in the Locations sidebar.
- Read/write across the shared store works, with the merge policy
  applied identically.

**Out of scope**

- Per-participant permission UI beyond what `UICloudSharingController`
  provides for free.
- Push-style change notifications (the existing `NSPersistentStoreRemoteChange`
  observer is enough).

**Exit criteria**

- [ ] Two devices on different iCloud accounts can both see and edit the
      same household after share acceptance.
- [ ] Removing a participant removes their access on the next launch.
- [ ] Manual checklist (`ARCHITECTURE.md` §11) entries 1–3 all pass.

---

## Phase 4 — Expiry notifications

**Goal:** users get a local notification before food expires.

**In scope**

- `UNUserNotificationCenter` permission flow gated to "first time the
  user sets `expiresAt`" (`ARCHITECTURE.md` §6).
- `NotificationScheduler` service with deterministic identifiers,
  observing both `NSManagedObjectContextDidSave` and
  `NSPersistentStoreRemoteChange`.
- Default lead time: 3 days before `expiresAt` at 9:00 local.
- Notification tap deep-links to the relevant `Item`.
- Notification body copy passes voice rules — plain, not heavy.

**Out of scope**

- Per-item lead-time customization. Server-side dedup. Critical alerts.

**Exit criteria**

- [ ] Setting an `expiresAt` on a real device schedules a local
      notification with the correct identifier and trigger date.
- [ ] Editing the expiry reschedules; clearing the expiry cancels.
- [ ] Tapping the notification opens the app on that item's detail.
- [ ] On two devices on the same household, both fire — accepted per
      `ARCHITECTURE.md` decisions log #5.

---

## Phase 5 — Photos

**Goal:** items can carry multiple photos that sync.

**In scope**

- Add `ItemPhoto` entity to the Core Data model and the CloudKit
  development schema.
- `imageData` with External Storage; inline `thumbnailData`.
- `PhotosPicker` integration plus camera capture bridge.
- Resize on import (max 2048px long edge).
- Item detail UI: primary photo prominent, secondary photos accessible
  in a clean way (per the review feedback on PR #5).
- Sync verification: thumbnail appears first on the receiving device,
  full asset shortly after.

**Out of scope**

- OCR. Barcode. Background blur. Photo deletion across all linked items.

**Exit criteria**

- [ ] Photo added on phone A appears on phone B with thumbnail in
      <10s, full asset shortly after.
- [ ] An item with five photos still loads instantly in list views
      (thumbnails only).
- [ ] CloudKit dev schema matches the model after adding `ItemPhoto`.

> **Phase ordering exception:** Phase 5 may be deferred until after
> Phase 6 if scope pressure demands. Photos are valuable but not on the
> critical path to "track inventory across two phones." Don't defer
> casually — it's a bait for Phase 7.

---

## Phase 6 — Cross-household views and adaptive polish

**Goal:** the app stops feeling location-shaped and starts feeling
household-shaped.

**In scope**

- "Expiring soon" view that spans all locations (per the review feedback
  on PR #5: cleanup is per-location, eat-soon is whole-household).
- Cross-household search surfaced from the sidebar.
- iPad three-column verification with rotation and split-view.
- Mac (Designed for iPad) verification — keyboard shortcuts, menu items
  that come for free, window resize.
- Empty states with full brand voice.

**Out of scope**

- Mac Catalyst. A separate macOS app. Watch app.

**Exit criteria**

- [ ] Expiring-soon view lists items from every location, ordered by
      expiry.
- [ ] App is usable on iPad in both orientations and on Mac at multiple
      window sizes.
- [ ] Empty states across the app pass voice rules and use icon + text
      (never color alone).

---

## Phase 7 — Pre-TestFlight hardening

**Goal:** ship a build to TestFlight internal testers.

**In scope**

- Xcode Cloud workflows: PR check (build + tests) and beta
  (build + tests + archive + upload).
- TestFlight internal group provisioned in App Store Connect.
- CloudKit schema **deployed to Production** (the gate from
  `DEVELOPMENT.md` §6).
- App Store Connect metadata stub — name, bundle id, default screenshots.
- Final manual QA pass against the full checklist
  (`ARCHITECTURE.md` §11).
- `DEVELOPMENT.md` Release section + Troubleshooting section filled in
  with whatever surfaces during the rollout.

**Out of scope**

- Public release. Marketing site. Privacy nutrition labels beyond what
  TestFlight requires.

**Exit criteria**

- [ ] An internal tester can install the build from TestFlight and use
      it end-to-end (add household, share, get an expiry notification,
      attach a photo).
- [ ] The full manual checklist passes on iPhone, iPad, and Mac.
- [ ] CloudKit Production schema matches Development schema exactly.

---

## After TestFlight

These are deliberately not v1.0. They live in `ARCHITECTURE.md` §12 and
will become their own phases when there's a reason to start.

- Personal macOS CLI tied to the future AI helper.
- AI ingredient-query integration.
- Apple Reminders ("add to grocery list") — manual, one-way to start.

---

## Decisions log (roadmap-shaped)

| # | Decision | Why |
| --- | --- | --- |
| 1 | Eight phases, not three | Each phase is a real exit gate with its own failure modes. Bigger phases hide regressions. |
| 2 | Sync (Phase 2) before Sharing (Phase 3) | Same-account sync is the cheaper test of the CloudKit stack; sharing layers on top. |
| 3 | Notifications (Phase 4) before Photos (Phase 5) | Notifications exercise the remote-change observer; photos add CKAsset complexity. |
| 4 | Photos (Phase 5) is the only phase with a documented defer-option | They're valuable but not on the critical path to "two phones, one inventory." |
| 5 | Cross-household views land in Phase 6, not Phase 1 | Phase 1 is the smallest thing that proves the data model. Holistic views need real data first. |

---

## Final thought

Each phase ends with a person able to use the app for something they
couldn't do before. If a phase doesn't pass that test, the phase is
wrong — split it.
