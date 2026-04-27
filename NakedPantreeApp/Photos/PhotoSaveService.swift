import Foundation
import NakedPantreeDomain
import UIKit

/// Outcome of a photo-save attempt. Surfaced to the UI layer so the
/// view can decide between an inline error banner, a silent retry, or
/// a pass-through.
enum PhotoSaveError: Error {
    /// Source bytes couldn't be parsed as an image — corrupted file,
    /// unsupported container, or zero bytes from a cancelled load.
    case invalidImageData
}

/// Encodes a source image into the persisted JPEG pair (`imageData`
/// + `thumbnailData`) and writes a new `ItemPhoto` row through the
/// repository.
///
/// Pulled out of the view layer so the resize → encode → persist
/// chain has a single seam tests can pin. The function takes the
/// repository as a parameter rather than reading the environment so
/// it stays a pure async function — no `@MainActor`, no SwiftUI
/// dependency leaking into the photos module.
///
/// `nextSortOrder` is the caller's responsibility. The natural value
/// is the current `photos(for:)` count cast to `Int16` — appends to
/// the end of the strip. Reorder UI in 5.3 will rewrite the column
/// in bulk; that's not this function's concern.
func savePhotoFromData(
    _ source: Data,
    itemID: Item.ID,
    nextSortOrder: Int16,
    repository: ItemPhotoRepository
) async throws -> ItemPhoto {
    guard
        let imageData = resizedPhotoData(from: source),
        let thumbnailData = thumbnailPhotoData(from: source)
    else {
        throw PhotoSaveError.invalidImageData
    }
    let photo = ItemPhoto(
        itemID: itemID,
        imageData: imageData,
        thumbnailData: thumbnailData,
        sortOrder: nextSortOrder
    )
    try await repository.create(photo)
    return photo
}

/// Camera-path entry. `UIImagePickerController` returns `UIImage`,
/// not the original asset bytes — there's no way to get raw HEIC out
/// of the camera capture surface. We re-encode to JPEG (quality 0.95
/// — barely lossy, the resize pipeline does the heavy lifting from
/// there) so the rest of the chain operates on the same `Data` shape
/// the library path produces.
///
/// Throws `PhotoSaveError.invalidImageData` if the `UIImage` has no
/// backing `cgImage` (rare — typically only happens with images
/// constructed from `CIImage` without rasterization).
func savePhotoFromUIImage(
    _ image: UIImage,
    itemID: Item.ID,
    nextSortOrder: Int16,
    repository: ItemPhotoRepository
) async throws -> ItemPhoto {
    guard let jpeg = image.jpegData(compressionQuality: 0.95) else {
        throw PhotoSaveError.invalidImageData
    }
    return try await savePhotoFromData(
        jpeg,
        itemID: itemID,
        nextSortOrder: nextSortOrder,
        repository: repository
    )
}
