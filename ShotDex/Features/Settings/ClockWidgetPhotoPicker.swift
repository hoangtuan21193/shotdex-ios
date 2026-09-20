import PhotosUI
import SwiftUI

/// Picks the single photo behind the Clock widget.
///
/// `PHPickerViewController`, like the editor's signature picker: it reads the
/// library out of process, so choosing a picture needs no authorization of its
/// own, and all that is wanted here is the asset's identifier — the picture
/// itself is rendered later by `ClockWidgetSnapshotWriter`.
struct ClockWidgetPhotoPicker: UIViewControllerRepresentable {
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, dismiss: { dismiss() })
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPick: (String) -> Void
        private let dismiss: () -> Void

        init(onPick: @escaping (String) -> Void, dismiss: @escaping () -> Void) {
            self.onPick = onPick
            self.dismiss = dismiss
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            defer { dismiss() }
            // Without an identifier there is nothing to render later: the
            // picker hands back an item provider for a photo the app has no
            // other handle on.
            guard let assetIdentifier = results.first?.assetIdentifier else { return }
            onPick(assetIdentifier)
        }
    }
}

/// Picks the album the Clock widget rotates through.
///
/// The app's own album list rather than a system picker: PhotosUI has no album
/// picker, and `AlbumsModel` already knows every album with a cover and a
/// count.
struct ClockWidgetAlbumPicker: View {
    let onPick: (_ collectionId: String, _ title: String) -> Void

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @State private var model = AlbumsModel()

    var body: some View {
        List {
            if model.userAlbums.isEmpty, model.smartAlbums.isEmpty {
                ContentUnavailableView(
                    "No Albums",
                    systemImage: "rectangle.stack",
                    description: Text("Albums you make in Photos or in ShotDex show up here.")
                )
            }
            section("My Albums", albums: model.userAlbums)
            section("Suggested", albums: model.smartAlbums)
            section("Media Types", albums: model.mediaTypeAlbums)
            section("Shared", albums: model.sharedAlbums)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Choose Album")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .task {
            model.dependencies = dependencies
            model.load()
        }
    }

    @ViewBuilder
    private func section(_ title: String, albums: [AlbumItem]) -> some View {
        if !albums.isEmpty {
            Section(title) {
                ForEach(albums) { album in
                    Button {
                        guard let collection = album.assetCollection else { return }
                        onPick(collection.localIdentifier, album.title)
                        dismiss()
                    } label: {
                        LabeledContent(album.title, value: album.count.formatted())
                            .monospacedDigit()
                    }
                    // All Photos is a fetch, not a collection, so there is no
                    // identifier to store for it.
                    .disabled(album.assetCollection == nil)
                }
            }
        }
    }
}
