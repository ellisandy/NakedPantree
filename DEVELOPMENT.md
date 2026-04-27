# Naked Pantree — Development

> Get a working build. Run the tests. Ship to TestFlight.

This doc is for humans setting the project up locally. For the architectural
shape of the code, see `ARCHITECTURE.md`. For guidance aimed at AI coding
agents, see `AGENTS.md`. For voice and copy rules, see
`DESIGN_GUIDELINES.md`.

> **Status:** Phase 0 (project scaffolding) is in. The Xcode project is
> generated from `project.yml` via XcodeGen — the `.xcodeproj` itself is
> gitignored.

---

## 1. Prerequisites

| Requirement | Why |
| --- | --- |
| **macOS 15 or newer** on **Apple Silicon** | "Designed for iPad on Mac" requires Apple Silicon (`ARCHITECTURE.md` §10). |
| **Xcode 26 or newer** | iOS 26 SDK, Swift Testing default, current SwiftUI surface. |
| **Swift 6 toolchain** (bundled with Xcode 26) | Strict concurrency, `Sendable` repository protocols. |
| **XcodeGen** (`brew install xcodegen`) | Generates `NakedPantree.xcodeproj` from `project.yml`. |
| **swift-format** and **SwiftLint** (`brew install swift-format swiftlint`) | Pre-commit hook + CI lint. |
| **Apple Developer account** with CloudKit enabled | Free tier is fine for local dev; paid is required to push a TestFlight build. |
| **Two devices** (or one device + the simulator) | Sharing flows can't be exercised on a single CloudKit account from one process. See `ARCHITECTURE.md` §11. |

Optional but useful: a second iCloud account for the "different accounts,
share accepted" manual check.

---

## 2. First-time setup

```bash
# 1. Clone and enter the repo.
git clone <repo-url>
cd NakedPantree

# 2. Generate the Xcode project from project.yml.
xcodegen generate

# 3. Install the pre-commit hook (runs swift-format + swiftlint on staged files).
scripts/install-hooks.sh

# 4. Open the project.
open NakedPantree.xcodeproj
```

In Xcode:

