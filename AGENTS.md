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
- **Use a git worktree for every task** — see §3 below. Do not switch
  branches in the main checkout while another task is in flight.

---

## 3. Use a git worktree for every task

This repo expects parallel work. Multiple agents (or one agent across
multiple sessions) regularly have independent branches in flight.
Switching branches in the main checkout corrupts in-progress work and
makes review history confusing. Worktrees fix this.

### The rule

- **Every new task starts with `git worktree add`.** Never `git checkout`
  another branch in the main checkout to do new work.
- **One worktree per branch.** Don't share worktrees across tasks.
- **Clean up when done.** After the PR merges, remove the worktree.

### How

```bash
# From the main checkout. Branch name follows DEVELOPMENT.md §4 conventions.
git worktree add ../NakedPantree-<short-name> -b claude/<short-name>

# Work inside it.
cd ../NakedPantree-<short-name>
# ... make commits, push, open PR ...

# After the PR merges:
cd /home/user/NakedPantree   # or wherever the main checkout lives
git worktree remove ../NakedPantree-<short-name>
git branch -d claude/<short-name>
```

### When using the Claude Code `Agent` tool

The `Agent` tool accepts an `isolation: "worktree"` parameter that
creates and cleans up a worktree automatically. Prefer that to manual
`git worktree add` when delegating a self-contained task to a sub-agent.
The agent's branch and final path come back in the result if any commits
were made; the worktree is auto-removed if no changes were made.

### When *not* to use a worktree

- One-line edits the user is watching live (e.g. fixing a typo they just
  pointed out). Switching to a worktree adds friction with no benefit.
- Pure read-only investigation. Read what you need from the main
  checkout — no branch involved.

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
- **`git checkout`-ing a different branch in the main checkout.** Use a
  worktree. See §3.
- **Skipping `--no-verify` discussions.** Don't use it without explicit
  user permission, even if a hook is annoying. Fix the hook or the code.

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
