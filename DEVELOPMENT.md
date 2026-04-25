# Naked Pantree — Development

> Get a working build. Run the tests. Ship to TestFlight.

This doc is for humans setting the project up locally. For the architectural
shape of the code, see `ARCHITECTURE.md`. For guidance aimed at AI coding
agents, see `AGENTS.md`.

> **Status:** stub. Filled out as the actual project structure lands. Sections
> marked **TBD** will be completed before the first code PR.

---

## 1. Prerequisites

- macOS (latest), Xcode 26 or newer.
- An Apple Developer account enrolled in CloudKit (free tier is fine for
  local dev; paid is required for TestFlight).
- Two test devices (or one device + the simulator) for sharing flows.
- Optional: `swift-format` and `swiftlint` installed via Homebrew for the
  pre-commit hook.

---

## 2. First-time setup

**TBD** — to be filled in once the Xcode project is created. Will cover:

1. Clone the repo.
2. Open `NakedPantree.xcworkspace` (not the `.xcodeproj` — the workspace
   includes the local SwiftPM `Packages/Core/`).
3. Configure your Team in Signing & Capabilities for both the app and the
   tests targets.
4. Set the CloudKit container identifier to your developer-account
   container.
5. Run the `Bootstrap` scheme once to generate any required local files.

---

## 3. Day-to-day

### Build

**TBD** — Xcode Build / Cmd+B. CLI invocation via `xcodebuild` to be
documented.

### Test

- **Unit tests:** Cmd+U in Xcode, or `xcodebuild test ...` (exact incantation
  TBD). Includes `NakedPantreeDomain` and `NakedPantreePersistence` package
  tests plus app-target Swift Testing suites.
- **UI tests:** the `NakedPantreeUITests` scheme. These are smoke flows
  only — see §11 of `ARCHITECTURE.md` for what's automated vs manual.

### Lint / format

**TBD** — `swift-format` config and `swiftlint` rules to be added.

---

## 4. Manual QA checklist

The full per-release checklist lives in §11 of `ARCHITECTURE.md`. The short
version: two devices, sharing accepted, airplane-mode write, photo, Mac
build.

---

## 5. Release

**TBD** — Xcode Cloud workflow names, TestFlight group, App Store Connect
setup. Will be filled in once the workflows exist.

---

## 6. Troubleshooting

**TBD** — common CloudKit "no account" / "schema not deployed" / "share
not accepted" pitfalls and how to recover. Filled in as we hit them.
