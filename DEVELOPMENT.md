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
on staged Swift files. To run them manually:

```bash
swift-format lint --recursive --strict --parallel .
swiftlint lint --strict
```

> ⚠️ The `--strict` flag is **required** to match CI. Without it
> `swift-format lint` exits 0 even on `[LineLength]` and similar
> warnings — meaning a plain local lint can pass while the
> `.github/workflows/lint.yml` job fails on the same code. If you're
> running these in a script, copy the flags exactly.

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
- [ ] `swift-format lint --recursive --strict --parallel .` and
      `swiftlint lint --strict` exit clean. Plain `swift-format lint`
      without `--strict` exits 0 on warnings — match CI exactly.
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
