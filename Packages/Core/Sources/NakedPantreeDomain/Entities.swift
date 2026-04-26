import Foundation

/// The share root. One household per `CKShare`. See `ARCHITECTURE.md` §4.
///
/// Children are referenced by id from the child side (`Location.householdID`)
/// rather than as a `[Location]` inside this struct — value types model the
/// node, the repository surfaces the relationship.
public struct Household: Sendable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    public let createdAt: Date

    public init(id: UUID = UUID(), name: String = "My Pantry", createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

/// A physical storage location within a household — pantry, fridge, freezer,
/// dry goods, or other.
public struct Location: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let householdID: Household.ID
    public var name: String
    public var kind: LocationKind
    public var sortOrder: Int16
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        householdID: Household.ID,
        name: String,
        kind: LocationKind = .pantry,
        sortOrder: Int16 = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.householdID = householdID
        self.name = name
        self.kind = kind
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

/// An inventory item. `updatedAt` is stamped by the repository on every edit
/// — callers should not set it directly. See `ItemRepository.update(_:)`.
public struct Item: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let locationID: Location.ID
    public var name: String
    public var quantity: Int32
    public var unit: Unit
    public var expiresAt: Date?
    public var notes: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        locationID: Location.ID,
        name: String,
        quantity: Int32 = 1,
        unit: Unit = .count,
        expiresAt: Date? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.locationID = locationID
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.expiresAt = expiresAt
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A photo attached to an item. The lowest `sortOrder` photo is the primary
/// (the one shown in lists, grids, and the item header); the rest are
/// secondary reference shots. See `ARCHITECTURE.md` §4.
public struct ItemPhoto: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let itemID: Item.ID
    public var imageData: Data?
    public var thumbnailData: Data?
    public var caption: String?
    public var sortOrder: Int16
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        itemID: Item.ID,
        imageData: Data? = nil,
        thumbnailData: Data? = nil,
        caption: String? = nil,
        sortOrder: Int16 = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.itemID = itemID
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.caption = caption
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
