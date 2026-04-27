import SwiftUI
import UIKit

/// `UIViewControllerRepresentable` wrapping `UIImagePickerController`
/// with `.camera` as the source.
///
/// SwiftUI's `PhotosPicker` covers the photo-library path beautifully,
/// but it deliberately doesn't surface the camera — capturing live has
/// to go through `UIImagePickerController`, which is still UIKit. The
/// representable bridge stays narrow: present, take one photo (no
/// editing UI), hand the result back as `UIImage`, dismiss.
///
/// Camera availability gate lives at the call-site, not here. Calling
/// code should check `UIImagePickerController.isSourceTypeAvailable(.camera)`
/// — the iPad simulator and the iPhone-sim-on-Mac pairing both return
/// false, so the toolbar action that presents this sheet should hide
/// or disable in those environments to avoid a black-screen no-op.
struct PhotoCaptureSheet: UIViewControllerRepresentable {
    /// Called once on capture (fires *before* dismissal so the caller
    /// can persist before the sheet animates away). `nil` means the
    /// user cancelled out without taking a photo.
    let onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    final class Coordinator:
        NSObject,
        UIImagePickerControllerDelegate,
        UINavigationControllerDelegate
    {
        let onCapture: (UIImage?) -> Void

        init(onCapture: @escaping (UIImage?) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // `.originalImage` carries the rotated, color-corrected
            // capture. The picker has already applied EXIF orientation
            // by this point, so the downstream image pipeline doesn't
            // need to handle a rotation case from this surface (it
            // still does, since the library path doesn't make the same
            // guarantee).
            let image = info[.originalImage] as? UIImage
            onCapture(image)
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
            picker.dismiss(animated: true)
        }
    }
}