1. Select the `NakedPantree` target → **Signing & Capabilities** → set your
   Development Team for the app, `NakedPantreeTests`, and
   `NakedPantreeUITests`. (XcodeGen leaves `DEVELOPMENT_TEAM` blank on
   purpose so it doesn't clobber your local config.)
2. Build & run (`Cmd+R`). You should see a Forest Green screen with
   "Naked Pantree — Pants optional inventory."

> CloudKit container setup, the **Bootstrap** scheme, and on-device
> testing requirements arrive in Phase 2 (sync). Phase 0 is local-only.

### Regenerating the project

`project.yml` is the source of truth. After editing it (or after pulling
a branch that did), regenerate:

```bash
xcodegen generate
```

The `.xcodeproj` is gitignored, so there's nothing to commit afterwards.

---

## 3. Day-to-day

### Build

In Xcode: `Cmd+B`. Headless:

```bash
xcodebuild build \
    -project NakedPantree.xcodeproj \
    -scheme NakedPantree \
    -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'
```

### Test

In Xcode: `Cmd+U` runs the app-target test bundles. Headless:

```bash
# App-target tests (Swift Testing + XCUITest).
xcodebuild test \
    -project NakedPantree.xcodeproj \
    -scheme NakedPantree \
    -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'

# Core package tests (fast, no simulator).
swift test --package-path Packages/Core
```

The intent (per `ARCHITECTURE.md` §11):

- **Package tests** (`NakedPantreeDomain`, `NakedPantreePersistence`) — fast,
  no I/O, run on every save.
- **App-target Swift Testing suites** — view models, scheduler, photo
  pipeline against in-memory repository mocks.
- **XCUITest smoke flows** — sidebar nav, item create, share sheet open.

### Lint and format

Configs at the repo root:

- `.swift-format` — formatting rules.
- `.swiftlint.yml` — lint rules.

The pre-commit hook (installed via `scripts/install-hooks.sh`) runs both
on staged Swift files. To run them manually before pushing:

```bash
./scripts/lint.sh
```

> ⚠️ **Don't run `swift-format lint --recursive --strict .` directly.**
> The Xcode-bundled `swift-format` (601.x / 602.x) has a real bug
> where `--recursive` silently misses per-file violations that the
> same binary catches when given the file directly. CI's `swift:6.0`
> container has a different build that doesn't have this bug, so a
> clean local recursive run can ship a PR that fails CI.
>
> `scripts/lint.sh` enumerates Swift files explicitly and lints each
> one, sidestepping the broken `--recursive` code path. Use it.

To auto-format the whole tree:

```bash
swift-format format --in-place --recursive .
```

CI runs both on every PR (`.github/workflows/lint.yml`).

---

## 4. Branch and commit policy

This is project-independent and locked in now.

- **Never push to `main` directly.** All changes land via PR.
- **Branch naming:** `<author-or-agent>/<short-kebab-summary>`. Examples:
  `ellisandy/share-sheet-bridge`, `claude/notification-scheduler`.
- **Commit messages:** imperative mood, explain *why* not *what*. One
  logical change per commit when practical. Match the existing style in
  `git log`.
- **Signing:** commits do not need to be GPG-signed for v1.0; revisit if
  the team grows.
- **PR size:** prefer small, reviewable PRs. If a PR touches more than
  ~400 lines of non-trivial code, split it.

### Pre-merge checklist

Before requesting review:

- [ ] `ARCHITECTURE.md` updated if the change adds/removes an entity, an
      enum, a repository protocol, or a CloudKit schema field.
- [ ] `DESIGN_GUIDELINES.md` voice rules applied to every user-facing
      string the PR adds or edits.
- [ ] Unit tests added or updated for any new logic in
      `NakedPantreeDomain`, `NakedPantreePersistence`, or app view models.
- [ ] `./scripts/lint.sh` exits clean. Don't substitute
      `swift-format lint --recursive .` — the Xcode-bundled binary's
      `--recursive` mode silently misses violations that CI catches.
      See §3.
- [ ] Full test suite passes the way CI runs it — *not* with
      `-only-testing`. `xcodebuild test ... -skip-testing:NakedPantreeUITests/SnapshotsUITests`
      catches UI smoke regressions a narrow filter would mask. See
      `.github/workflows/build-test.yml` for the exact invocation.
- [ ] Manual checklist (`ARCHITECTURE.md` §11) re-run if the PR touches
      sync, sharing, notifications, or photos.
- [ ] Screenshot (or short video) attached for any UI-visible change.

---

## 4a. Screenshots

App Store / TestFlight screenshots are generated headlessly from a seeded
fixture state — there's no manual capture pass per release. The pipeline
ships under issue [#12](https://github.com/ellisandy/NakedPantree/issues/12).

The app detects a `--snapshot-mode` launch argument and swaps its Core
Data stack for an in-memory bundle pre-populated by `SnapshotFixtures`.
`SnapshotsUITests` (in `NakedPantreeUITests`) launches with that flag,
navigates to each canonical surface, and attaches a PNG via
`XCUIScreen.main.screenshot()` + `XCTAttachment(lifetime: .keepAlways)`.

### Run locally

```bash
xcodebuild test \
    -project NakedPantree.xcodeproj \
    -scheme NakedPantree \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' \
    -only-testing:NakedPantreeUITests/SnapshotsUITests \
    -resultBundlePath Snapshots.xcresult \
    CODE_SIGNING_ALLOWED=NO

scripts/extract-screenshots.sh Snapshots.xcresult "iPhone 6.9" en-US
```

This writes PNGs to `screenshots/en-US/iPhone 6.9/` in the Fastlane
layout. Repeat for each device size (`iPad Pro 13-inch (M4)`,
`iPhone 16 Plus`, etc.) when App Store sizing requirements change.

### Run via GitHub Actions

The `Screenshots` workflow (`.github/workflows/screenshots.yml`) runs on
manual `workflow_dispatch` only — it never gates a PR. From the repo's
**Actions** tab, pick **Screenshots → Run workflow**. The job runs
across the configured device matrix and uploads the PNGs as artifacts
named `screenshots-<device-label>`.

The regular `Build & Test` workflow excludes `SnapshotsUITests` (via
`-skip-testing:NakedPantreeUITests/SnapshotsUITests`) so PR runs stay
fast.

---

## 5. Manual QA

The full per-release checklist lives in `ARCHITECTURE.md` §11. The short
version: two devices, sharing accepted, airplane-mode write, photo, Mac
build, notification tap.

If anything on that list becomes flaky, the answer is to push it down into
the automated layer by improving the protocol abstraction, not to add
another manual step.

---

## 5a. Phase 2 — CloudKit dev schema verification

A one-time verification that flips Phase 2 from "code lands" to
"sync actually works." Prerequisite: [#23](https://github.com/ellisandy/NakedPantree/issues/23)
done — the iCloud container exists in the developer portal and the
App ID has CloudKit + Push Notifications enabled.

### 1. Single-device dev schema population

The CloudKit dev schema is **not deployed by hand**.
`NSPersistentCloudKitContainer` populates it automatically the first
time the app writes against a real iCloud account. To trigger it:

1. Open the simulator (`iPhone 17 Pro Max` is what CI uses; any device
   works) → Settings → Apple Account → sign in with a real iCloud
   account. A dedicated test account is fine.
2. Run the app from Xcode (Debug → Cmd-R). Watch the Xcode console for
   `CoreData+CloudKit` initialisation logs and confirm there's no
   `Failed to initialise CloudKit Schema` line.
3. Add a location, an item, and edit the item — three writes, three
   record types.
4. Open the [CloudKit Console](https://icloud.developer.apple.com/dashboard),
   pick `iCloud.cc.mnmlst.nakedpantree`, **Schema → Record Types**.
   Verify all four exist with the `CD_` prefix Core Data adds:
   - `CD_HouseholdEntity`
   - `CD_LocationEntity`
   - `CD_ItemEntity`
   - `CD_ItemPhotoEntity` (created lazily once a photo is added —
     skip until Phase 5)
5. Spot-check a record type's fields against the model in
   `Packages/Core/Sources/NakedPantreePersistence/Model/NakedPantree.xcdatamodeld/`
   — `CD_<attr>` per attribute. CloudKit-mirrored attributes are
   optional or have a default per the §4 rule; relationships are
   optional both directions per the §5 rule.

If the schema doesn't appear within ~30s of a write, the typical
causes are:

- App ID's CloudKit container assignment didn't save in the portal.
  Re-check [#23](https://github.com/ellisandy/NakedPantree/issues/23)
  step 2.
- Provisioning profile is stale. In Xcode: Signing & Capabilities →
  click the team picker and pick again to force a regenerate.
- Simulator isn't actually signed in. The account-status banner
  (`AccountStatusBanner`, Phase 2.3) makes this loud.

### 2. Two-device sync verification

The Phase 2 exit criteria require this on real devices, not just the
simulator. With two devices on the same iCloud account:

- Add an item on phone A; phone B sees it within ~5s (foregrounded).
- Edit on phone A; phone B reflects the edit. Repeat for delete.
- Phone A in airplane mode → write → re-enable network → no duplicates.
- Cause a conflict (edit `quantity` on both phones while both offline,
  reconnect) → last write wins per `ARCHITECTURE.md` §5.

Tick the boxes in ROADMAP.md Phase 2 *exit criteria* once each
passes; mark Phase 2 ✅ when all four are green.

### 3. Production schema deploy gate

The dev schema deploy above only populates **development**. Production
deploy is a separate, deliberate step — covered in §6 (Release) and
gated behind a TestFlight build that exercises every field. Don't
deploy production until then; it's a one-way ratchet that's annoying
to roll back.

---

## 5b. Phase 3 — Sharing verification

Two-device, two-account verification of the share flow that landed
in Phase 3.1 / 3.2 / 3.3. Prerequisite: a second iCloud account on a
second physical device, both signed into the developer team
provisioning these builds.

### 1. Send the share

On phone A (account A):

1. Launch the app, add a few items so the share has content.
2. Sidebar toolbar → **Share Household** (the
   `person.crop.circle.badge.plus` icon next to `+`).
3. `UICloudSharingController` presents. Pick a transport
   (Messages is fastest for testing) and invite the email address
   tied to account B.
4. Confirm the share appears in the [CloudKit Console](https://icloud.developer.apple.com/dashboard)
   under the `iCloud.cc.mnmlst.nakedpantree` container's
   `cloudkit.share` records, scoped to phone A's user record.

### 2. Accept on the second device

On phone B (account B):

1. Open the invite link from Messages / Mail.
2. iOS may show a "Choose App" prompt — pick Naked Pantree.
3. `application(_:userDidAcceptCloudKitShareWith:)` fires; the
   shared household imports into the local shared store.
4. The sidebar should now show phone A's locations (after the
   `RemoteChangeMonitor` debounce settles, ~1-2s).
5. Add an item on phone B → it should appear on phone A within
   ~5s. Same for edits and deletes.

### 3. Phase 3 exit criteria

Tick these in `ROADMAP.md` Phase 3 once each passes on real devices:

- Two devices on different iCloud accounts both see and edit the
  same household.
- Edits round-trip in both directions within ~5s.
- Removing a participant (via the share controller's "Stop
  Sharing") removes their access on the next launch — verifies via
  the `cloudSharingControllerDidStopSharing` delegate path.

### Failure modes

- **Phone B sees nothing after accepting.** Check Xcode console
  on phone B for `acceptShareInvitations` errors. The most common
  is "shared store unavailable" — the shared store description in
  `CoreDataStack.cloudKitContainer(name:)` failed to load. Re-check
  the App ID's CloudKit capability in the developer portal.
- **Phone B sees the share but can't edit.** Check the share's
  permission level in the controller — defaults to read-only. Set
  to read-write before sending.
- **Phone B sees a `"Kitchen"` location appear on phone A out of
  nowhere.** That's a Bootstrap-into-shared-store regression.
  `BootstrapService` must call `ensurePrivateHousehold()`, not
  `currentHousehold()`. See `BootstrapService.swift`.

---

## 5c. Phase 4 — Expiry notification verification

Two-device verification of the notification scheduler that landed in
Phase 4.1 / 4.2 / 4.3. Prerequisite: §5b (sharing) passing — both
devices already round-trip writes against the same household.

Notifications are local (`UNUserNotificationCenter`); there is no
push channel to test. What we're verifying is that each device's
observer sees a remote write and reschedules its own pending request.

### 1. Single-device permission and schedule

On phone A:

1. Launch the app. Add an item with an expiry **more than 3 days
   out** (5+ is the easy-to-reason-about case). At exactly 3 days
   the 9am trigger may already be in the past relative to "now"
   and the scheduler silently skips (`expiryNotificationTriggerDate`
   returns `nil` for past targets).
2. Tap **Add**. The `requestAuthorization` prompt fires the first
   time. Tap **Allow**. Per `ARCHITECTURE.md` §8 the prompt is lazy
   — if it appeared at launch instead of on save, that's a regression.
3. There is no user-visible inspector for `pendingNotificationRequests()`.
   Verify scheduling end-to-end with a fast-fire test instead:
   - Pick an item whose expiry is **3 days + ~5 minutes** out.
   - Background the app and lock the device.
   - Wait for the lock-screen banner. Title is the item name; body
     reads `"Expires in 3 days."`. If the body says "in 4 weeks"
     or anything anchored to save time instead of fire time,
     that's the regression `NotificationBodyCopyTests.bodyAnchoredToTriggerDate`
     catches — flag it.
4. Cheap permission-state confirmation: Settings → Notifications →
   Naked Pantree → authorization should be **Allow** with **Show
   Previews** at *Always* (or *When Unlocked*).

### 2. Reschedule and cancel

The cheapest verification is end-to-end through the lock-screen
banner (above). The two flows below confirm the *cancel* paths,
which a fast-fire test won't catch on its own:

1. Schedule a fast-fire item (as above), then before it fires,
   edit the expiry to push it past tomorrow's 9am. The original
   banner must **not** appear at the original trigger time. The
   identifier is deterministic (`"item.<uuid>.expiry"`), so the
   pending request is replaced rather than duplicated.
2. Schedule a fast-fire item, then before it fires, edit the item
   and **clear** the expiry toggle → save. The banner must not
   appear. The 4.1 form callback handles the cancel directly; the
   4.3 resync sweep also catches it on the next
   `RemoteChangeMonitor.changeToken` tick.
3. Schedule a fast-fire item, then before it fires, delete the
   item. The banner must not appear.

### 3. Tap-to-deep-link

Reuse the §1 fast-fire item — when it actually rings, you'll
have a real notification to tap.

1. With the §1 fast-fire item still scheduled, background the app
   and lock the device.
2. When the banner fires, tap it (or swipe-to-open from the lock
   screen).
3. The app opens on the item's detail view. Sidebar selects the
   item's location; content selects the item.
4. Negative test: schedule a fresh fast-fire item, then before it
   fires delete the item from phone B (or the CloudKit Console).
   When the banner appears on phone A, tap it. The "That item is
   gone." alert fires; the user lands on whatever surface they
   were last viewing.

### 4. Two-device firing

Phones A and B sharing the same household per §5b. Both phones
must have launched the app at least once with notification
permission granted — pending requests are scheduled on each
device locally; a phone that never ran resync has no requests to
fire (see Failure modes).

1. On phone A, add an item with a fast-fire expiry (3 days + ~5
   minutes out per §5c step 1).
2. On phone B, wait ~5s, then confirm the new item appears in
   the relevant location list. Item appearing = `RemoteChangeMonitor`
   ticked → resync ran → pending request scheduled. Tying
   verification to user-visible state avoids guessing about
   internal timing.
3. Background both phones. Wait for the trigger time. Both
   devices fire the banner. Per `ARCHITECTURE.md` decisions log
   #5 this is intentional — server-side dedup would require
   infrastructure we don't have.
4. Edit the expiry on phone A. Wait ~5s, confirm the edit shows
   on phone B's item detail. The pending request on phone B
   reschedules on the same `changeToken` tick.
5. Delete the item on phone A. Wait ~5s, confirm phone B's row
   disappears. The pending request on phone B cancels via the
   resync sweep's stale-identifier diff.

### 5. Phase 4 exit criteria

Tick these in `ROADMAP.md` Phase 4 once each passes on real devices:

- [ ] Setting an `expiresAt` on a real device schedules a local
      notification with the correct identifier and trigger date.
- [ ] Editing the expiry reschedules; clearing the expiry cancels.
- [ ] Tapping the notification opens the app on that item's detail.
- [ ] On two devices on the same household, both fire.

### Failure modes

- **Permission prompt appears at cold launch instead of on first
  save.** Either the form-save path lost its lazy gate, or
  `NotificationScheduler.resync` is calling
  `ensureAuthorization` instead of bailing on `.notDetermined`
  up front. Check `resync(currentItems:)` — the gate must short-
  circuit before the per-item loop.
- **Body reads "in 4 weeks" instead of "in 3 days".** The body
  is computed against save time instead of trigger time.
  `expiryNotificationBodyCopy(expiresAt:relativeTo:)` must take
  the trigger date as `relativeTo`. Regression covered by
  `NotificationBodyCopyTests`.
- **Phone B fires nothing after a phone-A write.** Most common:
  phone B never ran the app with notification permission granted
  — pending requests are scheduled per-device, and `resync`
  needs at least one foreground launch to populate them. Less
  common: `RemoteChangeMonitor` isn't wired (the production
  `init(coordinator:)` branch in `NakedPantreeApp.swift`, not
  the no-op `init()`). The simulator with no iCloud account
  uses the no-op variant on purpose.
- **Tap on a deleted item shows nothing.** The "That item is gone."
  alert is gated on `bootstrapComplete`. If the cold-launch path
  applied the deep link before bootstrap finished, the lookup
  would short-circuit. `RootView`'s `.task` clears
  `pendingItemID` before awaiting `applyDeepLink`; if a refactor
  reorders that, the regression would surface here.
- **Both devices fire, but one has the wrong title.** Title is
  the item's `name` field at scheduling time on each device.
  A diverged name means the resync sweep didn't pick up the
  remote rename — check `RemoteChangeMonitor.changeToken` is
  ticking on the affected device.

---

## 5d. Phase 5 — Photo sync verification

Two-device verification of the photo pipeline that landed in Phase
5.1 / 5.2 / 5.3. Prerequisite: §5b (sharing) passing — both devices
already round-trip writes against the same household.

The key asymmetry to keep in mind: `ItemPhoto.thumbnailData` is an
inline ~64 KB JPEG that CloudKit syncs as a regular attribute,
while `ItemPhoto.imageData` has External Storage enabled and is
promoted to a `CKAsset` on the wire. *Expected behavior:*
thumbnails arrive on the receiving device on the next
`RemoteChangeMonitor` tick; the full asset follows once CloudKit
completes the asset transfer (which can be tens of seconds on a
cellular link or a large photo). The exit criteria allow this gap
by design — the first run of this runbook is the verification
that the expected behavior actually holds.

### 1. Single-device dev schema population

Like the entities in §5a, `CD_ItemPhotoEntity` is **not deployed by
hand** — `NSPersistentCloudKitContainer` populates it the first
time the app writes a photo against a real iCloud account. To
trigger:

1. On phone A (real device, signed into iCloud), launch the app
   and open any item's detail view.
2. Toolbar → **Add Photo** → **Choose from Library**. Pick a
   photo. The app first prompts for camera (lazily, only if you
   pick **Take Photo** instead) — the library path skips that
   prompt entirely because `PhotosPicker` is out-of-process.
3. Open the [CloudKit Console](https://icloud.developer.apple.com/dashboard),
   pick `iCloud.cc.mnmlst.nakedpantree`, **Schema → Record Types**.
   Confirm `CD_ItemPhotoEntity` exists with the expected fields:
   - `CD_id` (String / UUID)
   - `CD_imageData` (Asset)
   - `CD_thumbnailData` (Bytes)
   - `CD_caption` (String, optional)
   - `CD_sortOrder` (Int64)
   - `CD_createdAt` (Date / Timestamp)
4. Confirm `CD_imageData` shows as an **Asset** field in the
   schema, not Bytes. `NSPersistentCloudKitContainer` only
   promotes a Core Data Binary attribute to `CKAsset` when the
   model has External Storage enabled — if the field appears as
   Bytes, the storage flag is off and the schema needs the
   model fix before redeploying.

If the record type doesn't appear within ~30s of the photo write,
re-check the §5a failure modes — same App ID / container assignment
issues bite here.

### 2. Single-device add / edit / delete

Still on phone A:

1. Open the Cheese (or any) item detail. Add three photos via
   library picker. Verify after each save:
   - Primary header shows the photo with the lowest `sortOrder`
     — i.e. the first photo added (sortOrders 0, 1, 2 in add
     order; first add stays primary until someone runs Make
     Primary).
   - Strip below header appears once `photos.count >= 2`.
2. Tap the primary header → `PhotoPagerView` opens at index 0.
   Swipe through all three. Page-dot indicator updates.
3. Long-press a strip thumbnail → context menu shows
   **Make Primary** + **Delete**. Tap **Make Primary** on the
   third photo (the one currently rightmost in the strip). The
   header should swap to that photo within ~200ms; the previously-
   primary photo drops back into the strip.
4. Open the pager, tap the trash icon. Pager dismisses; the
   deleted photo is gone from the strip. Confirm the next photo
   in sortOrder ascending becomes primary if you deleted the
   primary.

### 3. Two-device sync (thumbnail-first, full asset shortly after)

Phones A and B sharing the same household per §5b. Both apps
foregrounded:

1. On phone A, add a photo to an item.
2. On phone B, watch the same item's detail view. Within ~5s
   (after the `RemoteChangeMonitor` debounce) the photo should
   appear — but may render initially with the small thumbnail
   blob and only swap to the full-resolution image after the
   `CKAsset` transfer completes. Phase 5 exit criterion #1 allows
   this gap.
3. Make Primary on phone A → on phone B, the same photo should
   move into the header on the next remote-change tick (~5s).
4. Delete on phone A → on phone B the photo disappears from the
   strip on the next remote-change tick. If the deleted photo was
   primary, the next-lowest sortOrder photo becomes the new header
   on B (auto-promote falls out of the natural ascending sort).

### 4. Five-photo performance check

Phase 5 exit criterion #2: an item with five photos still loads
instantly in list views (thumbnails only).

1. On phone A, add five photos to a single item.
2. Force-quit the app (swipe up).
3. Cold-launch. Navigate Kitchen → tap into the five-photo item.
4. Detail view should appear without visible hitch. The strip
   reads `thumbnailData` (~64 KB each, decoded inline) — five
   thumbnails total ~320 KB of decoded `UIImage` memory. The
   primary header reads the full-resolution `imageData` — that's
   a single ~3 MB decode, which is fine for one image per
   surface.
5. Open the pager — swipe through all five. Each page eagerly
   decodes its full-resolution `imageData`, so total resident
   memory while the pager is open is ~15 MB. Acceptable for v1.0;
   if a real-device hitch shows up, the fix lives at
   `PhotoPagerView` (per-page `.onAppear` decode + `.onDisappear`
   release).

### 5. Phase 5 exit criteria

Tick these in `ROADMAP.md` Phase 5 once each passes on real
devices:

- [ ] Photo added on phone A appears on phone B with thumbnail in
      <10s, full asset shortly after.
- [ ] An item with five photos still loads instantly in list views
      (thumbnails only).
- [ ] CloudKit dev schema matches the model after adding `ItemPhoto`.

### Failure modes

- **`CD_ItemPhotoEntity` doesn't appear in the CloudKit Console
  after a photo save.** Same root causes as §5a step 1 — App ID's
  CloudKit container assignment didn't save in the portal,
  provisioning profile is stale, or the simulator isn't actually
  signed in. The account-status banner makes the third loud.
- **Thumbnail arrives on phone B but the full asset never does.**
  CloudKit asset transfers can lag on cellular or low-priority
  links — the first thing to do is wait a minute or two before
  treating it as broken. If the asset still hasn't arrived,
  check the CloudKit Console under **Logs** for asset-transfer
  errors on phone A's user record. The 2048 px resize keeps a
  typical photo well under any documented CloudKit per-asset
  limit, so a size-related rejection would be surprising — but
  the logs will say so explicitly if it is.
- **Photo on phone B renders with a placeholder gray square.**
  `thumbnailData` decode failed — the persisted bytes are likely
  truncated or in an unrecognized container. Check the strip
  tile's `thumbnailUIImage` decode path (`ItemPhoto` extension
  in `ItemDetailView.swift`). If the primary header renders
  fine but the strip doesn't, the inline thumbnail mirror is the
  problem, not the asset.
- **Make Primary on phone A doesn't propagate to phone B.** The
  promote writes a single row with `currentMin - 1` and the
  receiving device should resort on the next
  `RemoteChangeMonitor` tick. If the strip on B doesn't reorder,
  check Xcode console on B for `NSPersistentStoreRemoteChange`
  notifications — silence means the observer didn't fire (see
  §5a "Phone B sees nothing after accepting" troubleshooting).
- **Deleting a photo on phone A leaves the row visible on B.**
  Cascade-delete only fires when the parent *Item* is deleted; a
  direct photo delete goes through `ItemPhotoRepository.delete(id:)`
  and skips cascade entirely. Confirm the row is actually gone
  from CloudKit Console under Data — if it is, B's failure to
  reload is a `RemoteChangeMonitor` bug, not a persistence one.
- **Five-photo item hitches on appearance.** The strip is
  rendering full-resolution `imageData` instead of `thumbnailData`.
  Check `photoStripTile(for:at:)` in `ItemDetailView.swift` —
  it must use `photo.thumbnailUIImage`, not `photo.uiImage`.
- **Pager memory grows unbounded on a multi-photo item.** Each
  page decodes its full-resolution image eagerly per the doc-
  comment in `PhotoPagerView`. Acceptable for v1.0 but if real-
  device pressure surfaces, retrofit lazy decode (per-page
  `.onAppear` decode + `.onDisappear` release).

---

## 5e. Phase 6 — iPad / Mac (Designed for iPad) verification

The cross-household views landed across 6.1 / 6.2a / 6.2b. This
runbook flips Phase 6 from "code lands and CI is green" to "the app
is actually usable on iPad in both orientations and on Mac at
multiple window sizes" — the second exit criterion in
`ROADMAP.md` Phase 6.

There is no separate Mac target. Per `project.yml`:
`SUPPORTS_MAC_DESIGNED_FOR_IPAD: YES`, `SUPPORTS_MACCATALYST: NO`.
The same iPad binary runs on Apple-silicon Macs via "Designed for
iPad on Mac." Anywhere this runbook says "Mac" it means that
delivery model — Mac Catalyst is explicitly out of scope per
`ARCHITECTURE.md` §10.

The pattern is the same as §5d: every step here is something the
human has to look at, because the audit at code level can't
distinguish "different from iPhone but correct for iPad" from
"broken on iPad." `xcodebuild test` on an iPhone simulator does
not exercise regular size class.

### 1. iPad landscape — three-column visible

On a real iPad (or `iPad Pro 13-inch` simulator) in landscape:

1. Cold-launch. All three columns visible: sidebar (Smart Lists +
   Locations), content (placeholder or last selection), detail
   (placeholder or last selected item).
2. Tap a Smart List (e.g. **Expiring Soon**). Content column updates
   in place; sidebar selection moves; detail column unchanged.
3. Tap a Location. Same — content swaps, detail untouched.
4. Tap an item in content. Detail column updates. Sidebar
   selection unchanged.
5. Repeat with a deep-link tap (Phase 4 expiry notification, if you
   have one queued from §5c). Sidebar should land on the item's
   location, content shows that location's items, detail shows the
   item — all three columns reflect the deep-link in one tick.

If any of those leave a column stale or jump the sidebar selection
unexpectedly, the bug is in `RootView`'s binding plumbing
(`sidebarSelection` / `selectedItemID`).

### 2. iPad portrait — sidebar toggle, back-nav

Same iPad rotated to portrait:

1. Sidebar collapses to a button (hamburger / `sidebar.left`) in
   the content column's toolbar. Content + detail visible.
2. Tap the sidebar button — sidebar slides in over content. Pick a
   smart list. Sidebar dismisses; content updates.
3. Tap an item — detail updates without dismissing the content
   column. Both still visible.
4. Tap the content column's back chevron. Detail clears; content
   stays.
5. Rotate back to landscape mid-task. The selection should
   survive — content keeps its items, detail keeps the selected
   item.

If sidebar selection survives the rotation but content goes blank,
that's the `@State`-cache / `.task(id:)` race documented in
`RootView`'s `bootstrapComplete` comment — not a regression unless
it shows on first launch.

### 3. iPad multitasking — split view + slide over

Stage Manager and split view both narrow the window enough that
`NavigationSplitView` collapses columns:

1. Drag a second app into split view at 50/50. Naked Pantree's
   window narrows; the detail column may collapse into the content
   column's nav stack.
2. Drag the divider to 70/30 with Naked Pantree on the small side.
   The split view should collapse further — likely to a single
   column with iPhone-style push nav.
3. Drag back to 100%. All three columns return.
4. At 70/30 small side, exercise sidebar search (next step) — the
   compact placement may differ from iPad full-width.

The thresholds aren't documented by Apple and shift across iOS
releases. We don't try to control them; we just verify the app
doesn't break at any of them.

### 4. Sidebar `.searchable` at iPad regular size class

This is the new surface from 6.2b ([apps#48](https://github.com/ellisandy/NakedPantree/pull/48))
and has never been driven on iPad regular size class — the
xcodebuild test job runs an iPhone simulator only. Verify on a real
iPad or `iPad Pro 13-inch` simulator:

1. Sidebar should show a search field at its top
   (`.searchable(placement: .sidebar)`). Visible without scrolling.
2. Type a query that matches items in two different locations
   (e.g. add "Tomatoes" to Pantry and "Tomato paste" to a second
   location first, then search "toma").
3. Content column swaps to **Search** results — title reads
   "Search," items from both locations appear together.
4. Tap a result. Detail column shows the item. Sidebar still has
   the query in the search field; content still shows results.
5. Tap the back chevron from detail (or use Cmd-[ on Mac). Detail
   clears but content **stays on the search results**, not the
   sidebar root. This is the acceptance criterion from #47 that
   the column-based nav gives for free.
6. Clear the search field. Content reverts to whatever was selected
   in the sidebar before search started (e.g. Expiring Soon).
7. Empty-results path: type a query that matches nothing. Content
   should show **"Nothing by that name yet."** with a magnifying-
   glass icon, per `DESIGN_GUIDELINES.md` §10.

If the sidebar search field doesn't appear at all on iPad regular
or hides itself when the sidebar is collapsed in portrait, the
placement is being downgraded — file a bug. The fallback in compact
size class is the navigation-bar drawer; that's expected, not a
regression.

### 5. Mac (Designed for iPad) — small, medium, large windows

On an Apple-silicon Mac with the build installed via TestFlight or
a local archive (per `ARCHITECTURE.md` §10 — Designed for iPad on
Mac is a TestFlight-or-Xcode-archive delivery, not a Cmd-R from
Xcode):

1. Launch. Default window is roughly two-column iPad-portrait-
   sized.
2. Resize the window to ~700 px wide. Three-column should collapse
   to two-column or fall through to single-column push nav. Verify
   no clipped toolbar items, no overlapping text, no permanently-
   hidden controls.
3. Resize to ~1100 px. All three columns should be visible and
   functional, identical to iPad landscape.
4. Resize to a 27" display fullscreen. The detail column shouldn't
   stretch a single column of text edge-to-edge — `Form` / `List`
   readability widths kick in by default; verify they do.
5. Exercise sidebar search (step 4 above) at each window size.
6. Cmd-W closes the window; Cmd-Q quits. The app should re-launch
   into the same household / location / item state on next launch
   (CoreData is the source of truth; nothing app-specific to
   verify here, but worth noting if it doesn't).
7. Menu-bar items: **File**, **Edit**, **View**, **Window**,
   **Help** all populate from SwiftUI defaults. We have no
   `.commands` block of our own yet — keyboard shortcuts beyond
   the built-ins (Cmd-Q, Cmd-W, Cmd-, ) are out of scope for 6.3.

If the Mac build crashes at launch, see §7 troubleshooting — the
`UICloudSharingController` bridge or an entitlement mismatch are
the usual suspects.

### 6. Phase 6 exit criteria

Tick these in `ROADMAP.md` Phase 6 once each passes:

- [ ] App is usable on iPad in both orientations and on Mac at
      multiple window sizes.

The other two exit criteria (Expiring Soon list + empty-state
voice) are owned by 6.1 and 6.4 respectively — 6.3 only carries
the adaptive-layout one.

### Failure modes

- **`UICloudSharingController` sheet renders empty / cropped on
  iPad.** The participant list has fixed-width assumptions from
  iPhone. Wrapping in `.ignoresSafeArea()` (already applied in
  `SidebarView`) usually papers over this; if not, the controller
  needs an explicit `popoverAnchor` on iPad. Check Apple's release
  notes against the iPadOS version under test before reaching for
  a workaround.
- **Sidebar search field disappears in portrait.** SwiftUI
  downgrades `.sidebar` placement to `.navigationBarDrawer` when
  the split view is in compact mode. That's expected behavior for
  iPhone-shaped contexts but iPad portrait should still be
  regular size class — if it drops to compact there, the trait
  collection is unexpected and worth a bug.
- **Detail column "stretches" a one-line label across the full
  Mac window width.** SwiftUI's readability margins handle this
  by default. If a custom `.frame(maxWidth: .infinity)` somewhere
  is overriding them, that's the bug.
- **Mac build crashes at launch with `dyld: missing symbol`.** The
  binary was built against an iPad SDK newer than the Mac runtime
  supports. Fix: lower `IPHONEOS_DEPLOYMENT_TARGET` or update
  macOS. The deployment target lives in `project.yml`.
- **Tapping a search result on iPad lands on detail but back-nav
  drops to the sidebar root.** The detail column's pop is
  popping the wrong stack — almost certainly a stray
  `NavigationStack` somewhere wrapping a column instead of
  `NavigationSplitView` driving column-based nav. Grep for
  `NavigationStack` and confirm none wrap the three-column shell.
- **Hover affordances missing on Mac.** Out of scope for 6.3.
  Tracked separately if it earns its keep — the iPad/Mac binary
  works without them; hover polish is its own decision.

---

## 6. Release

The shape, per `ARCHITECTURE.md` §10:

- **PRs:** `build-test.yml` (build + tests on iPhone simulator) +
  `lint.yml` (swift-format + swiftlint) — both on GitHub Actions
  `macos-26` runners.
- **Merges to `main`:** `testflight-beta.yml` archives, exports, and
  uploads to TestFlight via `xcrun altool`. Same runner.
- **App Store releases:** manual until there's a reason to automate.

### TestFlight upload secrets

The `testflight-beta.yml` workflow needs three repo secrets, all
generated from a single App Store Connect API key with **App Manager**
role:

| Secret | What it is |
| --- | --- |
| `APP_STORE_CONNECT_API_KEY_ID` | Short identifier from the API key page (e.g. `ABCD1234EF`). |
| `APP_STORE_CONNECT_API_ISSUER_ID` | UUID at the top of the **Users and Access → Keys** tab. |
| `APP_STORE_CONNECT_API_KEY` | The downloaded `.p8` file. Either paste the file contents directly (`pbpaste < AuthKey_*.p8`) or its base64 encoding (`base64 -i AuthKey_*.p8 \| pbcopy`) — the workflow detects which one and acts accordingly. |

> **Wrong key type is the #1 setup gotcha.** Apple has multiple `.p8`
> formats: APNs keys, in-app purchase keys, App Store Connect API
> keys. They look identical (PEM-formatted EC private keys, ~250
> bytes) but only the **App Store Connect API key** signs JWTs for
> TestFlight upload. Generate it at
> https://appstoreconnect.apple.com/access/api with the
> **App Manager** role.

Code-signing certificates and provisioning profiles are **not** stored
as secrets — `xcodebuild -allowProvisioningUpdates` regenerates them
via the API key on every run. The `.p8` itself is decoded into the
runner's `~/.appstoreconnect/private_keys/` directory at job start
and disappears with the runner.

### Build numbering

`CFBundleVersion` is overridden to `$GITHUB_RUN_NUMBER` at archive
time so each upload has a strictly increasing build number without
needing a commit-back step. Marketing version
(`CFBundleShortVersionString`) lives in
`NakedPantreeApp/Resources/Info.plist`; bump it by hand at milestone
boundaries.

### CloudKit Production deploy

CloudKit schema changes require a deliberate "Deploy to Production" step
in the CloudKit Console **after** a TestFlight build has exercised every
new field against the development schema. Skipping that step is how you
ship a build that can't sync.

---

## 7. Troubleshooting

> **TODO (filled in opportunistically):** add entries here as we hit and
> resolve issues. Expected starting set:
>
> - "iCloud account required" at launch despite being signed in.
> - CloudKit "schema not deployed" after adding a field.
> - Share invitation never arrives (Messages vs. Mail vs. AirDrop).
> - `NSPersistentStoreRemoteChange` not firing on the second device.
> - Mac build (Designed for iPad) crashes at launch.

Each entry should follow the format: **Symptom → Root cause → Fix.** No
folklore.
