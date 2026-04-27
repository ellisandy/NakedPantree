import CoreData
import Foundation
import Testing
@testable import NakedPantree
@testable import NakedPantreePersistence

@Suite("RemoteChangeMonitor")
@MainActor
struct RemoteChangeMonitorTests {
    @Test("changeToken bumps when an NSPersistentStoreRemoteChange is posted")
    func changeTokenBumpsOnRemoteChangeNotification() async throws {
        let container = CoreDataStack.inMemoryContainer()
        let monitor = RemoteChangeMonitor(coordinator: container.persistentStoreCoordinator)
        let initial = monitor.changeToken

        NotificationCenter.default.post(
            name: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )

        // Yield to the observer Task long enough for it to deliver the
        // notification and hop to MainActor — a few runloop turns.
        try await waitFor(
            condition: { monitor.changeToken != initial },
            timeoutNanos: 1_000_000_000
        )
        #expect(monitor.changeToken != initial)
    }

    @Test("changeToken ignores notifications scoped to a different coordinator")
    func changeTokenIgnoresUnrelatedCoordinators() async throws {
        let containerA = CoreDataStack.inMemoryContainer(name: "A")
        let containerB = CoreDataStack.inMemoryContainer(name: "B")
        let monitor = RemoteChangeMonitor(coordinator: containerA.persistentStoreCoordinator)
        let initial = monitor.changeToken

        NotificationCenter.default.post(
            name: .NSPersistentStoreRemoteChange,
            object: containerB.persistentStoreCoordinator
        )

        // Give the observer a chance to be wrong; the token must not move.
        try await Task.sleep(nanoseconds: 250_000_000)
        #expect(monitor.changeToken == initial)
    }

    @Test("A flurry of notifications coalesces into a single token bump")
    func flurryCoalescesIntoSingleBump() async throws {
        let container = CoreDataStack.inMemoryContainer()
        let monitor = RemoteChangeMonitor(coordinator: container.persistentStoreCoordinator)
        let initial = monitor.changeToken

        // Fire five notifications back-to-back. Pre-debounce this would
        // bump the token five times in the same frame and trip SwiftUI's
        // "onChange tried to update multiple times per frame" warning.
        for _ in 0..<5 {
            NotificationCenter.default.post(
                name: .NSPersistentStoreRemoteChange,
                object: container.persistentStoreCoordinator
            )
        }

        // Wait past the debounce window for the first bump to land.
        try await waitFor(
            condition: { monitor.changeToken != initial },
            timeoutNanos: 1_000_000_000
        )
        let firstBump = monitor.changeToken
        #expect(firstBump != initial)

        // No further notifications — token must remain stable through
        // another debounce window.
        try await Task.sleep(nanoseconds: 250_000_000)
        #expect(monitor.changeToken == firstBump)
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
        let observing = RemoteChangeMonitor(coordinator: container.persistentStoreCoordinator)
        #expect(observing.isObserving == true)
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
