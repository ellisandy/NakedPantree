# Naked Pantree — Development

> Get a working build. Run the tests. Ship to TestFlight.

This doc is for humans setting the project up locally. For the architectural
shape of the code, see `ARCHITECTURE.md`. For guidance aimed at AI coding
agents, see `AGENTS.md`. For voice and copy rules, see
`DESIGN_GUIDELINES.md`.

> **Status:** the things that are project-independent are filled in. Sections
> that depend on the not-yet-existing Xcode project carry explicit `TODO`
> markers with the PR or event that should resolve them.

---

## 1. Prerequisites

| Requirement | Why |
| --- | --- |
| **macOS 15 or newer** on **Apple Silicon** | "Designed for iPad on Mac" requires Apple Silicon (`ARCHITECTURE.md` §10). |
| **Xcode 26 or newer** | iOS 26 SDK, Swift Testing default, current SwiftUI surface. |
| **Swift 6 toolchain** (bundled with Xcode 26) | Strict concurrency, `Sendable` repository protocols. |
| **Apple Developer account** with CloudKit enabled | Free tier is fine for local dev; paid is required to push a TestFlight build. |
| **Two devices** (or one device + the simulator) | Sharing flows can't be exercised on a single CloudKit account from one process. See `ARCHITECTURE.md` §11. |
| `swift-format` and `swiftlint` (Homebrew) | Pre-commit hook + CI lint. Configs live at the repo root once added (see TODO below). |

Optional but useful: a second iCloud account for the "different accounts,
share accepted" manual check.

---

## 2. First-time setup

> **TODO (scaffolding PR):** rewrite this section with concrete steps once
> the Xcode project exists. The shape will be:
>
> 1. Clone the repo.
> 2. Open `NakedPantree.xcworkspace` (the workspace pulls in the local
>    `Packages/Core/` SwiftPM package — opening the bare `.xcodeproj`
>    misses it).
> 3. In Signing & Capabilities, set your Team for the app target, the
>    `NakedPantreeTests` target, and the `NakedPantreeUITests` target.
> 4. Set the CloudKit container identifier to `iCloud.<your-id>.NakedPantree`
>    (the default container created with the app target).
> 5. Run the **Bootstrap** scheme once to provision any required local
>    files (CloudKit schema deploy, default `Household` and `Location`).
> 6. Build & run on a real device — the Simulator can't reach the iCloud
>    accounts you'll want to test against.

---

## 3. Day-to-day

### Build

> **TODO (scaffolding PR):** lock in the exact `xcodebuild` invocation and
> scheme names. Cmd+B in Xcode works without any of that.

### Test

The intent (per `ARCHITECTURE.md` §11):

- **Package tests** (`NakedPantreeDomain`, `NakedPantreePersistence`) — fast,
  no I/O, run on every save.
- **App-target Swift Testing suites** — view models, scheduler, photo
  pipeline against in-memory repository mocks.
- **XCUITest smoke flows** — sidebar nav, item create, share sheet open.

Cmd+U in Xcode runs everything.

> **TODO (scaffolding PR):** document the headless invocations:
> `xcodebuild test -scheme <name> -destination 'platform=iOS Simulator,...'`
> for each suite, and the equivalent for the SwiftPM package
> (`swift test --package-path Packages/Core`).

### Lint and format

We will commit configs for both tools at the repo root:

- `.swift-format` — code-formatting rules.
- `.swiftlint.yml` — lint rules.

A pre-commit hook should run both on staged Swift files. CI runs them on
every PR.

> **TODO (lint PR):** add the actual `.swift-format` and `.swiftlint.yml`
> files, the pre-commit hook script under `scripts/`, and the GitHub
> Actions workflow that runs them.

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
- [ ] `swift-format` and `swiftlint` clean.
- [ ] Manual checklist (`ARCHITECTURE.md` §11) re-run if the PR touches
      sync, sharing, notifications, or photos.
- [ ] Screenshot (or short video) attached for any UI-visible change.

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
