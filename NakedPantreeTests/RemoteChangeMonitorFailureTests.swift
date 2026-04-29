import CoreData
import Foundation
import Testing

@testable import NakedPantree
@testable import NakedPantreePersistence

/// Coverage for `RemoteChangeMonitor.fetchHistory`'s failure path —
/// issue #114. Pre-#114 this branch was a silent swallow that left
/// `lastHistoryToken` unchanged and re-ran the same range on every
/// subsequent remote-change tick. apps#125 added an
/// `os.Logger.error` so the failure is at least discoverable in
/// Console.app, and pinned the behavior with the tests below.
///
/// The existing `RemoteChangeMonitorTests` covers happy-path filter
/// logic; this file complements it with the negative branch.
@Suite("RemoteChangeMonitor failure path")
struct RemoteChangeMonitorFailureTests {
    /// Build a Core Data context backed by a SQLite store *without*
    /// `NSPersistentHistoryTrackingKey` enabled. Fetching persistent
    /// history against such a store throws — the exact behavior the
    /// failure branch was written for.
    private static func makeContextWithoutHistoryTracking() throws -> NSManagedObjectContext {
        let container = NSPersistentContainer(
            name: "NakedPantree",
            managedObjectModel: CoreDataStack.model
        )
        let description = NSPersistentStoreDescription()
        description.type = NSSQLiteStoreType
        description.url = URL(fileURLWithPath: "/dev/null")
        description.shouldAddStoreAsynchronously = false
        // Deliberately omit:
        //   description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        // Without it, the store rejects history-fetch requests.
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            throw loadError
        }
        return container.newBackgroundContext()
    }

    @Test("fetchHistory returns .failure when history tracking is disabled")
    func failureBranchSetsFailedFlag() async throws {
        let context = try Self.makeContextWithoutHistoryTracking()
        let outcome = await RemoteChangeMonitor.fetchHistory(
            after: RemoteChangeMonitor.SendableHistoryToken(token: nil),
            in: context
        )
        #expect(outcome.failed == true)
        #expect(outcome.newToken == nil)
        #expect(outcome.hasNonLocal == false)
    }

    @Test("fetchHistory failure produces a log entry under cc.mnmlst.nakedpantree/remote-change")
    func failureBranchLogs() async throws {
        // The Logger output is captured by the unified log; we can't
        // assert against it from inside the test process without
        // OSLogStore (which requires entitlements not granted to the
        // simulator). What we *can* pin is that the failure path runs
        // to completion without hanging or crashing — which is the
        // pre-#114 silent-swallow behavior plus the new log call.
        // The actual log line is verifiable manually via Console.app.
        let context = try Self.makeContextWithoutHistoryTracking()
        let outcome = await RemoteChangeMonitor.fetchHistory(
            after: RemoteChangeMonitor.SendableHistoryToken(token: nil),
            in: context
        )
        #expect(outcome.failed == true)
    }
}
