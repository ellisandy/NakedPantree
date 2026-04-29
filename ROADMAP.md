# Naked Pantree — Roadmap

> Eleven phases between an empty repo and the App Store. One direction.
> Phases 0–7 took us through TestFlight; 8–11 take us from TestFlight
> to a public release.

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

## Phase 3 — Sharing across households ✅

**Status:** Complete (verified on real devices, see sub-milestones below).

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

- [x] Two devices on different iCloud accounts can both see and edit the
      same household after share acceptance.
- [x] Removing a participant removes their access on the next launch.
- [x] Manual checklist (`ARCHITECTURE.md` §11) entries 1–3 all pass.

**Sub-milestones**

| # | Title | Status |
| --- | --- | --- |
| 3.1 | `CKShare` creation + `UICloudSharingController` bridge + Share Household button | ✅ Merged ([apps#32](https://github.com/ellisandy/NakedPantree/pull/32)) |
| 3.2 | Share-acceptance handler (`UIApplicationDelegateAdaptor`) | ✅ Merged ([apps#33](https://github.com/ellisandy/NakedPantree/pull/33)) |
| 3.3 | Cross-store write routing (private vs shared on insert) + verification runbook | ✅ Merged ([apps#34](https://github.com/ellisandy/NakedPantree/pull/34)) |

---

## Phase 4 — Expiry notifications ✅

**Status:** Complete (verified on real devices, see sub-milestones below).

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

## Phase 5 — Photos ✅

**Status:** Complete (verified on real devices, see sub-milestones below).

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

## Phase 7 — Pre-TestFlight hardening ✅

**Status:** Complete. CI ships every `main` merge to TestFlight; the
internal-group install round-trips against production CloudKit.

**Goal:** ship a build to TestFlight internal testers.

**In scope**

- GitHub Actions workflows: existing `build-test.yml` (PR check, already
  lands) and a new `testflight-beta.yml` (archive + TestFlight upload on
  merge to `main`). One CI surface. See `ARCHITECTURE.md` §10 for the
  signing / API-key shape.
- App Store Connect record + TestFlight internal group + default metadata
  stub (name, bundle id, screenshots).
- Three repo secrets for the TestFlight upload:
  `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`,
  `APP_STORE_CONNECT_API_KEY`.
- CloudKit schema **deployed to Production** (the gate from
  `DEVELOPMENT.md` §6).
- Final manual QA pass against the full checklist
  (`ARCHITECTURE.md` §11).
- `DEVELOPMENT.md` Release section + Troubleshooting section filled in
  with whatever surfaces during the rollout.

**Out of scope**

- Public release. Marketing site. Privacy nutrition labels beyond what
  TestFlight requires.

**Exit criteria**

- [x] An internal tester can install the build from TestFlight and use
      it end-to-end (add household, share, get an expiry notification,
      attach a photo).
- [x] The full manual checklist passes on iPhone, iPad, and Mac.
- [x] CloudKit Production schema matches Development schema exactly.

**Known issues at close** (filed against post-Phase-7 work):

- [#67](https://github.com/ellisandy/NakedPantree/issues/67) — bootstrap
  creates a duplicate household on fresh install before CloudKit sync
  arrives. Eventually-consistent (`fetchHouseholdRow` sorts oldest-first
  so devices converge) but items added during the gap orphan. Must fix
  before App Store release.
- [#68](https://github.com/ellisandy/NakedPantree/issues/68) — local
  dev build and TestFlight build share bundle id `cc.mnmlst.nakedpantree`
  so they can't be installed side-by-side on the same device. Affects
  developer ergonomics only; no user-visible bug. Nice-to-have for
  post-Phase-7.

**Sub-milestones**

CI moved from Xcode Cloud to GitHub Actions (single platform, already
pays for the runner). 7.1 flips from `user`-owned to `agent`-owned —
workflow YAML lives in the repo. The remaining rows are still
Apple-web-UI work the agent can't drive: App Store Connect provisioning,
the production CloudKit schema deploy, and the manual checklist that
needs two real iCloud accounts. The **Owner** column makes the split
visible.

| # | Title | Owner | Status |
| --- | --- | --- | --- |
| 7.1 | `.github/workflows/testflight-beta.yml` — archive + TestFlight upload via App Store Connect API key on every `main` merge | agent | ✅ Merged ([apps#63](https://github.com/ellisandy/NakedPantree/pull/63), [apps#64](https://github.com/ellisandy/NakedPantree/pull/64), [apps#65](https://github.com/ellisandy/NakedPantree/pull/65)) |
| 7.2 | App Store Connect record + TestFlight internal group + bundle ID with Push / iCloud capabilities + Admin-role API key + three repo secrets | user | ✅ Complete (verified by [run 25011950721](https://github.com/ellisandy/NakedPantree/actions/runs/25011950721) — green end-to-end upload) |
| 7.3 | First green TestFlight upload from `main` that exercises every field of the dev CloudKit schema (gates 7.4) | user | 🟡 Upload landed; install on real device + exercise every field per `DEVELOPMENT.md` §5a step 1 still pending |
| 7.4 | CloudKit Production schema deploy via the CloudKit Console — one-way ratchet, must follow 7.3 | user | ⏳ Pending |
| 7.5 | Manual QA pass against `ARCHITECTURE.md` §11 checklist on iPhone, iPad, and Mac (Designed for iPad) — internal-group install, end-to-end | user | ⏳ Pending |
| 7.6 | `DEVELOPMENT.md` §6 (Release) and §7 (Troubleshooting) fill-ins — real failure modes that surface during 7.1–7.5 | agent | 🟡 In progress (§6 filled in 7.1; first three §7 entries land in this PR) |

> 7.6 lands as a series of small doc PRs threaded through the rest —
> not a one-shot at the end. The §6 / §7 TODO blocks come out as the
> user lands each step and reports back what surfaced.

---

## Phase 8 — TestFlight stability and cosmetic completeness ✅

**Status:** Complete. CI is on Node 24-compatible actions, the
bootstrap-races-sync fix shipped (real-device multi-device verification
still owed; see "Known issues at close" below), and the brand app icon
replaces the placeholder.

**Goal:** the TestFlight build is correct under multi-device install
and stops looking like a placeholder on the home screen.

**In scope**

- CI hygiene: GitHub Actions versions bumped past the Node 20 → Node 24
  deprecation deadline (June 2 2026 hard cutoff).
- Bootstrap fix so the second device on the same iCloud account
  doesn't create a duplicate `Household` before CloudKit sync arrives.
  Items added during the gap must not orphan.
- Brand app icon replaces the placeholder green tile so the
  TestFlight build's home-screen presence matches the rest of the
  brand.

**Out of scope**

- Settings UI for managing duplicate households created by older
  builds (one-time data hygiene, separate from the code fix).
- Wider visual brand pass — Phase 10.

**Exit criteria**

- [x] CI workflows use Node 24-compatible action versions; no
      deprecation warnings on PR runs.
- [x] Fresh-install of a second device tied to an existing iCloud
      account converges on the existing household within ~30s
      without creating a duplicate `CD_HouseholdEntity` row.
- [x] Items added on the second device immediately after launch
      survive CloudKit sync — they appear on both devices, not
      orphaned in a transient household.
- [x] App icon on the home screen and in App Store Connect matches
      the brand spec in `DESIGN_GUIDELINES.md` §7.

**Sub-milestones**

| # | Title | Issue | Status |
| --- | --- | --- | --- |
| 8.1 | GitHub Actions Node 24 compatibility (bump `actions/checkout` and friends) | [#57](https://github.com/ellisandy/NakedPantree/issues/57) | ✅ Merged ([apps#71](https://github.com/ellisandy/NakedPantree/pull/71)) |
| 8.2 | Bootstrap defers household creation until first remote-change tick or bounded timeout | [#67](https://github.com/ellisandy/NakedPantree/issues/67) | ✅ Merged ([apps#73](https://github.com/ellisandy/NakedPantree/pull/73)) |
| 8.3 | Replace placeholder app icon with brand icon | [#59](https://github.com/ellisandy/NakedPantree/issues/59) | ✅ Merged ([apps#72](https://github.com/ellisandy/NakedPantree/pull/72)) |

**Known issues at close** (real-device verification still owed; same
shape as Phase 7's framing):

- **8.2** — the bootstrap-defer fix is unit-test-covered but the
  multi-device fresh-install scenario from
  [#67](https://github.com/ellisandy/NakedPantree/issues/67) still
  needs hands-on verification: fresh-install on a second device tied
  to an existing iCloud account, watch CloudKit Console for at most
  one `CD_HouseholdEntity` row, immediately add an item on the new
  device and confirm it appears on the original device.
- **8.3** — springboard verification (home screen, Spotlight,
  Settings) per the issue's checklist still needs eyes on a real
  device. The simulator build confirms the asset catalog compiles;
  it doesn't confirm the icon looks right at every system size.

---

## Phase 9 — Notifications and quality-of-life polish

**Goal:** common interactions get faster; expiry notifications
become useful instead of annoying.

**In scope**

- Quantity adjusts inline on the item detail view without entering
  the edit form.
- Cold-start bootstrap shows progress feedback rather than a
  brand-color flash.
- Expiry notifications fire at a user-chosen time of day instead of
  the hard-coded 9:00 default.
- Same-day expiry notifications consolidate into a single summary
  notification rather than firing one per item.

**Out of scope**

- Per-item notification customization (lead time, time of day per
  item) — too much UI for the value at v1.0.
- Notification snooze / dismiss actions — separate decision.

**Exit criteria**

- [ ] User can `+1` / `−1` an item's quantity from
      `ItemDetailView` without going through `ItemFormView`.
- [ ] Cold-start launch shows a progress / loading state until
      `bootstrapComplete`, replacing the brand-color flash.
- [ ] Notification time-of-day is configurable (single setting,
      household-wide) and the scheduler honors it.
- [ ] Five items expiring on the same day produce one notification
      summarizing them, not five.

**Sub-milestones**

| # | Title | Issue | Status |
| --- | --- | --- | --- |
| 9.1 | Quantity inc / dec controls on `ItemDetailView` | [#51](https://github.com/ellisandy/NakedPantree/issues/51) | 🟡 In review |
| 9.2 | Launch / loading feedback during cold-start bootstrap | [#53](https://github.com/ellisandy/NakedPantree/issues/53) | 🟡 In review |
| 9.3 | Expiry-reminder time-of-day picker | [#55](https://github.com/ellisandy/NakedPantree/issues/55) | 🟡 In review |
| 9.4 | Roll up same-day expiries into a single summary notification | [#56](https://github.com/ellisandy/NakedPantree/issues/56) | 🟡 In review |

> Phase 9 ran the parallel-worktrees workflow: four agents in
> isolated worktrees, no per-sub-milestone PRs, integrated locally
> into a single PR. The shared file (`NotificationScheduler.swift`)
> was quarantined from the agents and wired centrally in the
> integration commit so 9.3's settings + 9.4's bundling both flow
> through one place. Each sub-branch's commit is preserved (cherry-
> picked, not squashed) so the PR is reviewable per sub-milestone.

---

## Phase 10 — Settings, brand pass, and developer ergonomics

**Goal:** household-level controls exist where users expect them,
the app's visual identity matches the brand, and the developer can
run dev + TestFlight side-by-side.

**In scope**

- Settings screen with household rename / share / leave / delete
  surfaces. The household-management UX gap surfaced during Phase 7
  diagnosis goes here.
- Brand color and personality pass — apply `DESIGN_GUIDELINES.md`
  §6 / §9 across the app's primary surfaces (the §52 research
  issue precedes implementation).
- Side-by-side dev + TestFlight install support via separate bundle
  id + CloudKit container for `Debug` config.
- Self-emission filter on `RemoteChangeMonitor` so local saves
  don't fire the observer twice (perf polish, not user-visible).

**Out of scope**

- Wholesale UI redesign — restraint per `DESIGN_GUIDELINES.md` §11.
  Brand pass means apply the existing tokens consistently, not
  invent new ones.
- Privacy / legal screens — Phase 11.

**Exit criteria**

- [ ] Settings screen reachable from the sidebar; household
      management actions all work end-to-end on a real device.
- [ ] App's typography, color, and copy match
      `DESIGN_GUIDELINES.md` § 5 / §6 / §3 across every screen
      that ships in v1.0.
- [ ] Local Xcode build installs side-by-side with the TestFlight
      build; the two have visually distinct icons / display names.
- [ ] `RemoteChangeMonitor` does not fire on saves originating
      from the same process.

**Sub-milestones**

| # | Title | Issue | Status |
| --- | --- | --- | --- |
| 10.1 | Settings screen with household management | [#60](https://github.com/ellisandy/NakedPantree/issues/60) | 🟡 In review |
| 10.2 | Brand color & personality pass — **research only** (implementation deferred to 10.5) | [#52](https://github.com/ellisandy/NakedPantree/issues/52) | 🟡 In review |
| 10.3 | Side-by-side dev + TestFlight install | [#68](https://github.com/ellisandy/NakedPantree/issues/68) | 🟡 In review |
| 10.4 | Filter self-emission from `RemoteChangeMonitor` via persistent-history tokens | [#28](https://github.com/ellisandy/NakedPantree/issues/28) | 🟡 In review |
| 10.5a | Brand-pass foundation #1 — Asset Catalog colorsets for the six brand primitives (light + dark + high-contrast variants) | [#80](https://github.com/ellisandy/NakedPantree/issues/80) | 🟡 In progress |
| 10.5b | Brand-pass foundation #2 — semantic role tokens (`Color+Semantic.swift`) | [#81](https://github.com/ellisandy/NakedPantree/issues/81) | 🟡 In progress |
| 10.5c | Brand-pass foundation #3 — apply `Color.surface` as the app canvas | [#82](https://github.com/ellisandy/NakedPantree/issues/82) | 🟡 In progress |
| 10.5d–10.5j | Brand-pass application long tail — badges, primary CTA buttons, branded empty states, sidebar tint, header strip, banner polish, dark-mode + Increase-Contrast QA. **Currently scoped as v1.1 work**, not pre-App-Store-submission, per `docs/BRAND_PASS_PROPOSAL.md` follow-ups #4–#10. Filed as work begins. | _per proposal_ | ⏳ Deferred to v1.1 |

> Phase 10.5's foundation (10.5a / 10.5b / 10.5c) lands as one
> integrated PR using the parallel-worktrees workflow's single-PR
> variant — three commits on a shared branch in dependency order
> (colorsets → semantic tokens → canvas application). The remaining
> seven follow-ups in the brand-pass proposal stay deferred to v1.1
> per Path B from the chat decision: enough brand foundation to ship
> a non-default-styled v1.0 to the App Store; full restyle is a v1.1
> follow-on.

> Phase 10 ran the parallel-worktrees workflow with **zero shared
> files** between the four sub-milestones — no integration commit
> needed (unlike Phase 9's `NotificationScheduler` quarantine). 10.2
> deliberately ships the research proposal only; the 10 prioritized
> implementation tasks listed in `docs/BRAND_PASS_PROPOSAL.md` get
> filed as follow-up issues and tracked under 10.5.

---

## Phase 11 — Pre-App-Store hardening

**Goal:** ship to the public App Store.

**In scope**

- App Store Connect metadata: full description, keywords, support
  URL, marketing URL, age rating.
- App Privacy "nutrition label" — covers iCloud, photos, no
  third-party data sharing.
- Real screenshots for each device family (iPhone 6.9", iPad 13",
  Mac via Designed-for-iPad).
- Final manual QA across iPhone / iPad / Mac on the production
  CloudKit environment.
- App Store submission and review response.

**Out of scope**

- Subscription or billing flows.
- Localization beyond English.

**Exit criteria**

- [ ] App Store Connect record is App-Store-Submission-ready: every
      required field populated, screenshots uploaded, privacy
      details accurate.
- [ ] Submitted build passes App Review (resubmission cycle if
      needed; the exit gate is acceptance, not first-submission).
- [ ] App is live on the public App Store.

**Sub-milestones**

Phase 11 is mostly user-driven (App Store Connect web UI + Apple
Review), with the agent prepping inputs and threading docs. Closer
to Phase 7's shape than to the parallel-worktrees workflow Phases
9–10 used. Hard sequential dependencies between rows: can't submit
without QA passing, can't QA without materials uploaded, can't
upload without drafts.

| # | Title | Owner | Status |
| --- | --- | --- | --- |
| 11.1a | App Store listing copy — name, subtitle, description, keywords, age rating, category (`docs/app-store-listing.md`) | agent | ✅ Merged ([apps#78](https://github.com/ellisandy/NakedPantree/pull/78)) |
| 11.1b | App Privacy questionnaire answers + `PrivacyInfo.xcprivacy` plist plan (`docs/app-store-privacy.md`) | agent | ✅ Merged ([apps#78](https://github.com/ellisandy/NakedPantree/pull/78)) |
| 11.1c | App Store screenshots pipeline — `SnapshotsUITests` produces App-Store-spec PNGs on demand (1320×2868 iPhone 6.9", 2064×2752 iPad 13"), uploaded as workflow artifact | agent | ✅ Merged ([apps#86](https://github.com/ellisandy/NakedPantree/pull/86)) |
| 11.1d | Ship `PrivacyInfo.xcprivacy` manifest (the code-side follow-up flagged in 11.1b §5 / §8) — `UserDefaults` reason `CA92.1`, empty `NSPrivacyCollectedDataTypes`, `NSPrivacyTracking=false` | agent | ✅ Merged ([apps#84](https://github.com/ellisandy/NakedPantree/pull/84)) |
| 11.1e | Declare `ITSAppUsesNonExemptEncryption=false` in `Info.plist` — skips App Store Connect's per-upload export-compliance questionnaire ([#76](https://github.com/ellisandy/NakedPantree/issues/76)). Pre-flight verified: no `CryptoKit` / `CommonCrypto` / third-party crypto in tree | agent | ✅ Merged ([apps#85](https://github.com/ellisandy/NakedPantree/pull/85)) |
| 11.2 | App Store Connect record setup — paste 11.1a metadata, fill 11.1b privacy answers, upload 11.1c screenshots, set age rating / category / regions, choose pricing (free, all countries) | user | ⏳ Pending |
| 11.3 | Final manual QA pass against `ARCHITECTURE.md §11` — two iCloud accounts, two devices, real iPhone + iPad + Mac (Designed for iPad). Sweeps up the still-pending real-device verification owed by Phases 8.2 / 8.3 / 9.{1..4} / 10.{1..4} | user | ⏳ Pending |
| 11.4 | App Store submission + review iteration — submit, respond to Apple Review feedback, ship code-side fixes if Apple flags anything (privacy manifest already shipped in 11.1d) | hybrid | ⏳ Pending |
| 11.5 | Release docs + retrospective — `DEVELOPMENT.md §6 / §7` final fills, ROADMAP close, tag `phase-11`, README version bump | agent | ⏳ Pending |

> 11.1's three doc-side pieces (a / b) ran in parallel agent
> worktrees alongside Phase 10. 11.1c initially deferred when the
> first agent ran out of budget; 11.1d / 11.1e / 11.1c picked up
> sequentially as small follow-up PRs once we needed each gap
> filled before submission. With 11.1c's pipeline producing
> exact-spec PNGs on demand, re-running the workflow against
> `main` at submission time is the recommended flow — Apple's
> specs change and the app's UI may shift between now and the
> upload window.

---

## Beyond v1.0

Once Phase 11 ships, anything still listed below earns its own phase
when there's a reason to start. Currently parked:

- Barcode scanning + Open Food Facts product lookup
  ([#4](https://github.com/ellisandy/NakedPantree/issues/4)).
- Grocery list integration — flag low-stock items, send to Apple
  Reminders ([#16](https://github.com/ellisandy/NakedPantree/issues/16)).
- Personal macOS CLI tied to the future AI helper
  (`ARCHITECTURE.md` §12).
- AI ingredient-query integration (`ARCHITECTURE.md` §12).
- OCR on photos for ingredient extraction
  (`ARCHITECTURE.md` §12).

---

## Decisions log (roadmap-shaped)

| # | Decision | Why |
| --- | --- | --- |
| 1 | Many small phases, not three big ones | Each phase is a real exit gate with its own failure modes. Bigger phases hide regressions. v1.0 lands at the end of Phase 11; Phases 8–11 came online as TestFlight feedback surfaced. |
| 2 | Sync (Phase 2) before Sharing (Phase 3) | Same-account sync is the cheaper test of the CloudKit stack; sharing layers on top. |
| 3 | Notifications (Phase 4) before Photos (Phase 5) | Notifications exercise the remote-change observer; photos add CKAsset complexity. |
| 4 | Photos (Phase 5) is the only phase with a documented defer-option | They're valuable but not on the critical path to "two phones, one inventory." |
| 5 | Cross-household views land in Phase 6, not Phase 1 | Phase 1 is the smallest thing that proves the data model. Holistic views need real data first. |

---

## Final thought

Each phase ends with a person able to use the app for something they
couldn't do before. If a phase doesn't pass that test, the phase is
wrong — split it.
