import SwiftUI
import UIKit

/// Live in-app camera capture for job photos — wraps `UIImagePickerController`
/// rather than a custom `AVFoundation` session, since a single still photo is
/// all this needs. Produces the same `(Data, String)` shape
/// `PhotosImportButton.onPick` already does, so callers (see
/// `JobDetailView.importAndAttachFromPhotos`) don't need to know whether the
/// photo came from the library or the camera.
struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (Data, String) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (Data, String) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (Data, String) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard
                let image = info[.originalImage] as? UIImage,
                let data = image.jpegData(compressionQuality: 0.85)
            else {
                onCancel()
                return
            }
            let stamp = Int(Date().timeIntervalSince1970)
            let name = "Photo-\(stamp)-\(UUID().uuidString.prefix(6)).jpg"
            onCapture(data, name)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
