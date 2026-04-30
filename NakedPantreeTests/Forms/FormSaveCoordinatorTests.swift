import Foundation
import Testing

@testable import NakedPantree
@testable import NakedPantreeDomain

// MARK: - Item form

@MainActor
@Suite("ItemFormSaveCoordinator")
struct ItemFormSaveCoordinatorTests {
    @Test("isValid(name:) — empty / whitespace returns false")
    func isValidEmptyAndWhitespace() {
        #expect(!ItemFormSaveCoordinator.isValid(name: ""))
        #expect(!ItemFormSaveCoordinator.isValid(name: "   "))
        #expect(!ItemFormSaveCoordinator.isValid(name: "\t \n"))
    }

    @Test("isValid(name:) — non-empty (with or without padding) returns true")
    func isValidNonEmpty() {
        #expect(ItemFormSaveCoordinator.isValid(name: "Apples"))
        #expect(ItemFormSaveCoordinator.isValid(name: "  Apples  "))
    }

    /// The combination test for the create branch: trims the name,
    /// collapses whitespace-only notes to nil, drops the expiry when
    /// `hasExpiry` is false, and persists the resulting item to the
    /// repo. One test instead of three because the trim/collapse logic
    /// is a single statement per field — splitting hides whether the
    /// branches compose.
    @Test("Create — name trimmed; whitespace-only notes → nil; toggle-off clears expiry")
    func createTrimsCollapsesAndClearsExpiry() async throws {
        let repo = InMemoryItemRepository()
        let center = StubNotificationCenter()
        let scheduler = NotificationScheduler(servicing: center)
        let locationID = UUID()

        let draft = ItemFormDraft(
            locationID: locationID,
            name: "  Sourdough  ",
            quantity: 2,
            unit: .count,
            // Toggle off — even with `expiresAt` set the persisted
            // item should land with `nil` expiry.
            hasExpiry: false,
            expiresAt: .now.addingTimeInterval(60 * 60 * 24 * 30),
            notes: "   "
        )

        let saved = try await ItemFormSaveCoordinator.save(
            mode: .create(locationID: locationID),
            draft: draft,
            repository: repo,
            scheduler: scheduler
        )

        #expect(saved.name == "Sourdough")
        #expect(saved.notes == nil)
        #expect(saved.expiresAt == nil)
        #expect(saved.locationID == locationID)
        #expect(saved.quantity == 2)

        let persisted = try await repo.items(in: locationID)
        #expect(persisted.count == 1)
        #expect(persisted.first?.name == "Sourdough")
        #expect(persisted.first?.notes == nil)
    }

    @Test("Create with future expiry — scheduler adds a request keyed to the item id")
    func createWithExpiryAddsRequest() async throws {
        let repo = InMemoryItemRepository()
        let center = StubNotificationCenter()
        let scheduler = NotificationScheduler(servicing: center)
        let locationID = UUID()

        // 30 days out — comfortably past the 3-day lead window so
        // `expiryNotificationTriggerDate` resolves a real future date
        // and the "add" branch runs.
        let future = Date.now.addingTimeInterval(60 * 60 * 24 * 30)
        let draft = ItemFormDraft(
            locationID: locationID,
            name: "Tomatoes",
            quantity: 1,
            unit: .count,
            hasExpiry: true,
            expiresAt: future,
            notes: "Heirlooms"
        )

        let saved = try await ItemFormSaveCoordinator.save(
            mode: .create(locationID: locationID),
            draft: draft,
            repository: repo,
            scheduler: scheduler
        )

        #expect(saved.expiresAt == future)
        #expect(saved.notes == "Heirlooms")

        let added = center.addedRequests
        #expect(added.count == 1)
        #expect(added.first?.identifier == "item.\(saved.id.uuidString).expiry")
    }

    @Test("Create with hasExpiry=false — scheduler removes any prior pending request")
    func createNoExpiryRemoves() async throws {
        let repo = InMemoryItemRepository()
        let center = StubNotificationCenter()
        let scheduler = NotificationScheduler(servicing: center)
        let locationID = UUID()

        let draft = ItemFormDraft(
            locationID: locationID,
            name: "Tinned tuna",
            quantity: 4,
            unit: .count,
            hasExpiry: false,
            expiresAt: .now.addingTimeInterval(60 * 60 * 24 * 30),
            notes: ""
        )

        let saved = try await ItemFormSaveCoordinator.save(
            mode: .create(locationID: locationID),
            draft: draft,
            repository: repo,
            scheduler: scheduler
        )

        #expect(saved.expiresAt == nil)
        // The nil-expiry branch in `scheduleIfNeeded` calls
        // `removePendingNotificationRequests` for the item's identifier
        // — even on a brand-new item, since it's idempotent and lets
        // the scheduler stay symmetric for create vs edit.
        let removed = center.removedIdentifiersBatches
        #expect(removed.count == 1)
        let expected = "item.\(saved.id.uuidString).expiry"
        #expect(removed.first?.contains(expected) == true)
        #expect(center.addedRequests.isEmpty)
    }

