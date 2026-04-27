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

## 6. Release

> **TODO (Xcode Cloud setup PR):** document the Xcode Cloud workflow names
> (PR check, TestFlight beta), the TestFlight internal group, and the App
> Store Connect bundle ID once they exist.

The shape, per `ARCHITECTURE.md` §10:

- Every PR: Xcode Cloud builds and runs the test suites.
- Merges to `main`: Xcode Cloud builds, tests, archives, uploads to
  TestFlight (internal group).
- App Store releases are manual until we have a reason to automate.

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
