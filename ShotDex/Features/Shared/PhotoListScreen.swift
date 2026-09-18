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
    }

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
