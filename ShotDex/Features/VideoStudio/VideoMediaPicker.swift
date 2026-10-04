import Photos
import PhotosUI
import SwiftUI

/// One media item picked to start a project or add a clip: the library
/// identifier plus the clip kind the model needs to build a `VideoClip`.
struct VideoMediaPick: Identifiable, Equatable, Sendable {
    let assetID: String
    let kind: VideoClipKind
    /// A video's length as the library knows it, before its media loads.
    var duration: Double?
    var id: String { assetID }
}

/// Picks the photos and/or videos a new video or collage starts from
/// (Creations). Inside Video Studio, adding, replacing and choosing a
/// background go through the Media panel instead. `PHPickerViewController` with
/// `photoLibrary: .shared()` so each result carries an `assetIdentifier` — the
/// same identity the rest of the studio keys on.
struct VideoMediaPicker: UIViewControllerRepresentable {
    /// 0 = unlimited (a new video); the collage's slot count for a new collage.
    var selectionLimit = 0
    /// What may be picked. Photos and videos by default; the collage side of
    /// Creations narrows it to images. Kept as one picker rather than a
    /// second wrapper around `PHPickerViewController` — the identity
    /// handling (`assetIdentifier` from a `.shared()` library) is the part
    /// that is easy to get wrong, and it should exist once.
    var filter: PHPickerFilter = .any(of: [.images, .videos])
    let onPick: ([VideoMediaPick]) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, dismiss: { dismiss() })
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = selectionLimit
        configuration.filter = filter
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: ([VideoMediaPick]) -> Void
        let dismiss: () -> Void

        init(onPick: @escaping ([VideoMediaPick]) -> Void, dismiss: @escaping () -> Void) {
            self.onPick = onPick
            self.dismiss = dismiss
        }

        func picker(
            _ picker: PHPickerViewController,
            didFinishPicking results: [PHPickerResult]
        ) {
            let identifiers = results.compactMap(\.assetIdentifier)
            let picks: [VideoMediaPick] = identifiers.compactMap { id in
                guard let asset = PHAsset.fetchAssets(
                    withLocalIdentifiers: [id], options: nil
                ).firstObject else { return nil }
                return VideoMediaPick(
                    assetID: id,
                    kind: asset.mediaType == .video ? .video : .photo
                )
            }
            onPick(picks)
            dismiss()
        }
    }
}
