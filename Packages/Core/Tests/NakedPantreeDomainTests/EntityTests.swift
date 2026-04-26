import Foundation
import Testing
@testable import NakedPantreeDomain

@Suite("Entity defaults")
struct EntityDefaultsTests {
    @Test("Household defaults match the bootstrap contract")
    func householdDefaults() {
        let household = Household()
        #expect(household.name == "My Pantry")
    }

    @Test("Location defaults to .pantry kind and sortOrder 0")
    func locationDefaults() {
        let household = Household()
        let location = Location(householdID: household.id, name: "Kitchen")
        #expect(location.kind == .pantry)
        #expect(location.sortOrder == 0)
        #expect(location.householdID == household.id)
    }

    @Test("Item defaults to quantity 1, unit .count, and no expiry")
    func itemDefaults() {
        let location = Location(householdID: UUID(), name: "Kitchen")
        let item = Item(locationID: location.id, name: "Tomatoes")
        #expect(item.quantity == 1)
        #expect(item.unit == .count)
        #expect(item.expiresAt == nil)
        #expect(item.notes == nil)
        #expect(item.locationID == location.id)
    }

    @Test("ItemPhoto defaults to sortOrder 0 and no payload")
    func itemPhotoDefaults() {
        let item = Item(locationID: UUID(), name: "Tomatoes")
        let photo = ItemPhoto(itemID: item.id)
        #expect(photo.sortOrder == 0)
        #expect(photo.imageData == nil)
        #expect(photo.thumbnailData == nil)
        #expect(photo.caption == nil)
        #expect(photo.itemID == item.id)
    }
}
