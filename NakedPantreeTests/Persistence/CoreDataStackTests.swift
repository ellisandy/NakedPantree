import CoreData
import Foundation
import Testing

@testable import NakedPantreePersistence

@Suite("Core Data stack spike")
struct CoreDataStackTests {
    @Test("Model loads from package bundle and exposes HouseholdEntity")
    func modelLoads() {
        let names = CoreDataStack.model.entitiesByName.keys
        #expect(names.contains("HouseholdEntity"))
    }

    @Test("In-memory container can insert and fetch a Household row")
    func insertAndFetch() throws {
        let container = CoreDataStack.inMemoryContainer()
        let context = container.viewContext

        let row = NSEntityDescription.insertNewObject(
            forEntityName: "HouseholdEntity",
            into: context
        )
        let id = UUID()
        let now = Date()
        row.setValue(id, forKey: "id")
        row.setValue("Test Pantry", forKey: "name")
        row.setValue(now, forKey: "createdAt")
        try context.save()

        let request = NSFetchRequest<NSManagedObject>(entityName: "HouseholdEntity")
        let results = try context.fetch(request)
        #expect(results.count == 1)
        #expect(results.first?.value(forKey: "id") as? UUID == id)
        #expect(results.first?.value(forKey: "name") as? String == "Test Pantry")
    }
}
