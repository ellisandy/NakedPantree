# Naked Pantree — Architecture

> Build the boring parts well. Sharing, sync, and notifications are the product.

This document is the source of truth for how Naked Pantree v1.0 is built. It
captures the decisions made during planning so future work has a frame of
reference, not a debate. Like the design guidelines, it is intentionally
opinionated: restraint is the point.

---

## 1. Goals & Non-Goals

### Goals (v1.0 → TestFlight)

- A household can track items across multiple locations (pantry, fridge,
  freezer, barn freezer, etc.) on iPhone.
- Two or more people in the same household see the same inventory in near
  real time.
- Users get a local notification before an item expires.
- Users can attach a **primary photo** to an item, plus **secondary
  reference shots** (e.g. ingredient list, back of a waffle-mix box).
- The app runs on iPad (adaptive) and on Apple Silicon Macs via "Designed
  for iPad on Mac" (see §10 for why this is *not* Mac Catalyst).

### Non-goals (v1.0)

These are explicitly out for v1.0. Items we **want to add later** live in §12
(Future Considerations), not here.

- Web app or Android app.
- A separate native macOS app or a Mac Catalyst build.
- Server-side state, accounts, or any backend we operate.
- Two-way Apple Reminders sync.
- An Apple Watch app.

---

## 2. Platform & Stack

| Concern | Choice |
| --- | --- |
| App platform | iOS 26 (iPad-compatible, runs on Apple Silicon Macs) |
| UI framework | SwiftUI |
| Persistence | Core Data via `NSPersistentCloudKitContainer` |
| Sync & sharing | CloudKit private DB + shared DB (Record Zone Sharing) |
| Notifications | `UNUserNotificationCenter` (local only) |
| Unit tests | Swift Testing |
| UI tests | XCUITest (smoke flows for sidebar, item create, share) |
| CI / distribution | Xcode Cloud → TestFlight |

### Why Core Data, not SwiftData

SwiftData on iOS 26 still does not expose CloudKit's shared database. Sharing
a household between two phones is the entire point of the product, so SwiftData
is disqualified for v1.0. We use `NSPersistentCloudKitContainer` with two
stores in the same container (private + shared) and the WWDC21 Record Zone
Sharing model.

If SwiftData closes the gap in a later iOS, migration is a separate decision —
not a v1.0 problem.

---

## 3. Repository Layout

```
NakedPantree/
  NakedPantree.xcworkspace
  NakedPantree.xcodeproj
  NakedPantreeApp/                 # iOS app target
    App/                           # @main, scene delegate, share acceptance
    Sharing/                       # CKShare wiring, UICloudSharingController bridge
    Notifications/                 # scheduler, permission flow
    Features/                      # Locations, Items, ItemDetail, Onboarding
    DesignSystem/                  # tokens from assets/brand, typography, components
    Resources/                     # asset catalog, localized strings
  Packages/
    Core/                          # local SwiftPM package — lives in THIS repo
      Sources/
        NakedPantreeDomain/        # entities, enums, value types, repository
                                   #   PROTOCOLS — no Core Data, no UIKit
        NakedPantreePersistence/   # NSPersistentCloudKitContainer-backed
                                   #   implementations of the protocols
      Tests/
  NakedPantreeTests/               # app-level integration tests
  NakedPantreeUITests/             # XCUITest smoke flows
  assets/brand/                    # existing brand tokens (colors.json)
  DESIGN_GUIDELINES.md
  ARCHITECTURE.md                  # this file
  DEVELOPMENT.md                   # local setup, build, test, release
  AGENTS.md                        # guidance for AI coding agents
```

The Core SwiftPM package lives at `Packages/Core/` **inside this repo** —
there is no separate repository. The iOS app, the future macOS CLI, and any
AI query helper all depend on it as a local package. This keeps the query
surface honest: anything the CLI needs must be reachable without importing
UIKit, and `NakedPantreeDomain` must compile without a Core Data dependency
so it can host the repository protocols (see §11).

---

## 4. Domain Model

Four entities. Relationships are optional with inverses, and every attribute
is either optional or has a default — both are CloudKit constraints, not
stylistic choices. Identity attributes (`id`, `createdAt`, `updatedAt`,
`name`) are modeled as optional because there is no meaningful schema-level
default for a UUID or a creation timestamp; the repository layer always
sets them on insert.

### Household

| Attribute | Type | Notes |
| --- | --- | --- |
| `id` | UUID | App-level identity |
| `name` | String | Default `"My Pantry"` |
| `createdAt` | Date | |
| `locations` | `[Location]?` | Cascade delete |

