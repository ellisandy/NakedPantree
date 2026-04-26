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
        try await waitFor(condition: { monitor.changeToken != initial }, timeoutNanos: 1_000_000_000)
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
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(monitor.changeToken == initial)
    }

    @Test("No-op monitor never bumps")
    func noOpMonitorNeverBumps() async throws {
        let monitor = RemoteChangeMonitor()
        let initial = monitor.changeToken

        NotificationCenter.default.post(
            name: .NSPersistentStoreRemoteChange,
            object: nil
        )

        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(monitor.changeToken == initial)
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