    @Test("Edit — preserves id/createdAt; updates editable fields; toggle-off cancels expiry")
    func editPreservesIdAndCancelsOldExpiry() async throws {
        let originalCreated = Date(timeIntervalSince1970: 1_700_000_000)
        let original = Item(
            id: UUID(),
            locationID: UUID(),
            name: "Bread",
            quantity: 1,
            unit: .count,
            expiresAt: .now.addingTimeInterval(60 * 60 * 24 * 30),
            notes: "Old note",
            createdAt: originalCreated
        )
        let repo = InMemoryItemRepository(initial: [original])
        let center = StubNotificationCenter()
        let scheduler = NotificationScheduler(servicing: center)

        let draft = ItemFormDraft(
            // Same locationID as the original — this test pins the
            // edit-without-move case. Issue #134's move-on-edit case
            // is covered separately in `editReassignsLocationID`.
            locationID: original.locationID,
            name: "  Sourdough  ",
            quantity: 3,
            unit: .package,
            // User flipped the expiry toggle off — the persisted item
            // should land with `nil` expiry and the scheduler should
            // cancel the pending request keyed by the (preserved) id.
            hasExpiry: false,
            expiresAt: .now.addingTimeInterval(60 * 60 * 24 * 30),
            notes: "  fresh  "
        )

        let saved = try await ItemFormSaveCoordinator.save(
            mode: .edit(original),
            draft: draft,
            repository: repo,
            scheduler: scheduler
        )

        #expect(saved.id == original.id)
        #expect(saved.createdAt == originalCreated)
        #expect(saved.name == "Sourdough")
        #expect(saved.quantity == 3)
        #expect(saved.unit == .package)
        #expect(saved.notes == "fresh")
        #expect(saved.expiresAt == nil)

        let expected = "item.\(original.id.uuidString).expiry"
        let removed = center.removedIdentifiersBatches
        // The cancellation may interleave with the protocol's own
        // background sweeps, so use `flatMap` rather than checking
        // a specific batch index.
        let removedFlat = removed.flatMap { $0 }
        #expect(removedFlat.contains(expected))
    }