The `Household` is the **share root**. One household per `CKShare`.

### Location

| Attribute | Type | Notes |
| --- | --- | --- |
| `id` | UUID | |
| `name` | String | "Kitchen Pantry", "Garage Freezer" |
| `kindRaw` | String | `LocationKind` enum raw, default `"pantry"` |
| `sortOrder` | Int16 | Default `0` |
| `createdAt` | Date | |
| `household` | `Household?` | Inverse |
| `items` | `[Item]?` | Cascade delete |

`LocationKind` lives in `NakedPantreeDomain`: `pantry`, `fridge`, `freezer`,
`dryGoods`, `other`. Stored as `String` so unknown values from a
forward-incompatible client don't crash decode.

### Item

| Attribute | Type | Notes |
| --- | --- | --- |
| `id` | UUID | |
| `name` | String | |
| `quantity` | Int32 | Default `1` |
| `unitRaw` | String | `Unit` enum raw, default `"count"` |
| `expiresAt` | Date? | Drives expiry notifications |
| `notes` | String? | |
| `createdAt` | Date | |
| `updatedAt` | Date | Touched on every edit |
| `location` | `Location?` | Inverse |
| `photos` | `[ItemPhoto]?` | Cascade delete |

### ItemPhoto

| Attribute | Type | Notes |
| --- | --- | --- |
| `id` | UUID | |
| `imageData` | Data? | **External Storage** → CKAsset on sync |
| `thumbnailData` | Data? | Inline, ~64KB JPEG, drives list views |
| `caption` | String? | "back of box", "ingredients", … |
| `sortOrder` | Int16 | Default `0` — **`0` is the primary photo**; the rest are secondary |
| `createdAt` | Date | |
| `item` | `Item?` | Inverse |

A separate entity (rather than a `photoData` attribute on `Item`) so an item
can carry the front, the ingredient list, and the back of a waffle-mix box
without growing the `Item` row. The lowest-`sortOrder` photo is treated as
the **primary**: it's what list rows, grids, and the item header show.
Secondary photos are reachable from the item detail view via a horizontal
strip — one tap into a full-screen pager. Capture is covered in §9.

### Constraints we are *not* using

- **No unique constraints.** CloudKit-mirrored stores reject them. Uniqueness
  by `id: UUID` is enforced at the application level on insert.
- **No required relationships.** CloudKit requires every relationship to be
  optional and bidirectional.

### Enums

