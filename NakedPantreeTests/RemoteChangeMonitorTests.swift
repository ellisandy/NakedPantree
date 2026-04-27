import CoreData
import Foundation
import Testing
@testable import NakedPantree
@testable import NakedPantreePersistence

@Suite("RemoteChangeMonitor")
@MainActor
struct RemoteChangeMonitorTests {
    @Test("A non-local transaction (author != \"local\") bumps changeToken")
    func nonLocalTransactionBumpsChangeToken() async throws {
        let container = CoreDataStack.inMemoryContainer()
        let defaults = makeIsolatedDefaults()
        let monitor = RemoteChangeMonitor(container: container, defaults: defaults)
        let initial = monitor.changeToken

        // Simulate a CloudKit-mirrored import by saving on a context
        // whose `transactionAuthor` is left nil — that's what the
        // mirror does. The remote-change notification posts on save.
        try await save(in: container, transactionAuthor: nil) { context in
            insertHousehold(name: "Remote", into: context)
        }

        try await waitFor(
            condition: { monitor.changeToken != initial },
            timeoutNanos: 2_000_000_000
        )
        #expect(monitor.changeToken != initial)
    }

    @Test("A local-author save does NOT bump changeToken")
    func localAuthorSaveDoesNotBumpChangeToken() async throws {
        let container = CoreDataStack.inMemoryContainer()
        let defaults = makeIsolatedDefaults()
        let monitor = RemoteChangeMonitor(container: container, defaults: defaults)
        let initial = monitor.changeToken

        // Mirror what `performBackgroundTaskWithDefaults` does — stamp
        // the context with `"local"` before saving. Phase 10.4 makes
        // every production write land here, so the observer should
        // ignore the resulting remote-change notification.
        try await save(
            in: container,
            transactionAuthor: CoreDataStack.localTransactionAuthor
        ) { context in
            insertHousehold(name: "Local", into: context)
        }

        // Wait past the debounce window; if the token was going to
        // bump, it would have. Verify it didn't.
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(monitor.changeToken == initial)
    }

    @Test("Notifications scoped to a different coordinator are ignored")
    func changeTokenIgnoresUnrelatedCoordinators() async throws {
        let containerA = CoreDataStack.inMemoryContainer(name: "A")
        let containerB = CoreDataStack.inMemoryContainer(name: "B")
        let defaults = makeIsolatedDefaults()
        let monitor = RemoteChangeMonitor(container: containerA, defaults: defaults)
        let initial = monitor.changeToken

        // A non-local save on B fires NSPersistentStoreRemoteChange
        // scoped to B's coordinator. The monitor subscribed to A's
        // coordinator must not receive it.
        try await save(in: containerB, transactionAuthor: nil) { context in
            insertHousehold(name: "OtherStore", into: context)
        }

        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(monitor.changeToken == initial)
    }

    @Test("A flurry of non-local saves coalesces into a single token bump")
    func flurryCoalescesIntoSingleBump() async throws {
        let container = CoreDataStack.inMemoryContainer()
        let defaults = makeIsolatedDefaults()
        let monitor = RemoteChangeMonitor(container: container, defaults: defaults)
        let initial = monitor.changeToken

        // Five back-to-back non-local saves. Pre-debounce this would
        // bump the token five times in the same frame and trip
        // SwiftUI's "onChange tried to update multiple times per
        // frame" warning.
        for index in 0..<5 {
            try await save(in: container, transactionAuthor: nil) { context in
                insertHousehold(name: "Remote\(index)", into: context)
            }
        }

        try await waitFor(
            condition: { monitor.changeToken != initial },
            timeoutNanos: 2_000_000_000
        )
        let firstBump = monitor.changeToken
        #expect(firstBump != initial)

        // Quiet window — no further notifications, no further bumps.
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(monitor.changeToken == firstBump)
    }

