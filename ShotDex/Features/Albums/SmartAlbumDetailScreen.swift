import Photos
import SwiftUI

/// Grid of the photos matching a smart album's saved criteria, with the
/// conditions shown as read-only tokens at the top. Structurally a sibling of
/// `AlbumDetailScreen` (same viewer / multi-select / compare / delete), but
/// driven by a `SmartAlbumDetailModel` (criteria query) instead of a
/// PhotoKit collection.
struct SmartAlbumDetailScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(AppNavigation.self) private var navigation

    let album: SmartAlbum

    @State private var model: SmartAlbumDetailModel?
    @State private var viewerTarget: PhotoViewerTarget?

    @State private var isSelecting = false
    @State private var selectedIds: [String] = []
    @State private var isComparePresented = false
    @State private var compressionPresentation: CompressionPresentation?
    @State private var swipeBaseline: [String] = []
    @State private var isDeleting = false
    @State private var isPreparingShare = false
    @State private var deleteErrorMessage: String?

    @AppStorage(SettingsKeys.gridColumns) private var storedColumns = 3

    var body: some View {
        Group {
            if let model {
                photoGrid(model)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 80)
            }
        }
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onChange(of: isSelecting) { navigation.hidesTabBar = isSelecting }
        .onChange(of: selectionSnapshot) {
            navigation.selectionBar = isSelecting ? selectionBarModel() : nil
        }
        .onAppear {
            if isSelecting { navigation.selectionBar = selectionBarModel() }
        }
        .onDisappear {
            navigation.hidesTabBar = false
            if isSelecting { navigation.selectionBar = nil }
        }
        .safeAreaInset(edge: .top) {
            if !album.query.isEmpty {
                SmartAlbumConditionsBar(
                    query: album.query,
                    matchCount: model?.matchCount ?? 0
                )
            }
        }
        .task {
            if model == nil {
                let newModel = SmartAlbumDetailModel(album: album, dependencies: dependencies)
                await newModel.load()
                model = newModel
            }
        }
        .onChange(of: photoLibrary.assetChangeToken) {
            guard !isSelecting, let model else { return }
            Task {
                await model.load()
            }
        }
        .fullScreenCover(item: $viewerTarget) { target in
            if let model {
                PhotoDetailScreen(model: model, currentIndex: target.startIndex)
            }
        }
        .fullScreenCover(isPresented: $isComparePresented, onDismiss: stopSelecting) {
            if let model, let photos = comparePhotos(model) {
                CompareScreen(photos: photos)
            }
        }
        .fullScreenCover(item: $compressionPresentation) { presentation in
            CompressionScreen(
                assets: presentation.assets,
                sourceAlbum: presentation.sourceAlbum
            )
        }
        .alert(
            "Couldn't Delete Photos",
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .sensoryFeedback(.selection, trigger: selectedIds.count)
    }

    // MARK: Grid

    private func photoGrid(_ model: SmartAlbumDetailModel) -> some View {
        PhotoGridCollectionView(
            photos: model.items,
            assetProvider: { index, _ in model.asset(atFlatIndex: index) },
            sectionMode: .dates,
            anchorsBottom: false,
            contentVersion: model.contentGeneration,
            contentRefreshVersion: model.contentRefreshGeneration,
            jumpToNewestToken: 0,
            columnCount: Binding(
                get: { GridDensity.clamped(storedColumns) },
                set: { storedColumns = $0 }
            ),
            isSelecting: isSelecting,
            selectedIds: selectedIds,
            bottomInset: isSelecting ? navigation.selectionGridInset : bottomChromeInset,
            photoLibrary: photoLibrary,
            onTap: { _, item in
                if isSelecting {
                    toggleSelection(of: item.assetId)
                } else if let index = model.index(of: item.assetId) {
                    viewerTarget = PhotoViewerTarget(id: item.assetId, startIndex: index)
                }
            },
            onLongPress: { item in
                if !isSelecting {
                    isSelecting = true
                    toggleSelection(of: item.assetId)
                }
            },
            onSwipeEvent: handleSwipeEvent,
            onNearEnd: {},
            onUserScroll: {}
        )
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: Selection

    private func toggleSelection(of assetId: String) {
        if let existing = selectedIds.firstIndex(of: assetId) {
            selectedIds.remove(at: existing)
        } else {
            selectedIds.append(assetId)
        }
    }

    private func handleSwipeEvent(_ event: SwipeSelectEvent) {
        switch event {
        case .began:
            swipeBaseline = selectedIds
        case .changed(let rangeIds, let select):
            let updated: [String]
            if select {
                let existing = Set(swipeBaseline)
                updated = swipeBaseline + rangeIds.filter { !existing.contains($0) }
            } else {
                let range = Set(rangeIds)
                updated = swipeBaseline.filter { !range.contains($0) }
            }
            if updated != selectedIds { selectedIds = updated }
        case .ended:
            swipeBaseline = []
        }
    }

    private func presentCompression(_ model: SmartAlbumDetailModel) {
        let assets: [PHAsset] = selectedIds.compactMap { id -> PHAsset? in
            guard let asset = model.asset(for: id), asset.mediaType == .image else { return nil }
            return asset
        }
        guard !assets.isEmpty else { return }
        compressionPresentation = CompressionPresentation(
            assets: assets,
            sourceAlbum: nil
        )
    }

    private func stopSelecting() {
        isSelecting = false
        selectedIds = []
        swipeBaseline = []
    }

    /// Compare panes follow the pick order of the selection.
    private func comparePhotos(_ model: SmartAlbumDetailModel) -> [ComparePhoto]? {
        guard (2...CompareScreen.maxPhotoCount).contains(selectedIds.count) else { return nil }
        let photos = selectedIds.compactMap { id -> ComparePhoto? in
            guard let asset = model.asset(for: id) else { return nil }
            return ComparePhoto(metadata: model.metadata(for: id), asset: asset)
        }
        return photos.count >= 2 ? photos : nil
    }

    private func shareSelected(_ model: SmartAlbumDetailModel) {
        guard !selectedIds.isEmpty, !isPreparingShare else { return }
        let assets = selectedIds.compactMap { model.asset(for: $0) }
        isPreparingShare = true
        Task {
            let items = await PhotoShareSheet.gather(assets: assets)
            isPreparingShare = false
            PhotoShareSheet.present(items: items)
        }
    }

    private func deleteSelected(_ model: SmartAlbumDetailModel) {
        guard !selectedIds.isEmpty else { return }
        let ids = Set(selectedIds)
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await model.deleteAssets(ids: ids)
                withAnimation { stopSelecting() }
            } catch let error as PHPhotosError where error.code == .userCancelled {
                // User dismissed the system confirm — keep the selection.
            } catch {
                deleteErrorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Selection bar & toolbar

    private struct SelectionSnapshot: Equatable {
        var isSelecting: Bool
        var ids: [String]
        var isDeleting: Bool
    }
    private var selectionSnapshot: SelectionSnapshot {
        SelectionSnapshot(isSelecting: isSelecting, ids: selectedIds, isDeleting: isDeleting)
    }

    private func selectionBarModel() -> SelectionBarModel? {
        guard let model else { return nil }
        return SelectionBarModel(
            selectionCount: selectedIds.count,
            thumbnailIds: selectedIds,
            photoLibrary: photoLibrary,
            onCompare: { isComparePresented = true },
            onDelete: { deleteSelected(model) },
            onDeselect: { toggleSelection(of: $0) },
            isDeleting: isDeleting
        )
    }

    private var bottomChromeInset: CGFloat {
        if #available(iOS 26.0, *) { 8 } else { 100 }
    }

    @ViewBuilder
    private var shareToolbarButton: some View {
        Button {
            if let model { shareSelected(model) }
        } label: {
            if isPreparingShare {
                ProgressView()
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .disabled(selectedIds.isEmpty || isPreparingShare)
        .accessibilityLabel("Share")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if isSelecting {
                shareToolbarButton
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if let model, isSelecting {
                Menu {
                    Button {
                        presentCompression(model)
                    } label: {
                        Label(
                            "Resize & Compress",
                            systemImage: "arrow.down.right.and.arrow.up.left"
                        )
                    }
                    .disabled(
                        !selectedIds.contains {
                            model.asset(for: $0)?.mediaType == .image
                        }
                    )
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More selection actions")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if model?.items.isEmpty == false {
                Button {
                    if isSelecting {
                        stopSelecting()
                    } else {
                        isSelecting = true
                    }
                } label: {
                    Image(systemName: isSelecting ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .accessibilityLabel(isSelecting ? "Cancel selection" : "Select photos")
            }
        }
    }
}