Every enum is stored on its entity as a `*Raw: String` attribute (Core
Data + CloudKit don't preserve Swift enums) and exposed in
`NakedPantreeDomain` as a `String`-backed enum with an `unknown(String)`
catch-all so a future client adding a value won't crash older builds.

#### `LocationKind` — on `Location.kindRaw`

| Raw | Use |
| --- | --- |
| `pantry` | Default. Dry shelf-stable storage. |
| `fridge` | Refrigerated. |
| `freezer` | Frozen. |
| `dryGoods` | Bulk staples — flour, rice, beans. |
| `other` | Catch-all (barn shelf, garage cabinet, …). |

#### `Unit` — on `Item.unitRaw`

| Raw | Use |
| --- | --- |
| `count` | Default. Discrete items ("3 cans of tomatoes"). |
| `gram` | Mass, metric. |
| `kilogram` | Mass, metric. |
| `ounce` | Mass, US. |
| `pound` | Mass, US. |
| `milliliter` | Volume, metric. |
| `liter` | Volume, metric. |
| `fluidOunce` | Volume, US. |
| `package` | Pre-packaged unit ("a box of waffle mix"). |

We deliberately keep this list short for v1.0. New units are an additive
schema change — see migration notes in §10.

---

## 5. Sync & Sharing

### Topology

- One CloudKit container.
- Two `NSPersistentStoreDescription`s in the same `NSPersistentCloudKitContainer`:
  - `private.sqlite` → user's `CKContainer.privateCloudDatabase`
  - `shared.sqlite`  → `CKContainer.sharedCloudDatabase`
- Every write goes to whichever store currently owns the `Household`. The
  share moves the whole record zone, so flipping ownership is a CloudKit
  operation, not a copy.

### Sharing flow

1. User taps "Share Household."
2. We create or fetch the `CKShare` rooted at the `Household`'s record.
3. We present `UICloudSharingController` via a `UIViewControllerRepresentable`
   bridge (no SwiftUI-native equivalent yet on iOS 26).
4. Recipient taps the iCloud invite. The system calls
   `windowScene(_:userDidAcceptCloudKitShareWith:)`; we call
   `acceptShareInvitations(from:into:completion:)` on the shared store.
5. From that point the recipient's app sees the household via the shared
   store. Edits replicate via `NSPersistentStoreRemoteChange`.

### Conflict resolution

`NSMergeByPropertyObjectTrumpMergePolicy` — last write wins, per attribute.
Accepted edge case: if two phones edit `Item.quantity` near-simultaneously,
the later one wins. This is acceptable for a household-inventory app; we are
not building OT.

#### Offline edits

The interesting case is two members editing **the same item while both
offline**. Each write is queued locally and stamped with `updatedAt` (set by
the writing client) and a CloudKit server-side modification time when the
record eventually replicates. The merge happens at the property level — so
if member A bumps `quantity` from 3 → 2 and member B edits `notes`, both
edits land. If both touch `quantity`, the write whose CloudKit replication
lands second wins, regardless of who wrote it first locally. Deletes win
over edits to the same record (CloudKit default).

We do **not** show a "conflict" UI. The user model is "the fridge eventually
shows the truth," and forcing humans to resolve merges would be worse than
the very rare miscount. If this turns out to bite real users, the next step
is per-item CRDT counters on `quantity`, not a conflict modal.

### Offline behavior

The local SQLite store is the source of truth for the UI. Writes are queued
by Core Data's mirror and flushed when CloudKit is reachable. We do **not**
show a spinner for sync — only an unobtrusive banner if the container reports
account problems.

---

## 6. Onboarding

The shortest path to a usable app.

1. **Require iCloud.** If the user is signed out, show a plain explanation and
   a button that opens Settings. No humor here — voice rules §9 of the design
   guidelines apply.
2. **Implicit default household.** On first launch we create a `Household`
   named "My Pantry" and a default `Location` named "Kitchen." The user
   renames either in place. No multi-step setup.
3. **Defer notification permission.** Ask the first time the user sets an
   `expiresAt` — that's the moment the permission actually buys them
   something. If they decline, expiry UI still works; only the local
   reminder is suppressed.

---

## 7. Navigation & Adaptive Layout

`NavigationSplitView` from day one, three columns:

| Column | iPhone | iPad / Mac |
| --- | --- | --- |
| Sidebar | Smart Lists + Locations (drilled) | Smart Lists + Locations |
| Content | Items in selected list/location | Items in selected list/location |
| Detail | Item detail (pushed) | Item detail (visible) |

This gives us iPad's two-pane and Mac's three-pane layout for free, with no
size-class branching code. On iPhone the split view collapses to the standard
push stack automatically.

We deliberately avoid `TabView` at the root — locations *are* the primary
navigation, and Smart Lists sit above them.

### Sidebar shape

The sidebar has two sections, in this order. The pattern mirrors Apple Mail,
Reminders, and Notes — users already know it.

```
Smart Lists
  ▢ Expiring Soon       (items with expiresAt within 7 days, sorted soonest)
  ▢ All Items           (every item across every location, with search)
  ▢ Recently Added      (items added in the last 14 days)

Locations
  🥫 Kitchen Pantry
  🧊 Garage Freezer
  🌽 Barn Shelf
  …
```

**Why both:** the user comments on the PR called this out directly. When
you're doing inventory cleanup you want a *single* location view (focused,
edit-heavy). When you're deciding what to cook tonight or what's about to
spoil, you need a *cross-household* view. The sidebar serves both modes
without modal switching.

Smart Lists are pure projections — they read from the same Core Data store
as Locations and don't introduce new entities. They are computed via
`NSPredicate` against the repository protocols defined in §11.

---

## 8. Notifications

### Scheduling

- Local only (`UNUserNotificationCenter`, `UNCalendarNotificationTrigger`).
- Identifier is deterministic: `"item.\(item.id.uuidString).expiry"`. The
  scheduler can re-add the same identifier idempotently — `add(_:)` replaces
  pending requests with the same id.
- Default lead time: 3 days before `expiresAt` at 9:00 local. Configurable
  per item later; not in v1.0.
- A `NotificationScheduler` service observes `NSManagedObjectContextDidSave`
  and `NSPersistentStoreRemoteChange`. On each event it diffs affected items
  and reschedules / cancels.

### Tap behavior

Every scheduled notification carries `userInfo: ["itemID": item.id.uuidString]`.
A `UNUserNotificationCenterDelegate` on the app side reads it and routes the
app to the corresponding `Item` detail via the navigation state's
`selectedItemID` binding. Routing rules:

