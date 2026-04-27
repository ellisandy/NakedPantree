import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Default max long-edge for the full-resolution `imageData` we persist
/// per `ARCHITECTURE.md` §9 / Phase 5 scope. Larger source photos are
/// downscaled before write; smaller ones pass through untouched.
let defaultPhotoMaxLongEdge: Int = 2048

/// Default max long-edge for the inline `thumbnailData` blob shown in
/// list rows and grids. ~256 px keeps the encoded JPEG comfortably under
/// the ~64 KB inline-storage target while still looking sharp on a
/// retina display.
let defaultThumbnailMaxLongEdge: Int = 256

/// Resize-and-encode source image data to a JPEG no larger than
/// `maxLongEdge` on its longest side.
///
/// Uses `ImageIO`'s thumbnail API rather than `UIGraphicsImageRenderer`
/// for two reasons: it streams the source instead of decoding the full
/// image into memory first (a 12-megapixel HEIC from a recent iPhone
/// is ~30MB decoded, ~3MB encoded), and `kCGImageSourceCreateThumbnailWithTransform`
/// applies the EXIF-orientation rotation in one shot — naive
/// `UIImage(data:)` → resize loses the orientation, producing
/// sideways-rotated photos for portrait-shot iPhone images.
///
/// Always returns a JPEG (`UTType.jpeg`) regardless of the input
/// container. Output portability beats source-format fidelity for
/// pantry photos. Returns `nil` if the input isn't a parseable image.
///
/// Pure function so tests can pin synthetic input and verify exact
/// output dimensions without a UI surface.
func resizedPhotoData(
    from data: Data,
    maxLongEdge: Int = defaultPhotoMaxLongEdge,
    compressionQuality: Double = 0.85
) -> Data? {
    encodeJPEG(
        from: data,
        maxLongEdge: maxLongEdge,
        compressionQuality: compressionQuality
    )
}

/// Generate the inline thumbnail JPEG sized for list-row and grid
/// display. Lower compression quality than the full-size resize since
/// the thumbnail is small enough that JPEG artifacts disappear into
/// the rendering scale.
///
/// Same `ImageIO` thumbnail-with-transform path as `resizedPhotoData`
/// — see that function's doc-comment for the EXIF / streaming
/// rationale.
func thumbnailPhotoData(
    from data: Data,
    maxLongEdge: Int = defaultThumbnailMaxLongEdge,
    compressionQuality: Double = 0.7
) -> Data? {
    encodeJPEG(
        from: data,
        maxLongEdge: maxLongEdge,
        compressionQuality: compressionQuality
    )
}

private func encodeJPEG(
    from data: Data,
    maxLongEdge: Int,
    compressionQuality: Double
) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
        return nil
    }
    let thumbnailOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: maxLongEdge,
    ]
    guard
        let scaled = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        )
    else {
        return nil
    }
    let output = NSMutableData()
    guard
        let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        )
    else {
        return nil
    }
    let writeOptions: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: compressionQuality
    ]
    CGImageDestinationAddImage(destination, scaled, writeOptions as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return output as Data
}
