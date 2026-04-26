# Naked Pantree

> Know what you have—no pants required.

Naked Pantree is an iOS app for tracking everything in your pantry, fridge,
freezer, and beyond — across the kitchen, garage, barn, and that extra
freezer outside. Multi-location, shared between household members, and it
reminds you before things expire.

**Status:** in planning. No app code yet — design, architecture, and the
phased roadmap are committed; implementation begins with Phase 0 (Xcode
project scaffolding) per [`ROADMAP.md`](ROADMAP.md).

## What's here

| Document | What's in it |
| --- | --- |
| [`DESIGN_GUIDELINES.md`](DESIGN_GUIDELINES.md) | Voice, color palette, typography, app icon, copy rules. |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Stack choices, domain model, sync + sharing topology, testing strategy. |
| [`ROADMAP.md`](ROADMAP.md) | Eight phases between empty repo and TestFlight, each with exit criteria. |
| [`DEVELOPMENT.md`](DEVELOPMENT.md) | Local setup, branch policy, pre-merge checklist. |
| [`AGENTS.md`](AGENTS.md) | Operating manual for AI coding agents working on this repo. |
| [`assets/brand/`](assets/brand) | Brand color tokens (machine-readable). |

## Stack

- iOS 26+; iPad-compatible; runs on Apple Silicon Macs via "Designed for
  iPad on Mac."
- SwiftUI with `NavigationSplitView` from day one.
- Core Data via `NSPersistentCloudKitContainer` (private + shared stores)
  for sync + sharing.
- Local SwiftPM `Packages/Core/` for domain + persistence reuse (paves
  the way for a future personal CLI / AI helper).
- Swift Testing.
- Xcode Cloud → TestFlight.

See `ARCHITECTURE.md` for the why behind each.

## Project conventions

- Voice and copy rules in `DESIGN_GUIDELINES.md` apply to every
  user-facing string the project ships.
- Every PR follows the pre-merge checklist in `DEVELOPMENT.md` §4.
- AI-authored work follows `AGENTS.md` — including its branch-isolation
  workflow and the known signing-service caveat in §3.

## Contributing

This is a personal project; outside contributions aren't being solicited
for v1.0. The docs are public so future-me, collaborators, and AI agents
share the same source of truth.