- If the item still exists, push it onto the detail column.
- If the item was deleted (e.g. someone in the household tossed it before
  you tapped), land on the **Expiring Soon** smart list instead and show a
  one-line plain banner: "That item is gone."
- If the app is launched cold from the notification, the routing is applied
  after the persistent store loads, not during onboarding.

**Phase 4.2 interim:** Expiring Soon is stubbed until Phase 6, so routing
to it on a missing item lands on a placeholder that has nothing to do with
the deleted item — worse than no navigation at all. Until Smart Lists ship,
the missing-item case shows the "That item is gone." copy as a one-shot
alert in place and leaves the user on whatever surface they were viewing.
Restore the Expiring Soon hand-off when Phase 6 lands the real list.

### Multi-device behavior

If two household members both have the app installed, both phones will fire
the notification. We accept this for v1.0. Server-side dedup would require a
backend, which we don't have. If it becomes a real annoyance, the fix is a
per-user "I want expiry alerts" toggle, not infrastructure.

### Voice

Notification copy follows the design guidelines:

- ✅ "Milk expires tomorrow."
- ❌ "Milk expires tomorrow. You've been warned." — funny in the doc, too
  heavy when it pings someone at 9am.

#### Phase 4.4 voice review

Recorded here so the verdict travels with the spec, not just a closed PR.