    /// Issue #134: edit-mode save honours the draft's `locationID` —
    /// the picker can move an item between locations. Pins the
    /// behavior that #134 added so a future refactor that drops
    /// the line `updated.locationID = draft.locationID` (it would
    /// be easy to overlook in a sweep) fails the test rather than
    /// silently sending every move-edit back to the original
    /// location.
    @Test("Edit — draft locationID overrides the original (move between locations)")
    func editReassignsLocationID() async throws {
        let oldLocation = UUID()
        let newLocation = UUID()
        let original = Item(
            id: UUID(),
            locationID: oldLocation,
            name: "Chili",
            quantity: 1,
            unit: .count,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let repo = InMemoryItemRepository(initial: [original])
        let center = StubNotificationCenter()
        let scheduler = NotificationScheduler(servicing: center)

        let draft = ItemFormDraft(
            // The draft says "save into the new location" — the
            // edit branch must respect that, not fall back to
            // `original.locationID`.
            locationID: newLocation,
            name: "Chili",
            quantity: 1,
            unit: .count,
            hasExpiry: false,
            expiresAt: .now,
            notes: ""
        )

        let saved = try await ItemFormSaveCoordinator.save(
            mode: .edit(original),
            draft: draft,
            repository: repo,
            scheduler: scheduler
        )

        #expect(saved.id == original.id, "Move must preserve item identity.")
        #expect(saved.createdAt == original.createdAt, "Move must preserve createdAt.")
        #expect(saved.locationID == newLocation, "Move must reassign locationID.")

        // Repo round-trip: the item lives at the new location now,
        // not the old one. `items(in:)` is the surface UI uses to
        // populate per-location lists, so this is the contract that
        // makes the sidebar list show the moved item correctly.
        let fromOldLocation = try await repo.items(in: oldLocation)
        let fromNewLocation = try await repo.items(in: newLocation)
        #expect(fromOldLocation.isEmpty, "Old location should no longer contain the item.")
        #expect(fromNewLocation.contains(where: { $0.id == original.id }))
    }

    /// Issue #153: the draft's `restockThreshold` is the form's
    /// toggle+stepper collapsed into the optional domain field.
    /// Pin that the create branch hands the threshold straight
    /// through to the persisted item. The auto-flag-when-low rule
    /// itself is the repository's responsibility — covered by the
    /// `ItemRepository` contract test in `RepositoryContractTests`.
    @Test("Create — draft restockThreshold flows through to the persisted item")
    func createPersistsRestockThreshold() async throws {
        let repo = InMemoryItemRepository()
        let center = StubNotificationCenter()
        let scheduler = NotificationScheduler(servicing: center)
        let locationID = UUID()

        let draft = ItemFormDraft(
            locationID: locationID,
            name: "Milk",
            quantity: 5,
            unit: .count,
            hasExpiry: false,
            expiresAt: .now,
            notes: "",
            restockThreshold: 2
        )

        let saved = try await ItemFormSaveCoordinator.save(
            mode: .create(locationID: locationID),
            draft: draft,
            repository: repo,
            scheduler: scheduler
        )

        #expect(saved.restockThreshold == 2)
        // Quantity 5 > threshold 2 — the auto-flag rule shouldn't fire,
        // so `needsRestocking` stays at the default `false`.
        #expect(saved.needsRestocking == false)
    }

    @Test("Edit — draft restockThreshold updates and can be cleared back to nil")
    func editUpdatesAndClearsRestockThreshold() async throws {
        let originalCreated = Date(timeIntervalSince1970: 1_700_000_000)
        let original = Item(
            id: UUID(),
            locationID: UUID(),
            name: "Milk",
            quantity: 3,
            unit: .count,
            restockThreshold: 1,
            createdAt: originalCreated
        )
        let repo = InMemoryItemRepository(initial: [original])
        let center = StubNotificationCenter()
        let scheduler = NotificationScheduler(servicing: center)

        // First edit: bump threshold to 5.
        var draft = ItemFormDraft(
            locationID: original.locationID,
            name: "Milk",
            quantity: 3,
            unit: .count,
            hasExpiry: false,
            expiresAt: .now,
            notes: "",
            restockThreshold: 5
        )
        var saved = try await ItemFormSaveCoordinator.save(
            mode: .edit(original),
            draft: draft,
            repository: repo,
            scheduler: scheduler
        )
        #expect(saved.restockThreshold == 5)

        // Second edit: turn the threshold off (toggle → nil draft).
        draft.restockThreshold = nil
        saved = try await ItemFormSaveCoordinator.save(
            mode: .edit(saved),
            draft: draft,
            repository: repo,
            scheduler: scheduler
        )
        #expect(saved.restockThreshold == nil)
    }

    @Test("Repository error — propagates and scheduler is never called")
    func repositoryErrorPropagates() async throws {
        let repo = ThrowingItemRepository()
        let center = StubNotificationCenter()
        let scheduler = NotificationScheduler(servicing: center)

        let draft = ItemFormDraft(
            locationID: UUID(),
            name: "Bread",
            quantity: 1,
            unit: .count,
            hasExpiry: true,
            expiresAt: .now.addingTimeInterval(60 * 60 * 24 * 30),
            notes: ""
        )

        await #expect(throws: FormCoordinatorTestError.self) {
            _ = try await ItemFormSaveCoordinator.save(
                mode: .create(locationID: UUID()),
                draft: draft,
                repository: repo,
                scheduler: scheduler
            )
        }
        // Scheduler intentionally runs after the repo write succeeds.
        // A repo throw should leave both stub buckets untouched —
        // catches a regression that swaps the order or swallows the
        // error.
        #expect(center.addedRequests.isEmpty)
        #expect(center.removedIdentifiersBatches.isEmpty)
    }

    /// Issue #109: writes are local-first regardless of iCloud account
    /// status. `NSPersistentCloudKitContainer` queues unsynced writes in
    /// its local store and replays them once the account becomes
    /// `.available` again, so threading `AccountStatusMonitor` into the
    /// save path would only degrade offline-first behavior without
    /// preventing data loss. This binding pins the parameter list — if
    /// a future refactor adds a required `monitor:` parameter, the
    /// assignment fails to compile and forces a re-read of the policy
    /// doc in `AccountStatusMonitor.swift`.
    @Test("Issue #109: save signature has no AccountStatusMonitor parameter")
    func saveSignatureOmitsAccountStatusGuard() {
        let _:
            (
                ItemFormView.Mode, ItemFormDraft, any ItemRepository, NotificationScheduler
            ) async throws -> Item = ItemFormSaveCoordinator.save
    }
}

// MARK: - Location form

@MainActor
@Suite("LocationFormSaveCoordinator")
struct LocationFormSaveCoordinatorTests {
    @Test("isValid(name:) — empty/whitespace false; non-empty true")
    func isValidPredicate() {
        #expect(!LocationFormSaveCoordinator.isValid(name: ""))
        #expect(!LocationFormSaveCoordinator.isValid(name: "   "))
        #expect(LocationFormSaveCoordinator.isValid(name: "Pantry"))
        #expect(LocationFormSaveCoordinator.isValid(name: "  Pantry "))
    }

