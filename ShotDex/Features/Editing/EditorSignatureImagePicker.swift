import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Picks the image for a signature layer out of the photo library.
///
/// `PHPickerViewController` rather than a grid built on the app's own
/// `LibraryQueries`: it is a few lines instead of a screen, and it reads the library
/// out of process, so choosing a logo needs no authorization of its own.
///
/// The transparency is the whole point of a signature, so the PNG data is asked for
/// by type and only re-encoded when the asset is not already a PNG. A
/// `PHImageManager` target-size request would hand back a flattened bitmap and turn
/// a logo into a white box.
struct EditorSignatureImagePicker: UIViewControllerRepresentable {
    let onPick: (Data, String?) -> Void
    let onFailure: () -> Void
    /// Fired on the main thread the instant a photo is chosen, before the picker is
    /// even dismissed. Decoding and re-encoding a full-resolution image to PNG takes
    /// a beat, so the editor puts up a spinner from here rather than appearing to
    /// freeze after the sheet closes.
    var onBegin: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onBegin: onBegin,
            onPick: onPick,
            onFailure: onFailure,
            dismiss: { dismiss() }
        )
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        // `.current` rather than `.compatible`: compatible transcodes to JPEG,
        // which throws the alpha channel away.
        configuration.preferredAssetRepresentationMode = .current
        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onBegin: () -> Void
        private let onPick: (Data, String?) -> Void
        private let onFailure: () -> Void
        private let dismiss: () -> Void

        init(
            onBegin: @escaping () -> Void,
            onPick: @escaping (Data, String?) -> Void,
            onFailure: @escaping () -> Void,
            dismiss: @escaping () -> Void
        ) {
            self.onBegin = onBegin
            self.onPick = onPick
            self.onFailure = onFailure
            self.dismiss = dismiss
        }

        func picker(
            _ picker: PHPickerViewController,
            didFinishPicking results: [PHPickerResult]
        ) {
            guard let result = results.first else {
                dismiss()
                return
            }
            // Tell the editor to show its spinner, then close the sheet at once so
            // the wait plays out over the photo rather than on a stalled picker.
            onBegin()
            dismiss()
            let assetIdentifier = result.assetIdentifier
            let provider = result.itemProvider
            let pngType = UTType.png.identifier

            if provider.hasItemConformingToTypeIdentifier(pngType) {
                provider.loadDataRepresentation(forTypeIdentifier: pngType) { data, _ in
                    self.finish(data: data, assetIdentifier: assetIdentifier, isPNG: true)
                }
                return
            }
            provider.loadDataRepresentation(
                forTypeIdentifier: UTType.image.identifier
            ) { data, _ in
                self.finish(data: data, assetIdentifier: assetIdentifier, isPNG: false)
            }
        }

        private func finish(data: Data?, assetIdentifier: String?, isPNG: Bool) {
            let png = data.flatMap { isPNG ? $0 : OverlayImageStore.pngData(from: $0) }
            Task { @MainActor in
                if let png {
                    self.onPick(png, assetIdentifier)
                } else {
                    self.onFailure()
                }
            }
        }
    }
}
