import Photos
import SwiftUI

/// A plain grid over a computed run of photos — the photos around one place,
/// the photos of one trip, the photos in one memory.
///
/// Browsing only: tap opens the viewer, long press opens the tile menu. The
/// multi-select chrome is deliberately absent, because these lists are derived
/// and a selection made here would have no obvious home; a user who wants to
/// act on many photos has Library, Album Detail and Smart Album Detail.
struct PhotoListScreen: View {
    let title: String
    var subtitle: String?
    let assetIds: [String]

    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @AppStorage(SettingsKeys.gridColumns) private var storedColumns = 3

    @State private var model: PhotoListModel?
    @State private var viewerTarget: PhotoViewerTarget?
    @State private var videoStudioPresentation: VideoStudioPresentation?

    var body: some View {
        Group {
            if let model, !model.items.isEmpty {
                grid(model)
            } else if model?.isLoading == true || model == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let model, !model.items.isEmpty {
                    Button {
                        makeVideo(model)
                    } label: {
                        Image(systemName: "film")
                    }
                    .tint(.primary)
                    .accessibilityLabel("Make a video from these photos")
                }
            }
            if let subtitle {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(title).font(.headline)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task {
            if model == nil {
                model = PhotoListModel(assetIds: assetIds, dependencies: dependencies)
            }
            model?.load()
        }
        .fullScreenCover(item: $viewerTarget) { target in
            if let model {
                PhotoDetailScreen(
                    model: model,
                    currentIndex: model.index(of: target.id) ?? target.startIndex
                )
            }
        }
        .fullScreenCover(item: $videoStudioPresentation) { presentation in
            VideoStudioScreen(
                assets: presentation.assets,
                mode: presentation.mode,
                onSaved: { _ in }
            )
        }
    }

    /// Opens this list in Video Studio, in the order it is shown.
    ///
    /// A memory or a trip is already a chosen, ordered run of photos, which is
    /// the hard part of making a video out of them. The studio's own timeline
    /// is where the rest of the decisions belong, so this hands the photos over
    /// rather than building a film nobody asked for.
    ///
    /// Capped: a studio project carries every clip in memory, and a memory of
    /// four hundred photos would be a timeline nobody can work with.
    private func makeVideo(_ model: PhotoListModel) {
        let ids = model.items.prefix(Self.videoClipLimit).map(\.assetId)
        let assets = PhotoLibraryService.fetchAssets(ids: ids)
        guard !assets.isEmpty else { return }
        videoStudioPresentation = VideoStudioPresentation(assets: assets, mode: .multiClip)
    }

    /// Roughly two minutes at the studio's default photo duration.
    private static let videoClipLimit = 60

    private func grid(_ model: PhotoListModel) -> some View {
        PhotoGridCollectionView(
            photos: model.items,
            assetProvider: { _, item in model.assetsById[item.assetId] },
            sectionMode: .dates,
            anchorsBottom: false,
            contentVersion: model.contentGeneration,
            contentRefreshVersion: model.contentGeneration,
            jumpToNewestToken: 0,
            columnCount: Binding(
                get: { GridDensity.clamped(storedColumns) },
                set: { storedColumns = $0 }
            ),
            isSelecting: false,
            selectedIds: [],
            bottomInset: 0,
            photoLibrary: photoLibrary,
            onTap: { flatIndex, item in
                viewerTarget = PhotoViewerTarget(id: item.assetId, startIndex: flatIndex)
            },
            onLongPress: { _ in },
            onSwipeEvent: { _ in },
            onNearEnd: {},
            onUserScroll: {},
            removal: model.lastRemoval,
            contextMenuProvider: { item in tileMenu(model, assetId: item.assetId).makeMenu() }
        )
        .ignoresSafeArea(edges: .bottom)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("These photos are no longer in your library.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tileMenu(_ model: PhotoListModel, assetId: String) -> PhotoTileContextMenu {
        let actions = dependencies.assetActions
        return PhotoTileContextMenu(
            assetId: assetId,
            isVideo: model.assetsById[assetId]?.mediaType == .video,
            actions: actions,
            onShare: { actions.share(ids: [assetId]) },
            onAddToAlbum: { actions.presentAddToAlbum(ids: [assetId]) },
            onDuplicate: { actions.duplicate(ids: [assetId]) },
            onDelete: {
                Task { try? await model.deleteAssets(ids: [assetId]) }
            }
        )
    }
}
