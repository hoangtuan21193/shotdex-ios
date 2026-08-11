import Photos
import PhotosUI
import SwiftUI

/// One media item picked to add or replace a clip: the library identifier plus
/// the clip kind the model needs to build a `VideoClip`.
struct VideoMediaPick: Identifiable, Equatable, Sendable {
    let assetID: String
    let kind: VideoClipKind
    var id: String { assetID }
}

/// Picks photos and/or videos out of the library to append to the Video track
/// or replace the selected clip. `PHPickerViewController` with
/// `photoLibrary: .shared()` so each result carries an `assetIdentifier` — the
/// same identity the rest of the studio keys on.
struct VideoMediaPicker: UIViewControllerRepresentable {
    /// 0 = unlimited (Add media); 1 = single (Replace).
    var selectionLimit = 0
    let onPick: ([VideoMediaPick]) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, dismiss: { dismiss() })
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = selectionLimit
        configuration.filter = .any(of: [.images, .videos])
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
