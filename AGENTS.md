# Naked Pantree — Agent Guide

> For the ones-and-zeros developers. Read this before writing code in this
> repo.

This document is the operating manual for AI coding agents (Claude Code,
Cursor, Copilot Workspace, etc.) working on Naked Pantree. Humans, see
`DEVELOPMENT.md`. Architecture, see `ARCHITECTURE.md`. Brand voice and
copy rules, see `DESIGN_GUIDELINES.md`.

> **Status:** the rules and conventions that don't depend on real code are
> filled in. Sections that wait for the project to exist carry explicit
> `TODO` markers.

---

## 1. Read these first, in this order

1. `ARCHITECTURE.md` — the shape of the system. Don't propose changes
   that contradict it without flagging them as a deviation.
2. `DESIGN_GUIDELINES.md` — voice, copy, color, logo. Every user-facing
   string passes the §10 checklist.
3. `DEVELOPMENT.md` — local setup, branch policy, pre-merge checklist.
4. This file — local conventions and traps.

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
- **Don't have two tasks in flight in the same checkout.** Use a worktree
  if the environment supports it; otherwise commit / push / open a PR
  before switching branches. See §3.

---

## 3. Branch isolation: worktrees when supported, serial branches otherwise

This repo expects multiple branches in flight at once. Switching branches
in a single checkout while another task is mid-edit corrupts in-progress
work and confuses review history. There are two ways to avoid that — pick
the one your environment supports.

### Preferred: git worktrees

When the environment supports it, each new task gets its own worktree:

```bash
# From the main checkout. Branch name follows DEVELOPMENT.md §4 conventions.
git worktree add ../NakedPantree-<short-name> -b claude/<short-name>

cd ../NakedPantree-<short-name>
# ... make commits, push, open PR ...

# After the PR merges:
cd /home/user/NakedPantree   # or wherever the main checkout lives
git worktree remove ../NakedPantree-<short-name>
git branch -d claude/<short-name>
```

### Known limitation: hosted commit-signing services

Some Claude Code hosted environments use a managed commit-signing service
that rejects signing requests issued from a worktree (HTTP 400
`"missing source"`) but signs cleanly from the main checkout. Confirmed
with an empty-commit test from each location. If you hit it:

- **Don't reach for `--no-verify` or `-c commit.gpgsign=false`.** That
  produces unsigned commits and a downstream policy headache.
- **Fall back to serial branches in the main checkout.** Only one task
  in flight at a time. Commit, push, and open the PR before starting the
  next one.
- **Don't keep uncommitted changes when you switch branches.** Stash or
  commit first.

A quick way to check the current environment: from a worktree, run
`git commit --allow-empty -m "signing test"`. If it fails, you're in a
fall-back environment.

### When using the Claude Code `Agent` tool

`Agent` accepts an `isolation: "worktree"` parameter that creates and
cleans up a worktree automatically. The same signing limitation applies —
if the sub-agent's commits fail to sign in its worktree, prefer running
the work directly in the main checkout instead.

### When *not* to isolate at all

- One-line edits the user is watching live (e.g. fixing a typo they just
  pointed out). Branch switching adds friction with no benefit.
- Pure read-only investigation. Read what you need; no branch involved.

---

## 4. Conventions

### File layout

Match `ARCHITECTURE.md` §3 exactly. New SwiftUI features go under
`NakedPantreeApp/Features/<FeatureName>/`. New repository protocols go
under `Packages/Core/Sources/NakedPantreeDomain/Repositories/`.

### Naming

> **TODO (first feature PR):** lock in the suffix conventions
> (`*View`, `*ViewModel`, `*Repository`, `*Service`) once the first real
> feature lands and we can point at concrete examples.

Until then: prefer Apple's own SwiftUI sample-app conventions and match
whatever neighbors in the file use.

### Tests

- Every public function in `NakedPantreeDomain` has a Swift Testing case.
- Every repository protocol has both a Core Data-backed implementation
  test (against an in-memory store) and an in-memory mock used by app-level
  tests.
- UI tests are smoke-only; they exercise navigation, not business logic.

### Commits and PRs

Follow `DEVELOPMENT.md` §4. The pre-merge checklist there applies to
agent-authored PRs too. In particular: update `ARCHITECTURE.md` in the
same PR if the change touches the schema, an enum, or a repository
protocol.

### `ROADMAP.md` is a living document

When a PR completes — or introduces — an interim milestone, update
`ROADMAP.md` in the same branch:

- Tick the exit-criteria checkboxes the PR satisfies.
- Mark the phase status at the top of its section: `✅ Complete`,
  `🟡 In progress`, or leave blank for upcoming.
- If a phase is large enough to land across multiple PRs, maintain a
  **Sub-milestones** table inside that phase. Phase 1 carries the
  pattern: one row per PR with title, status, and a PR link once
  it's open. The split is a guide, not a contract — retitle or add
  rows when scope shifts.

Bundle the roadmap edit into the PR that does the work, **not** a
follow-up PR. The doc reflects state as-of-merge: by the time the PR
lands on `main`, anyone reading `ROADMAP.md` should see the work
already counted.

---

## 5. Things that look fine but aren't

A short list of traps that have already cost time:

- **Adding a unique constraint in the Core Data model.** CloudKit-mirrored
  stores reject these — the app will crash on first migration. Enforce
  uniqueness in code at insert time, on `id: UUID`.
- **Making a relationship required.** CloudKit needs every relationship
  optional and bidirectional. The model editor will let you do it; sync
  will reject it.
- **Using SwiftData.** It still doesn't expose the CloudKit shared
  database on iOS 26. Sharing is the product. Don't.
- **Reaching for `TabView` at the root.** Smart Lists + Locations *are*
  the navigation; see `ARCHITECTURE.md` §7.
- **Putting humor in error messages, permission requests, billing, or
  legal text.** See `DESIGN_GUIDELINES.md` §9 — those are off-limits.
- **Switching branches in the main checkout while another task is mid-edit.**
  See §3 for the worktree workflow and the signing-service caveat.
- **Reaching for `--no-verify` to bypass a failing hook.** Don't, without
  explicit user permission. Fix the hook or the code.
- **Assuming worktrees just work.** They don't, in every environment —
  re-read §3.
- **Running `swift-format lint --recursive` locally.** The
  Xcode-bundled binary's `--recursive` mode silently misses per-file
  `[LineLength]` (and similar) violations that CI's `swift:6.0`
  container catches. A clean local recursive run is **not evidence
  that CI will pass** — this has shipped failed-CI lint three times.
  Run **`./scripts/lint.sh`** instead, which enumerates files
  explicitly and sidesteps the broken code path. See `DEVELOPMENT.md` §3.

---

## 6. When you're stuck

- If a change requires deviating from `ARCHITECTURE.md`, propose the
  deviation in the PR description and wait for sign-off rather than
  silently doing it.
- If you can't tell whether something is in scope for v1.0, check
  `ARCHITECTURE.md` §1 (Goals) and §12 (Future Considerations) before
  writing code.
- If `DESIGN_GUIDELINES.md` and a UX choice seem to conflict, the
  guidelines win.
- If `DEVELOPMENT.md` has a `TODO` blocking your task, fill it in as
  part of your PR — don't work around it silently.
