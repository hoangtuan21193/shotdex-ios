import PhotosUI
import SwiftUI

/// Picks the single photo behind a photo widget.
///
/// `PHPickerViewController`, like the editor's signature picker: it reads the
/// library out of process, so choosing a picture needs no authorization of its
/// own, and all that is wanted here is the asset's identifier — the picture
/// itself is rendered later by `PhotoWidgetSnapshotWriter`.
struct PhotoWidgetPhotoPicker: UIViewControllerRepresentable {
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

/// Picks the album a photo widget rotates through.
///
/// A grid of covers, not a list of names — the same tiles the Collections tab
/// uses (`AlbumCoverTile`), because this is the same question that screen
/// answers: which one is this. A name and a count beside it is the one thing
/// that does not help you recognise an album of your own photos.
struct PhotoWidgetAlbumPicker: View {
    let onPick: (_ collectionId: String, _ title: String) -> Void

    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var model = AlbumsModel()
    @State private var search = ""

    private var side: CGFloat {
        AlbumTileMetrics.side(isRegularWidth: horizontalSizeClass == .regular)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                if isEmpty {
                    ContentUnavailableView(
                        search.isEmpty ? "No Albums" : "No Matches",
                        systemImage: "rectangle.stack",
                        description: Text(
                            search.isEmpty
                                ? "Albums you make in Photos or in ShotDex show up here."
                                : "No album is called that."
                        )
                    )
                    .padding(.top, AppTheme.Spacing.xxl)
                }
                section("My Albums", albums: matching(model.userAlbums))
                section("Suggested", albums: matching(model.smartAlbums))
                section("Media Types", albums: matching(model.mediaTypeAlbums))
                section("Shared", albums: matching(model.sharedAlbums))
            }
            .padding(.vertical, AppTheme.Spacing.lg)
        }
        .searchable(text: $search, prompt: "Search Albums")
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

    private var isEmpty: Bool {
        [model.userAlbums, model.smartAlbums, model.mediaTypeAlbums, model.sharedAlbums]
            .allSatisfy { matching($0).isEmpty }
    }

    /// Accent-blind matching, the same rule the Home Screen's own album picker
    /// uses, so typing "da lat" finds "Đà Lạt" in both places.
    private func matching(_ albums: [AlbumItem]) -> [AlbumItem] {
        let query = WidgetAlbumCatalog.normalized(search)
        guard !query.isEmpty else { return albums }
        return albums.filter { WidgetAlbumCatalog.normalized($0.title).contains(query) }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, albums: [AlbumItem]) -> some View {
        if !albums.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text(title)
                    .font(.title3.bold())
                    .padding(.horizontal, AppTheme.Spacing.lg)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: side), spacing: AppTheme.Spacing.sm)],
                    spacing: AppTheme.Spacing.sm
                ) {
                    ForEach(albums) { album in
                        Button {
                            guard let collection = album.assetCollection else { return }
                            onPick(collection.localIdentifier, album.title)
                            dismiss()
                        } label: {
                            PhotoWidgetAlbumTile(album: album)
                        }
                        .buttonStyle(.plain)
                        // All Photos is a fetch rather than a collection, so
                        // there is no identifier to store for it.
                        .disabled(album.assetCollection == nil)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
            }
        }
    }
}

/// One album in that grid: its cover, its name over the bottom of it.
private struct PhotoWidgetAlbumTile: View {
    let album: AlbumItem

    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var cover: UIImage?
    @State private var needsScrim = false

    private var side: CGFloat {
        AlbumTileMetrics.side(isRegularWidth: horizontalSizeClass == .regular)
    }

    var body: some View {
        AlbumCoverTile(
            title: album.title,
            accessibilityLabel: String(
                localized: "\(album.title), \(album.count) photos",
                comment: "VoiceOver label for an album tile in the widget's album picker"
            ),
            needsScrim: needsScrim
        ) {
            AlbumCoverWell(image: cover, systemImage: album.symbolName ?? "photo.on.rectangle")
        }
        .onAppear(perform: loadCover)
    }

    private func loadCover() {
        guard cover == nil, let asset = album.coverAsset else { return }
        let pixels = side * ActiveDisplay.scale
        _ = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: pixels, height: pixels),
            allowNetwork: false
        ) { image in
            guard let image else { return }
            cover = image
            // Measured rather than assumed, like the Collections tab: a scrim
            // on an already-dark cover only dirties it.
            needsScrim = CoverTitleScrim.isNeeded(for: image)
        }
    }
}
