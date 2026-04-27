import CoreGraphics
import Foundation
import ImageIO
import NakedPantreeDomain
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import NakedPantree

private func makeTestJPEG(width: Int, height: Int) throws -> Data {
    let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let bitmapInfo = CGImageAlphaInfo.noneSkipFirst.rawValue
    let context = try #require(
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )
    )
    context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let cgImage = try #require(context.makeImage())
    let output = NSMutableData()
    let destination = try #require(
        CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        )
    )
    CGImageDestinationAddImage(destination, cgImage, nil)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
}

@Suite("Photo save service")
struct PhotoSaveServiceTests {
    @Test("Persists both imageData and thumbnailData from a Data source")
    func persistsBothBlobs() async throws {
        let repo = InMemoryItemPhotoRepository()
        let item = Item(locationID: UUID(), name: "Cheese")
        let source = try makeTestJPEG(width: 4000, height: 3000)

        let saved = try await savePhotoFromData(
            source,
            itemID: item.id,
            nextSortOrder: 0,
            repository: repo
        )

        #expect(saved.itemID == item.id)
        #expect(saved.imageData != nil)
        #expect(saved.thumbnailData != nil)
        // The thumbnail must be smaller than the persisted full
        // resize — confirms the resize and thumbnail paths produced
        // distinct outputs rather than the same blob twice.
        #expect((saved.thumbnailData?.count ?? 0) < (saved.imageData?.count ?? 0))

        let persisted = try await repo.photos(for: item.id)
        #expect(persisted.count == 1)
        #expect(persisted.first?.id == saved.id)
    }

    @Test("Honors caller-supplied sortOrder")
    func sortOrderRoundTrips() async throws {
        let repo = InMemoryItemPhotoRepository()
        let itemID = UUID()
        let source = try makeTestJPEG(width: 800, height: 600)

        let first = try await savePhotoFromData(
            source, itemID: itemID, nextSortOrder: 0, repository: repo
        )
        let second = try await savePhotoFromData(
            source, itemID: itemID, nextSortOrder: 1, repository: repo
        )

        #expect(first.sortOrder == 0)
        #expect(second.sortOrder == 1)

        let persisted = try await repo.photos(for: itemID)
        #expect(persisted.map(\.sortOrder) == [0, 1])
    }

    @Test("Garbage source data throws invalidImageData")
    func garbageDataThrows() async {
        let repo = InMemoryItemPhotoRepository()
        let garbage = Data("not an image".utf8)

        await #expect(throws: PhotoSaveError.invalidImageData) {
            _ = try await savePhotoFromData(
                garbage,
                itemID: UUID(),
                nextSortOrder: 0,
                repository: repo
            )
        }
    }

    @Test("UIImage entry point routes through the data path")
    func uiImageEntryPointRoutesThroughDataPath() async throws {
        let repo = InMemoryItemPhotoRepository()
        let source = try makeTestJPEG(width: 1200, height: 900)
        let image = try #require(UIImage(data: source))

        let saved = try await savePhotoFromUIImage(
            image,
            itemID: UUID(),
            nextSortOrder: 0,
            repository: repo
        )

        #expect(saved.imageData != nil)
        #expect(saved.thumbnailData != nil)
    }
}

@Suite("Photo promote service")
struct PhotoPromoteServiceTests {
    private static func makePhoto(
        sortOrder: Int16,
        itemID: UUID = UUID()
    ) -> ItemPhoto {
        ItemPhoto(itemID: itemID, sortOrder: sortOrder)
    }

    @Test("Promoting a non-primary photo writes sortOrder = currentMin - 1")
    func promotesToOneBelowCurrentMin() async throws {
        let itemID = UUID()
        let primary = Self.makePhoto(sortOrder: 0, itemID: itemID)
        let middle = Self.makePhoto(sortOrder: 1, itemID: itemID)
        let last = Self.makePhoto(sortOrder: 2, itemID: itemID)
        let repo = InMemoryItemPhotoRepository()
        for photo in [primary, middle, last] {
            try await repo.create(photo)
        }

        let promoted = try await makePhotoPrimary(
            middle,
            among: [primary, middle, last],
            repository: repo
        )

        #expect(promoted.sortOrder == -1)
        // Repository now sorts ascending, so the promoted photo is
        // first — the user-visible "primary" slot.
        let persisted = try await repo.photos(for: itemID)
        #expect(persisted.first?.id == middle.id)
    }

    @Test("Empty photo list still produces a valid promote (currentMin defaults to 0)")
    func emptyListPromotesToMinusOne() async throws {
        let itemID = UUID()
        let solo = Self.makePhoto(sortOrder: 5, itemID: itemID)
        let repo = InMemoryItemPhotoRepository()
        try await repo.create(solo)

        // The "among" array doesn't include the photo being promoted —
        // models the corner where the strip's photos array is empty.
        let promoted = try await makePhotoPrimary(
            solo,
            among: [],
            repository: repo
        )

        #expect(promoted.sortOrder == -1)
    }

    @Test("Negative current min still gets one below")
    func negativeMinKeepsShifting() async throws {
        // After a promote, the new min sortOrder is negative. A
        // subsequent promote of a different photo must keep going
        // negative (currentMin - 1), not collapse to 0.
        let itemID = UUID()
        let alreadyPromoted = Self.makePhoto(sortOrder: -1, itemID: itemID)
        let original = Self.makePhoto(sortOrder: 0, itemID: itemID)
        let repo = InMemoryItemPhotoRepository()
        try await repo.create(alreadyPromoted)
        try await repo.create(original)

        let promoted = try await makePhotoPrimary(
            original,
            among: [alreadyPromoted, original],
            repository: repo
        )

        #expect(promoted.sortOrder == -2)
        let persisted = try await repo.photos(for: itemID)
        #expect(persisted.first?.id == original.id)
    }
}