    @Test("History token persists across monitor instances (simulated restart)")
    func historyTokenPersistsAcrossRestart() async throws {
        let container = CoreDataStack.inMemoryContainer()
        let defaults = makeIsolatedDefaults()

        // First "process": create a monitor, drive a non-local save,
        // wait for the bump, then tear it down. The persisted token
        // captures the post-save state.
        do {
            let monitor = RemoteChangeMonitor(container: container, defaults: defaults)
            let initial = monitor.changeToken
            try await save(in: container, transactionAuthor: nil) { context in
                insertHousehold(name: "FirstRun", into: context)
            }
            try await waitFor(
                condition: { monitor.changeToken != initial },
                timeoutNanos: 2_000_000_000
            )
            #expect(monitor.changeToken != initial)
        }

        // The persisted token must be present.
        let persisted = defaults.data(forKey: RemoteChangeMonitor.historyTokenDefaultsKey)
        #expect(persisted != nil)

        // Second "process": new monitor over the same defaults. A
        // local-author save now should NOT bump — proving the new
        // monitor read the persisted token (otherwise it would refetch
        // history from epoch, see the earlier non-local save, and
        // bump on the very first refresh).
        let secondMonitor = RemoteChangeMonitor(container: container, defaults: defaults)
        let secondInitial = secondMonitor.changeToken
        try await save(
            in: container,
            transactionAuthor: CoreDataStack.localTransactionAuthor
        ) { context in
            insertHousehold(name: "SecondRunLocal", into: context)
        }
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(secondMonitor.changeToken == secondInitial)
    }

    @Test("No-op monitor never bumps")
    func noOpMonitorNeverBumps() async throws {
        let monitor = RemoteChangeMonitor()
        let initial = monitor.changeToken

        NotificationCenter.default.post(
            name: .NSPersistentStoreRemoteChange,
            object: nil
        )

        try await Task.sleep(nanoseconds: 250_000_000)
        #expect(monitor.changeToken == initial)
    }

    @Test("isObserving distinguishes the two initializers")
    func isObservingReflectsInitializer() {
        // Phase 8.2: `BootstrapService`'s deferred-bootstrap waiter
        // skips the wait when `isObserving == false` because the no-op
        // monitor will never tick. Pin both shapes here so a future
        // refactor that drops the flag breaks loudly.
        let noOp = RemoteChangeMonitor()
        #expect(noOp.isObserving == false)

        let container = CoreDataStack.inMemoryContainer()
        let defaults = makeIsolatedDefaults()
        let observing = RemoteChangeMonitor(container: container, defaults: defaults)
        #expect(observing.isObserving == true)
    }

    // MARK: - Helpers

    /// Fresh `UserDefaults` per test so parallel test runs and the
    /// "simulated restart" test don't stomp on each other's persisted
    /// tokens. Mirrors the per-test isolation `NotificationSettings`
    /// tests use.
    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "RemoteChangeMonitorTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create UserDefaults suite \(suiteName)")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    /// Inserts a HouseholdEntity row and saves on a background context
    /// whose `transactionAuthor` we control. Returning before the
    /// `NSPersistentStoreRemoteChange` notification has been posted is
    /// fine — the monitor's debounce gives us a window to observe.
    nonisolated private func save(
        in container: NSPersistentContainer,
        transactionAuthor: String?,
        _ block: @Sendable @escaping (NSManagedObjectContext) -> Void
    ) async throws {
        try await container.performBackgroundTask { context in
            context.mergePolicy = CoreDataStack.defaultMergePolicy
            context.transactionAuthor = transactionAuthor
            block(context)
            try context.save()
        }
    }

    /// Inserts a `HouseholdEntity` with the minimum required attributes
    /// — using the model directly, no repository dependency — so a
    /// `context.save()` on this context produces exactly one persistent-
    /// history transaction.
    nonisolated private static func insertHousehold(
        name: String,
        into context: NSManagedObjectContext
    ) {
        let row = NSEntityDescription.insertNewObject(
            forEntityName: "HouseholdEntity",
            into: context
        )
        row.setValue(UUID(), forKey: "id")
        row.setValue(name, forKey: "name")
        row.setValue(Date(), forKey: "createdAt")
    }

    /// Static-method shim so call sites read `insertHousehold(...)` and
    /// not `RemoteChangeMonitorTests.insertHousehold(...)`.
    nonisolated private func insertHousehold(
        name: String,
        into context: NSManagedObjectContext
    ) {
        Self.insertHousehold(name: name, into: context)
    }

    private func waitFor(
        condition: @MainActor () -> Bool,
        timeoutNanos: UInt64
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int(timeoutNanos)))
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