| Surface | Copy | Verdict |
| --- | --- | --- |
| Notification title | `item.name` (the user's own string) | ✅ The user's words always win. No app-side editorializing. |
| Notification body | `"Expires <relative>."` — e.g. `"Expires in 3 days."` (`expiryNotificationBodyCopy`) | ✅ Plain, useful, time-anchored to fire (not save) date. Passes the "frustrated user at 9am" test. **Known limitation:** `RelativeDateTimeFormatter` localizes its output, but `"Expires "` is hardcoded English — a Spanish-locale device will read `"Expires en 3 días."` v1.0 ships English-only by design; full localization is a Phase 7 polish item. |
| Missing-item alert (`RootView`) | `"That item is gone."` | ✅ Short, calm, no joke about a phantom milk bottle. Stays in the personality-off-limits zone (`DESIGN_GUIDELINES.md` §9). |
| Permission prompt | iOS system default — not customizable in `requestAuthorization(options:)` | n/a |

The `DESIGN_GUIDELINES.md` §9 personality table cites `"This expires soon. Time to act."` as illustrative — the implementation went with the relative-time form because it's measurably more useful (the user knows whether to act today vs. plan for the weekend). The guide's example is a frame, not a literal string requirement.

---

## 9. Photos

- Stored on `ItemPhoto.imageData` with **External Storage** enabled. Core
  Data writes to the file system locally; the CloudKit mirror promotes to
  `CKAsset` automatically.
- A second attribute, `thumbnailData`, holds an inline ~64KB JPEG. List and
  grid views read the thumbnail; only the detail view reads the full asset.
- Capture path: `PhotosPicker` for the picker, plus `UIImagePickerController`
  bridge for direct camera capture. We resize on import (max 2048px long
  edge) before persisting.

### Primary vs secondary

A clean interface comes from a clear hierarchy:

- **Primary** (`sortOrder == 0`) is what *every* item-aware surface
  shows: list rows, grids, item header in detail, share previews.
- **Secondary** photos sit behind one tap. The item detail view shows a
  small horizontal strip of thumbnails below the header; tapping any opens
  a full-screen pager (`TabView` with `.tabViewStyle(.page)`).
- Reordering is a long-press-and-drag in the strip; whichever photo lands
  at index 0 becomes the new primary.
- Deleting the primary promotes the next photo (lowest `sortOrder`)
  automatically.

The strip is hidden entirely when an item has zero or one photo — no empty
chrome, no "+1 more" affordance for a single image.

---

## 10. Distribution & CI

- Single iOS app target. `iPad` is added to "Supported Destinations." "Mac
  (Designed for iPad)" is enabled.
- **Xcode Cloud** runs on every PR (build + tests) and on merges to `main`
  (TestFlight beta upload, internal group).
- GitHub Actions is reserved for lint and `swift-format` checks that don't
  need an Xcode runner.
- Versioned Core Data model from day one (`Model.xcdatamodeld` with a `v1`
  version inside). Lightweight migration enabled. CloudKit schema changes
  are deployed to Production via the CloudKit Console after the dev schema
  has shipped to a TestFlight build that exercises every new field.

### "Designed for iPad on Mac" vs Mac Catalyst

These are two different Apple technologies. We are using the first, not the
second:

| | Designed for iPad on Mac (chosen) | Mac Catalyst |
| --- | --- | --- |
| What it is | The iPad binary runs unmodified on Apple Silicon Macs. | A separate Mac build target that compiles UIKit code into an AppKit-hosted Mac app. |
| Build cost | Zero — flip a checkbox in "Supported Destinations." | A second build configuration, second sandbox profile, second set of QA, AppKit bridging where Mac-native behavior is wanted. |
| Mac feel | iPad app in a Mac window. Right-click works, menu bar is generated, but it's clearly an iPad app. | More Mac-native (windowing, menu items, sidebar styles). |
| Why we chose this | Mac is a personal convenience for power users, not a product. The iPad layout is already adaptive (§7), so the Mac window inherits it for free. | Reserved for a possible v2 if a real Mac audience emerges. Not before. |

The personal CLI in §12 is a separate concern — it's a command-line
executable target, not a GUI Mac app.

---

## 11. Testing

### Repository protocols — the testability boundary

The single biggest testability decision: **the data layer is hidden behind
protocols defined in `NakedPantreeDomain`.** The CloudKit-mirrored
Core Data implementation lives in `NakedPantreePersistence` and is the only
type that imports CoreData. Everything above the persistence layer
(features, view models, the notification scheduler, the future CLI, the
future AI helper) talks to the protocols, never to `NSManagedObject`
subclasses or `NSPersistentCloudKitContainer` directly.

Sketch:

```swift
// NakedPantreeDomain — no CoreData, no UIKit
public protocol ItemRepository: Sendable {
    func items(in: Location.ID) async throws -> [Item]
    func expiringWithin(_ days: Int) async throws -> [Item]
    func search(_ query: String) async throws -> [Item]
    func upsert(_ item: Item) async throws
    func delete(id: Item.ID) async throws
}

// NakedPantreePersistence — internal Core Data impl
struct CoreDataItemRepository: ItemRepository { … }

// Tests — fast, deterministic, no CloudKit
final class InMemoryItemRepository: ItemRepository { … }
```

This means the storage layer that *actually* talks to CloudKit is an
integration concern (covered manually below), but every layer above it is
unit-testable with no I/O.

### Automated coverage (Swift Testing + XCUITest)

We are not aiming for vanity coverage numbers. We *are* aiming to catch the
classes of bug that would silently break sync, expiry, or sharing.

#### `NakedPantreeDomain` (pure logic — fastest, biggest count)

- Enum raw-value stability — breaking these breaks sync. One failing assert
  per existing raw value, plus an `unknown(String)` round-trip test.
- Date math for `expiringWithin(_:)` (boundary at midnight, DST transition,
  expired-already inclusion rules).
- Search query normalization (case, diacritics, whitespace).

#### `NakedPantreePersistence` against an **in-memory Core Data store**

- Every `*Repository` protocol method, end to end, against an
  `NSPersistentContainer` (no CloudKit) backed by `/dev/null`.
- Conflict-merge policy: write A, write B with the same `id` and a later
  `updatedAt`, assert B wins property-wise.
- Cascade deletes: deleting a `Location` removes its `Item`s and their
  `ItemPhoto`s.
- Lightweight migration tests as the model bumps versions.

#### App-level (Swift Testing, app target)

- `NotificationScheduler` against an `InMemoryItemRepository` — schedule,
  reschedule on edit, cancel on delete, idempotent identifier.
- Notification routing: a delivered notification with a known `itemID`
  surfaces the right detail; a missing `itemID` falls back to Expiring Soon.
- Photo import pipeline: 4032×3024 JPEG in → ≤2048px primary + ~64KB
  thumbnail out, EXIF stripped, orientation respected.
- Reminders push (when shipped): given a chosen list id, calling the
  publish action issues exactly one `EKReminder` with the right title.
- View models for Smart Lists (Expiring Soon, All Items, Recently Added)
  against an in-memory repository fixture.

#### XCUITest — UI smoke flows

- Launch → empty state → create first item → it appears in the location
  list.
- Sidebar navigation between Smart Lists and Locations on iPhone, iPad,
  and Mac (Designed for iPad).
- Share-household sheet opens and dismisses without crashing
  (we don't actually accept the share in UI tests — that needs a second
  device).

### Manual checklist (per TestFlight build)

These are the things that genuinely require multiple devices, real iCloud
accounts, or the photo-roll permission system. They are not "things we
gave up on" — they are integration checks that no in-process test can
honestly cover:

- Two phones, same iCloud account → second phone sees inserts within ~5s.
- Two phones, different accounts, share accepted → same.
- Airplane-mode write → reconnect → propagates without duplicates.
- Two members editing the same item while both offline → reconcile per §5.
- Photo attached on phone A appears on phone B (thumbnail first, full asset
  shortly after).
- Mac build (Designed for iPad) launches and can read/write.
- Notification fires at the expected local time and tapping it routes to
  the item.

If something on this list becomes flaky, the answer is to push it down into
the automated layer by improving the protocol abstraction, not to add
another manual step.

---

## 12. Future Considerations

These are not v1.0. They are listed so today's choices don't paint them into
a corner.

### Personal CLI (macOS)

A separate executable target in the same workspace, depending on
`NakedPantreeDomain` + `NakedPantreePersistence`. It opens the user's local
CloudKit-mirrored store read-only and exposes shell-friendly queries
(`pantry list`, `pantry expiring 7`). Personal use only — not shipped.

### AI ingredient queries

The query API on `NakedPantreePersistence` is shaped to answer "do I have
ingredient X?" cleanly: a search by item name with location and quantity
projected. An AI helper (LLM tool-use, MCP, whatever) calls into the same
package the CLI uses. The exact integration is TBD; the constraint we honor
today is that the persistence package never imports UIKit, so it stays
embeddable.

### Apple Reminders ("add to grocery list")

A button on `Item` detail. First tap presents an `EKEventStore`-backed list
picker; the chosen list id is persisted in `UserDefaults` (per-device).
Subsequent taps insert an `EKReminder` titled with the item name into that
list. One-way. Two-way sync (checking the reminder restocks the item) is a
later decision.

### Barcode scanning, OCR, recipe suggestions

All three were in non-goals during planning; they belong here because we do
expect to ship them, just not in v1.0.

- **Barcode scanning** — `DataScannerViewController` on iOS, looking up
  product names against a free product DB (OpenFoodFacts is the obvious
  start). Fast-path "add by scan" entry on the Items tab.
- **OCR** — `VisionKit`'s live text on the secondary photo of an item
  (ingredient list, expiry date stamped on packaging). Read-only at first
  — the user confirms before anything is written to the model.
- **Recipe suggestions** — given the household's current inventory and
  expiring-soon set, suggest recipes that use them. Likely a thin wrapper
  around the AI helper above; not its own subsystem.

---

## 13. Decisions Log

| # | Decision | Why |
| --- | --- | --- |
| 1 | Core Data over SwiftData | SwiftData lacks shared-DB support on iOS 26. |
| 2 | `Household` is the share root | One share per family; record zone moves with it. |
| 3 | `ItemPhoto` entity, not `Item.photoData` | Multi-photo (front, ingredients, back of box). |
| 4 | Last-write-wins per attribute | Acceptable for inventory; OT is overkill. |
| 5 | Dual-device notifications accepted | No backend → no dedup. Toggle later if needed. |
| 6 | `NavigationSplitView` from day one | Free iPad/Mac adaptive layout. |
| 7 | Local SwiftPM `Core` package | Future CLI and AI helper share the same domain. |
| 8 | "Designed for iPad on Mac," no Catalyst | Mac is a personal convenience, not a product. See §10 for the distinction. |
| 9 | Xcode Cloud for builds | Native TestFlight pipeline; less yak-shaving. |
| 10 | Reminders integration deferred | Nice-to-have; one-way when it ships. |
| 11 | Repository protocols in `NakedPantreeDomain` | Everything above storage is unit-testable without CloudKit. |
| 12 | Smart Lists above Locations in the sidebar | Inventory cleanup wants per-location; cooking/expiry wants cross-household. Both need first-class entry points. |
| 13 | Notifications stay plain; sass lives elsewhere | Voice rules from `DESIGN_GUIDELINES.md` §9 hold for time-sensitive pings. |
| 14 | Primary photo = `sortOrder == 0` | One photo per surface above; secondaries are one tap away. |
| 15 | Barcode/OCR/recipes are *future*, not non-goals | Calling them out separately keeps the v1.0 scope honest without pretending we'll never build them. |

---

## 14. Final Thought

The product is sharing, sync, and timely expiry alerts. Everything else is
chrome. When in doubt about a v1.0 decision, ask which option makes those
three things more reliable — and pick that one.
