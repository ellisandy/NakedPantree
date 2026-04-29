import CoreData
import Foundation
import Testing

@testable import NakedPantreePersistence

/// Sanity coverage for the `MultiStoreFixture` itself (issue #111) —
/// every test that depends on the fixture's correctness benefits from
/// pinning the invariants in one place.
@Suite("MultiStoreFixture")
struct MultiStoreFixtureTests {
    @Test("Both stores load and live at distinct, expected URLs")
    func bothStoresLoad() throws {
        let fixture = try MultiStoreFixture()
        defer { fixture.cleanup() }

        let stores = fixture.container.persistentStoreCoordinator.persistentStores
        #expect(stores.count == 2)

        let urls = stores.compactMap(\.url).map(\.lastPathComponent)
        #expect(urls.contains("NakedPantree-private.sqlite"))
        #expect(urls.contains("NakedPantree-shared.sqlite"))
    }

    @Test("CoreDataStack.privateCloudKitStore(in:) finds the private store")
    func privateStoreLookup() throws {
        let fixture = try MultiStoreFixture()
        defer { fixture.cleanup() }

        let privateStore = CoreDataStack.privateCloudKitStore(in: fixture.container)
        #expect(privateStore != nil)
        #expect(privateStore?.url?.lastPathComponent == "NakedPantree-private.sqlite")
    }

    @Test("CoreDataStack.sharedCloudKitStore(in:) finds the shared store")
    func sharedStoreLookup() throws {
        let fixture = try MultiStoreFixture()
        defer { fixture.cleanup() }

        let sharedStore = CoreDataStack.sharedCloudKitStore(in: fixture.container)
        #expect(sharedStore != nil)
        #expect(sharedStore?.url?.lastPathComponent == "NakedPantree-shared.sqlite")
    }

    @Test("Cleanup removes the per-instance directory")
    func cleanupRemovesDirectory() throws {
        let fixture = try MultiStoreFixture()
        let urls = fixture.container.persistentStoreCoordinator.persistentStores
            .compactMap(\.url)
        #expect(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })

        fixture.cleanup()
        // Files are gone, but the persistent stores still hold references
        // — `urls` was captured pre-cleanup. Verify by checking the
        // parent directory itself was removed.
        let parentDirectory = urls.first?.deletingLastPathComponent()
        if let parentDirectory {
            #expect(FileManager.default.fileExists(atPath: parentDirectory.path) == false)
        }
    }
}
