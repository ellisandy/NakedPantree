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

## Phase 2 — CloudKit sync (private database only) ✅

**Status:** Complete (verified on real devices, see sub-milestones below).

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

- [x] Two devices signed into the same iCloud account see inserts within
      ~5s of each other.
- [x] Airplane-mode write replays cleanly on reconnect with no
      duplicates.
- [x] No `unique constraint` errors at runtime — uniqueness is enforced
      in code at insert time.
- [x] CloudKit dev schema matches the model exactly.

**Sub-milestones**

| # | Title | Status |
| --- | --- | --- |
| 2.1 | CloudKit container + entitlements + private-store assignment | ✅ Merged ([apps#24](https://github.com/ellisandy/NakedPantree/pull/24)) |
| 2.2 | `NSPersistentStoreRemoteChange` observer + view auto-refresh | ✅ Merged ([apps#25](https://github.com/ellisandy/NakedPantree/pull/25)) |
| 2.3 | Account-status banner | ✅ Merged ([apps#26](https://github.com/ellisandy/NakedPantree/pull/26)) |
| 2.4 | CloudKit dev schema deploy verification | ✅ Merged ([apps#29](https://github.com/ellisandy/NakedPantree/pull/29)) |

---

## Phase 3 — Sharing across households 🟡

**Status:** In progress.

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

**Sub-milestones**

| # | Title | Status |
| --- | --- | --- |
| 3.1 | `CKShare` creation + `UICloudSharingController` bridge + Share Household button | ✅ Merged ([apps#32](https://github.com/ellisandy/NakedPantree/pull/32)) |
| 3.2 | Share-acceptance handler (`UIApplicationDelegateAdaptor`) | ✅ Merged ([apps#33](https://github.com/ellisandy/NakedPantree/pull/33)) |
| 3.3 | Cross-store write routing (private vs shared on insert) + verification runbook | ✅ Merged ([apps#34](https://github.com/ellisandy/NakedPantree/pull/34)) |

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

- [x] Setting an `expiresAt` on a real device schedules a local
      notification with the correct identifier and trigger date.
- [x] Editing the expiry reschedules; clearing the expiry cancels.
- [x] Tapping the notification opens the app on that item's detail.
- [x] On two devices on the same household, both fire — accepted per
      `ARCHITECTURE.md` decisions log #5.

**Sub-milestones**

| # | Title | Status |
| --- | --- | --- |
| 4.1 | `NotificationScheduler` + lazy permission + scheduling on item save/delete | ✅ Merged ([apps#35](https://github.com/ellisandy/NakedPantree/pull/35)) |
| 4.2 | Tap-to-deep-link routing (`UNUserNotificationCenterDelegate` + `RootView` navigation) | ✅ Merged ([apps#36](https://github.com/ellisandy/NakedPantree/pull/36)) |
| 4.3 | Auto-reschedule on `NSPersistentStoreRemoteChange` (complementary to issue #28) | ✅ Merged ([apps#37](https://github.com/ellisandy/NakedPantree/pull/37)) |
| 4.4 | Voice-review of notification copy + two-device verification runbook | ✅ Merged ([apps#38](https://github.com/ellisandy/NakedPantree/pull/38)) |

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

- [x] Photo added on phone A appears on phone B with thumbnail in
      <10s, full asset shortly after.
- [x] An item with five photos still loads instantly in list views
      (thumbnails only).
- [x] CloudKit dev schema matches the model after adding `ItemPhoto`.

> **Phase ordering exception:** Phase 5 may be deferred until after
> Phase 6 if scope pressure demands. Photos are valuable but not on the
> critical path to "track inventory across two phones." Don't defer
> casually — it's a bait for Phase 7.

**Sub-milestones**

| # | Title | Status |
| --- | --- | --- |
| 5.1 | App-layer image pipeline (`ImageIO` resize + thumbnail, EXIF-correct) | ✅ Merged ([apps#40](https://github.com/ellisandy/NakedPantree/pull/40)) |
| 5.2 | `PhotosPicker` + camera bridge + primary-photo header in `ItemDetailView` | ✅ Merged ([apps#41](https://github.com/ellisandy/NakedPantree/pull/41)) |
| 5.3 | Secondary photo strip + full-screen pager + delete + Make Primary (long-press drag deferred) | ✅ Merged ([apps#42](https://github.com/ellisandy/NakedPantree/pull/42)) |
| 5.4 | Two-device sync verification + dev schema deploy + `DEVELOPMENT.md` §5d runbook | ✅ Merged ([apps#43](https://github.com/ellisandy/NakedPantree/pull/43)) |

**Persistence layer status (sanity check, not a sub-milestone):** the
`ItemPhoto` Core Data entity, repository protocol/impl, and CRUD tests
all landed in Phase 1.2b — Phase 5 is pure UI + image-processing work.
The CloudKit dev-schema record type for `CD_ItemPhotoEntity` is created
lazily on the first photo write per `DEVELOPMENT.md` §5a step 4.

---

## Phase 6 — Cross-household views and adaptive polish ✅

**Status:** Complete (verified on real iPad and Mac per `DEVELOPMENT.md` §5e).

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

- [x] Expiring-soon view lists items from every location, ordered by
      expiry.
- [x] App is usable on iPad in both orientations and on Mac at multiple
      window sizes.
- [x] Empty states across the app pass voice rules and use icon + text
      (never color alone).

**Sub-milestones**

| # | Title | Status |
| --- | --- | --- |
| 6.1 | `ExpiringSoonView` (cross-location, sorted by expiry) + restore §8 missing-item routing | ✅ Merged ([apps#45](https://github.com/ellisandy/NakedPantree/pull/45)) |
| 6.2a | `RecentlyAddedView` (cross-location, sorted by `createdAt` desc) | ✅ Merged ([apps#46](https://github.com/ellisandy/NakedPantree/pull/46)) |
| 6.2b | Cross-household search surface from the sidebar (`.searchable(placement: .sidebar)`) | ✅ Merged ([apps#48](https://github.com/ellisandy/NakedPantree/pull/48)) |
| 6.3 | iPad / Mac (Designed for iPad) verification + `DEVELOPMENT.md` §5e runbook | ✅ Merged ([apps#50](https://github.com/ellisandy/NakedPantree/pull/50)) |
| 6.4 | Empty-state copy pass with brand voice | ✅ Merged ([apps#54](https://github.com/ellisandy/NakedPantree/pull/54)) |

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

**Sub-milestones**

Phase 7 is mostly Apple-web-UI work — Xcode Cloud workflows, App Store
Connect, CloudKit Console — that the agent can't drive directly. The
**Owner** column is the split: `user` rows happen in Apple's web tools
(no PR); `agent` rows are doc / config edits that follow once the user
reports back.

| # | Title | Owner | Status |
| --- | --- | --- | --- |
| 7.1 | Xcode Cloud workflows: PR check (build + tests) and `main`-merge beta (build + tests + archive + TestFlight upload) | user | ⏳ Pending |
| 7.2 | App Store Connect record + TestFlight internal group + default metadata stub (name, bundle id, screenshots) | user | ⏳ Pending |
| 7.3 | First TestFlight beta build that exercises every field of the dev CloudKit schema (gates 7.4) | user | ⏳ Pending |
| 7.4 | CloudKit Production schema deploy via the CloudKit Console — one-way ratchet, must follow 7.3 | user | ⏳ Pending |
| 7.5 | Manual QA pass against `ARCHITECTURE.md` §11 checklist on iPhone, iPad, and Mac (Designed for iPad) — internal-group install, end-to-end | user | ⏳ Pending |
| 7.6 | `DEVELOPMENT.md` §6 (Release) and §7 (Troubleshooting) fill-ins — workflow names, real failure modes that surface during 7.1–7.5 | agent | ⏳ Pending |

> 7.6 lands as a series of small doc PRs threaded through the rest —
> not a one-shot at the end. The TODO blocks in §6 / §7 come out as
> the user lands each step and reports what the names / failure modes
> actually were.

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