    @Test("Create — name trimmed; kind preserved; persisted to the household")
    func createTrimsAndPersists() async throws {
        let repo = InMemoryLocationRepository()
        let householdID = UUID()
        let draft = LocationFormDraft(name: "  Garage Freezer  ", kind: .freezer)

        let saved = try await LocationFormSaveCoordinator.save(
            mode: .create(householdID: householdID),
            draft: draft,
            repository: repo
        )

        #expect(saved.name == "Garage Freezer")
        #expect(saved.kind == .freezer)
        #expect(saved.householdID == householdID)

        let persisted = try await repo.locations(in: householdID)
        #expect(persisted.count == 1)
        #expect(persisted.first?.name == "Garage Freezer")
        #expect(persisted.first?.kind == .freezer)
    }

    @Test("Edit — preserves id/createdAt; updates name and kind")
    func editPreservesIdentity() async throws {
        let originalCreated = Date(timeIntervalSince1970: 1_700_000_000)
        let householdID = UUID()
        let original = Location(
            id: UUID(),
            householdID: householdID,
            name: "Kitchen",
            kind: .pantry,
            createdAt: originalCreated
        )
        let repo = InMemoryLocationRepository()
        try await repo.create(original)

        let draft = LocationFormDraft(name: "  Pantry Shelf  ", kind: .dryGoods)
        let saved = try await LocationFormSaveCoordinator.save(
            mode: .edit(original),
            draft: draft,
            repository: repo
        )

        #expect(saved.id == original.id)
        #expect(saved.createdAt == originalCreated)
        #expect(saved.name == "Pantry Shelf")
        #expect(saved.kind == .dryGoods)
        #expect(saved.householdID == householdID)
    }

    @Test("Repository error — propagates")
    func repositoryErrorPropagates() async throws {
        let repo = ThrowingLocationRepository()
        let draft = LocationFormDraft(name: "Pantry", kind: .pantry)
        await #expect(throws: FormCoordinatorTestError.self) {
            _ = try await LocationFormSaveCoordinator.save(
                mode: .create(householdID: UUID()),
                draft: draft,
                repository: repo
            )
        }
    }

    /// Companion to `ItemFormSaveCoordinatorTests.saveSignatureOmitsAccountStatusGuard`.
    /// Same intent: pin the parameter list so issue #109's local-first
    /// policy can't be silently undone. See the policy paragraph in
    /// `AccountStatusMonitor.swift` for the rationale.
    @Test("Issue #109: save signature has no AccountStatusMonitor parameter")
    func saveSignatureOmitsAccountStatusGuard() {
        let _:
            (
                LocationFormView.Mode, LocationFormDraft, any LocationRepository
            ) async throws -> Location = LocationFormSaveCoordinator.save
    }
}

// MARK: - Throwing repository stubs

private struct FormCoordinatorTestError: Error, Equatable {}

/// Always-throwing `ItemRepository` for verifying the coordinator's
/// error propagation. Reads return empty so accidental "did we read
/// before we wrote?" regressions don't blow up before we hit the
/// throwing branch under test.
private actor ThrowingItemRepository: ItemRepository {
    func items(in locationID: Location.ID) async throws -> [Item] { [] }
    func item(id: Item.ID) async throws -> Item? { nil }
    func allItems(in householdID: Household.ID) async throws -> [Item] { [] }
    func search(_ query: String, in householdID: Household.ID) async throws -> [Item] { [] }
    func create(_ item: Item) async throws { throw FormCoordinatorTestError() }
    func update(_ item: Item) async throws { throw FormCoordinatorTestError() }
    func updateQuantity(id: Item.ID, quantity: Int32) async throws {
        throw FormCoordinatorTestError()
    }
    func setNeedsRestocking(id: Item.ID, needsRestocking: Bool) async throws {
        throw FormCoordinatorTestError()
    }
    func needsRestocking(in householdID: Household.ID) async throws -> [Item] { [] }
    func delete(id: Item.ID) async throws { throw FormCoordinatorTestError() }
}

private actor ThrowingLocationRepository: LocationRepository {
    func locations(in householdID: Household.ID) async throws -> [Location] { [] }
    func location(id: Location.ID) async throws -> Location? { nil }
    func create(_ location: Location) async throws { throw FormCoordinatorTestError() }
    func update(_ location: Location) async throws { throw FormCoordinatorTestError() }
    func delete(id: Location.ID) async throws { throw FormCoordinatorTestError() }
}
