import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import NakedPantree

/// Synthesizes a JPEG-encoded `Data` blob of the given pixel dimensions.
/// Hermetic — no file fixtures, no network. The pixel content is solid
/// gray so JPEG compression is highly predictable.
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

/// Reads back the pixel dimensions of an encoded image blob.
private func pixelDimensions(of data: Data) throws -> (width: Int, height: Int) {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let properties = try #require(
        CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    )
    let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
    let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)
    return (width, height)
}

@Suite("Photo resize pipeline")
struct ResizedPhotoDataTests {
    @Test("Square 4096px source resizes to 2048 long edge")
    func squareSourceCappedAtMaxLongEdge() throws {
        let source = try makeTestJPEG(width: 4096, height: 4096)
        let resized = try #require(resizedPhotoData(from: source))
        let dimensions = try pixelDimensions(of: resized)
        #expect(dimensions.width == 2048)
        #expect(dimensions.height == 2048)
    }

    @Test("Landscape 4000x3000 source preserves aspect ratio")
    func landscapeAspectRatioPreserved() throws {
        let source = try makeTestJPEG(width: 4000, height: 3000)
        let resized = try #require(resizedPhotoData(from: source))
        let dimensions = try pixelDimensions(of: resized)
        // 4000 / 2048 = ~1.95; 3000 / 1.95 = ~1536.
        #expect(dimensions.width == 2048)
        #expect(dimensions.height == 1536)
    }

    @Test("Portrait 3000x4000 source caps the longest edge, not width")
    func portraitCapsLongestEdge() throws {
        let source = try makeTestJPEG(width: 3000, height: 4000)
        let resized = try #require(resizedPhotoData(from: source))
        let dimensions = try pixelDimensions(of: resized)
        #expect(dimensions.height == 2048)
        #expect(dimensions.width == 1536)
    }

    @Test("Already-small source passes through at original dimensions")
    func alreadySmallSourcePassesThrough() throws {
        // A 1024x768 source is below the 2048 cap. ImageIO's thumbnail
        // API clamps at source size when the requested edge exceeds it,
        // so the output dimensions should match the input exactly. Any
        // mismatch (upscale, or a quiet off-by-one downscale) is a
        // regression we want to catch.
        let source = try makeTestJPEG(width: 1024, height: 768)
        let resized = try #require(resizedPhotoData(from: source))
        let dimensions = try pixelDimensions(of: resized)
        #expect(dimensions.width == 1024)
        #expect(dimensions.height == 768)
    }

    @Test("Non-image input returns nil")
    func garbageInputReturnsNil() {
        let garbage = Data("not an image".utf8)
        #expect(resizedPhotoData(from: garbage) == nil)
    }

    @Test("Custom maxLongEdge overrides default")
    func customMaxLongEdgeOverridesDefault() throws {
        let source = try makeTestJPEG(width: 4000, height: 3000)
        let resized = try #require(resizedPhotoData(from: source, maxLongEdge: 1000))
        let dimensions = try pixelDimensions(of: resized)
        #expect(dimensions.width == 1000)
        #expect(dimensions.height == 750)
    }
}

@Suite("Thumbnail pipeline")
struct ThumbnailPhotoDataTests {
    @Test("Caps long edge at the thumbnail default")
    func capsAtThumbnailDefault() throws {
        let source = try makeTestJPEG(width: 4000, height: 3000)
        let thumbnail = try #require(thumbnailPhotoData(from: source))
        let dimensions = try pixelDimensions(of: thumbnail)
        #expect(dimensions.width == 256)
        #expect(dimensions.height == 192)
    }

    @Test("Thumbnail bytes are smaller than full-size resize")
    func thumbnailIsSmallerThanResize() throws {
        // The dimension cap (above) is the precise invariant. This
        // size check is the cheap downstream signal: if the dimension
        // cap regressed silently and emitted a full-resolution
        // thumbnail, this assertion would catch it as a side effect.
        // The exact ~64KB inline budget is content-dependent and gets
        // verified on real photos in the Phase 5.4 two-device runbook.
        let source = try makeTestJPEG(width: 4000, height: 3000)
        let resized = try #require(resizedPhotoData(from: source))
        let thumbnail = try #require(thumbnailPhotoData(from: source))
        #expect(thumbnail.count < resized.count)
    }

    @Test("Non-image input returns nil")
    func garbageInputReturnsNil() {
        let garbage = Data("nope".utf8)
        #expect(thumbnailPhotoData(from: garbage) == nil)
    }
}
