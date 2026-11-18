import SwiftUI
import UIKit

/// 相机 / 相册选择器。用 UIImagePickerController 桥接，返回选中的 UIImage。
/// 模拟器没有摄像头，相机按钮会自动禁用，避免运行时崩溃。
struct CameraImagePicker: UIViewControllerRepresentable {
    enum Source {
        case camera
        case photoLibrary
    }

    let source: Source
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        switch source {
        case .camera:
            picker.sourceType = .camera
        case .photoLibrary:
            picker.sourceType = .photoLibrary
        }
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage) { dismiss() }
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        let onFinish: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onFinish: @escaping () -> Void) {
            self.onImage = onImage
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.editedImage] as? UIImage
                ?? info[.originalImage] as? UIImage
            if let image {
                onImage(image)
            }
            onFinish()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish()
        }
    }
}
