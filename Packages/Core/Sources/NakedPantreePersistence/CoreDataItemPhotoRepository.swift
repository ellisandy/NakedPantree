import CoreData
import Foundation
import NakedPantreeDomain

/// `ItemPhotoRepository` backed by `NSPersistentContainer`. Same
/// Sendable trade-off as `CoreDataHouseholdRepository` — see that file.
public final class CoreDataItemPhotoRepository: ItemPhotoRepository, @unchecked Sendable {
    private let container: NSPersistentContainer

    public init(container: NSPersistentContainer) {
        self.container = container
    }

    public func photos(for itemID: Item.ID) async throws -> [ItemPhoto] {
        try await container.performBackgroundTaskWithDefaults { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ItemPhotoEntity")
            request.predicate = NSPredicate(format: "item.id == %@", itemID as CVarArg)
            request.sortDescriptors = [
                NSSortDescriptor(key: "sortOrder", ascending: true),
                NSSortDescriptor(key: "createdAt", ascending: true),
            ]
            return try context.fetch(request).map(Self.makePhoto)
        }
    }

    public func create(_ photo: ItemPhoto) async throws {
        try await container.performBackgroundTaskWithDefaults { [container] context in
            let row = NSEntityDescription.insertNewObject(
                forEntityName: "ItemPhotoEntity",
                into: context
            )
            try Self.assignAttributes(photo, to: row)
            // Set parent first, then assign new row to the same store —
            // see `CoreDataLocationRepository.assignToParentStore` for
            // the cross-store-relationship rationale.
            let item = try Self.attachItem(photo.itemID, to: row, in: context)
            Self.assignToParentStore(row, parent: item, container: container, in: context)
            try context.save()
        }
    }

    public func update(_ photo: ItemPhoto) async throws {
        try await container.performBackgroundTaskWithDefaults { [container] context in
            let row: NSManagedObject
            let isNew: Bool
            if let existing = try Self.fetchPhotoRow(id: photo.id, in: context) {
                row = existing
                isNew = false
            } else {
                row = NSEntityDescription.insertNewObject(
                    forEntityName: "ItemPhotoEntity",
                    into: context
                )
                isNew = true
            }
            try Self.assignAttributes(photo, to: row)
            let item = try Self.attachItem(photo.itemID, to: row, in: context)
            if isNew {
                Self.assignToParentStore(
                    row,
                    parent: item,
                    container: container,
                    in: context
                )
            }
            try context.save()
        }
    }

    public func delete(id: ItemPhoto.ID) async throws {
        try await container.performBackgroundTaskWithDefaults { context in
            guard let row = try Self.fetchPhotoRow(id: id, in: context) else { return }
            context.delete(row)
            try context.save()
        }
    }

    private static func assignAttributes(_ photo: ItemPhoto, to row: NSManagedObject) throws {
        row.setValue(photo.id, forKey: "id")
        row.setValue(photo.imageData, forKey: "imageData")
        row.setValue(photo.thumbnailData, forKey: "thumbnailData")
        row.setValue(photo.caption, forKey: "caption")
        row.setValue(photo.sortOrder, forKey: "sortOrder")
        row.setValue(photo.createdAt, forKey: "createdAt")
    }

    @discardableResult
    private static func attachItem(
        _ itemID: Item.ID,
        to row: NSManagedObject,
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "ItemEntity")
        request.predicate = NSPredicate(format: "id == %@", itemID as CVarArg)
        request.fetchLimit = 1
        let item = try context.fetch(request).first
        row.setValue(item, forKey: "item")
        return item
    }

    /// Routes a new photo to the same store as its parent item —
    /// CloudKit rejects cross-store relationships at save time.
    private static func assignToParentStore(
        _ row: NSManagedObject,
        parent: NSManagedObject?,
        container: NSPersistentContainer,
        in context: NSManagedObjectContext
    ) {
        if let parentStore = parent?.objectID.persistentStore {
            context.assign(row, to: parentStore)
        } else if let privateStore = CoreDataStack.privateCloudKitStore(in: container) {
            context.assign(row, to: privateStore)
        }
    }

    private static func fetchPhotoRow(
        id: ItemPhoto.ID,
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "ItemPhotoEntity")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private static func makePhoto(from row: NSManagedObject) -> ItemPhoto {
        let itemID =
            (row.value(forKey: "item") as? NSManagedObject)?
            .value(forKey: "id") as? UUID ?? UUID()
        return ItemPhoto(
            id: row.value(forKey: "id") as? UUID ?? UUID(),
            itemID: itemID,
            imageData: row.value(forKey: "imageData") as? Data,
            thumbnailData: row.value(forKey: "thumbnailData") as? Data,
            caption: row.value(forKey: "caption") as? String,
            sortOrder: row.value(forKey: "sortOrder") as? Int16 ?? 0,
            createdAt: row.value(forKey: "createdAt") as? Date ?? Date()
        )
    }
}
