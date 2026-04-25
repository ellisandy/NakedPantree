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
- Users can attach photos to items (e.g. the back of a waffle-mix box).
- The app runs on iPad (adaptive) and on Apple Silicon Macs via "Designed
  for iPad on Mac."

### Non-goals (v1.0)

- Web app, Android app, or a separate native macOS app.
- Barcode scanning, OCR, recipe suggestions.
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
| Tests | Swift Testing |
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
    Core/                          # local SwiftPM package
      Sources/
        NakedPantreeDomain/        # entities, enums, value types — no Core Data import
        NakedPantreePersistence/   # NSPersistentCloudKitContainer, repositories, queries
      Tests/
  NakedPantreeTests/               # app-level integration & UI tests
  assets/brand/                    # existing brand tokens (colors.json)
  DESIGN_GUIDELINES.md
  ARCHITECTURE.md                  # this file
```

The Core SwiftPM package exists from day one. The future macOS CLI and any AI
query helper will depend on it; the iOS app does too. This keeps the query
surface honest — anything the CLI needs has to be reachable without importing
UIKit.

---

## 4. Domain Model

Four entities. Relationships are optional with inverses, every attribute has a
default — both are CloudKit constraints, not stylistic choices.

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
| `unitRaw` | String | Default `"count"` |
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
| `sortOrder` | Int16 | Default `0` |
| `createdAt` | Date | |
| `item` | `Item?` | Inverse |

A separate entity (rather than a `photoData` attribute on `Item`) so an item
can carry the front, the ingredient list, and the back of a waffle-mix box
without growing the `Item` row.

### Constraints we are *not* using

- **No unique constraints.** CloudKit-mirrored stores reject them. Uniqueness
  by `id: UUID` is enforced at the application level on insert.
- **No required relationships.** CloudKit requires every relationship to be
  optional and bidirectional.

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
| Sidebar | Locations list (drilled) | Locations list |
| Content | Items in selected location | Items in selected location |
| Detail | Item detail (pushed) | Item detail (visible) |

This gives us iPad's two-pane and Mac's three-pane layout for free, with no
size-class branching code. On iPhone the split view collapses to the standard
push stack automatically.

We deliberately avoid `TabView` at the root — locations *are* the navigation.

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

---

## 10. Distribution & CI

- Single iOS app target. `iPad` is added to "Supported Destinations." "Mac
  (Designed for iPad)" is enabled — no Catalyst.
- **Xcode Cloud** runs on every PR (build + tests) and on merges to `main`
  (TestFlight beta upload, internal group).
- GitHub Actions is reserved for lint and `swift-format` checks that don't
  need an Xcode runner.
- Versioned Core Data model from day one (`Model.xcdatamodeld` with a `v1`
  version inside). Lightweight migration enabled. CloudKit schema changes
  are deployed to Production via the CloudKit Console after the dev schema
  has shipped to a TestFlight build that exercises every new field.

---

## 11. Testing

### Swift Testing covers

- `NakedPantreeDomain` enums (raw-value stability — breaking these breaks
  sync).
- `NotificationScheduler` reschedule logic against an in-memory store.
- Repository queries (search, expiring-soon window).
- Migration tests when the model bumps a version.

### Manual checklist (per release)

- Two phones, same iCloud account → second phone sees inserts within ~5s.
- Two phones, different accounts, share accepted → same.
- Airplane-mode write → reconnect → propagates without duplicates.
- Photo attached on phone A appears on phone B (thumbnail first, full asset
  shortly after).
- Mac build launches and can read/write.

CloudKit cannot be meaningfully unit-tested; we don't pretend otherwise.

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
| 8 | "Designed for iPad on Mac," no Catalyst | Mac is a personal convenience, not a product. |
| 9 | Xcode Cloud for builds | Native TestFlight pipeline; less yak-shaving. |
| 10 | Reminders integration deferred | Nice-to-have; one-way when it ships. |

---

## 14. Final Thought

The product is sharing, sync, and timely expiry alerts. Everything else is
chrome. When in doubt about a v1.0 decision, ask which option makes those
three things more reliable — and pick that one.
