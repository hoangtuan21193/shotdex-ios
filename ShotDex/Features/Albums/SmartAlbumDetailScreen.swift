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
    @State private var collagePresentation: CollagePresentation?
    @State private var videoStudioPresentation: VideoStudioPresentation?
    @State private var addToCollectionPresentation: AddToCollectionPresentation?
    @State private var swipeBaseline: [String] = []
    @State private var isDeleting = false
    @State private var isPreparingShare = false
    @State private var isDuplicating = false
    @State private var deleteErrorMessage: String?
    /// Errors from the ⋯ actions (Export EXIF, Duplicate).
    @State private var actionErrorMessage: String?

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
        .toolbar(isSelecting ? .hidden : .automatic, for: .navigationBar, .tabBar)
        .disablesBackSwipe(isSelecting)
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
        .fullScreenCover(item: $compressionPresentation, onDismiss: stopSelecting) { presentation in
            CompressionScreen(
                assets: presentation.assets,
                sourceAlbum: presentation.sourceAlbum
            )
        }
        .fullScreenCover(item: $collagePresentation) { presentation in
            CollageScreen(assets: presentation.assets)
        }
        .fullScreenCover(item: $videoStudioPresentation) { presentation in
            VideoStudioScreen(
                assets: presentation.assets,
                mode: presentation.mode,
                onSaved: { _ in }
            )
        }
        .sheet(item: $addToCollectionPresentation) { presentation in
            AddToCollectionSheet(
                assets: presentation.assets,
                photoLibrary: photoLibrary,
                onAdded: { withAnimation { stopSelecting() } }
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
        .alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { actionErrorMessage != nil },
                set: { if !$0 { actionErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "")
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

    /// Selected *image* asset ids in pick order (videos dropped) for Collage.
    private func selectedImageIDs(_ model: SmartAlbumDetailModel) -> [String] {
        selectedIds.filter { model.asset(for: $0)?.mediaType == .image }
    }

    private func presentCollage(_ model: SmartAlbumDetailModel) {
        let assets = selectedImageIDs(model).compactMap { model.asset(for: $0) }
        guard CollageTemplateCatalog.supportedCounts.contains(assets.count) else { return }
        collagePresentation = CollagePresentation(assets: assets)
    }

    private func presentVideoStudio(_ model: SmartAlbumDetailModel) {
        let assets = selectedIds.compactMap { model.asset(for: $0) }
        guard !assets.isEmpty else { return }
        videoStudioPresentation = VideoStudioPresentation(assets: assets, mode: .multiClip)
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
        var isPreparingShare: Bool
    }
    private var selectionSnapshot: SelectionSnapshot {
        SelectionSnapshot(
            isSelecting: isSelecting,
            ids: selectedIds,
            isDeleting: isDeleting,
            isPreparingShare: isPreparingShare
        )
    }

    /// The model the root tab view's floating `SelectionOverlay` renders: the full
    /// action set plus the selection thumbnail tray.
    private func selectionBarModel() -> SelectionBarModel? {
        guard let model else { return nil }
        return SelectionBarModel(
            selectionCount: selectedIds.count,
            imageSelectionCount: selectedImageIDs(model).count,
            thumbnailIds: selectedIds,
            photoLibrary: photoLibrary,
            libraryQueries: dependencies.libraryQueries,
            isDeleting: isDeleting,
            isPreparingShare: isPreparingShare,
            onShare: { shareSelected(model) },
            onClose: { withAnimation { stopSelecting() } },
            onDeselect: { toggleSelection(of: $0) },
            onCollage: { presentCollage(model) },
            onVideo: { presentVideoStudio(model) },
            onCompare: { isComparePresented = true },
            onCompress: { presentCompression(model) },
            onDelete: { deleteSelected(model) },
            onAddToCollection: { addToCollection(model) },
            onExportEXIF: { exportEXIF(model) },
            onDuplicate: { duplicateSelected(model) }
        )
    }

    private var bottomChromeInset: CGFloat {
        if #available(iOS 26.0, *) { 8 } else { 100 }
    }

    // MARK: ⋯ actions

    private func addToCollection(_ model: SmartAlbumDetailModel) {
        let assets = selectedIds.compactMap { model.asset(for: $0) }
        guard !assets.isEmpty else { return }
        addToCollectionPresentation = AddToCollectionPresentation(assets: assets)
    }

    private func exportEXIF(_ model: SmartAlbumDetailModel) {
        let imageIDs = selectedImageIDs(model)
        guard !imageIDs.isEmpty else { return }
        Task {
            let byId = (try? dependencies.libraryQueries.metadata(assetIds: imageIDs)) ?? [:]
            let rows = imageIDs.compactMap { byId[$0] }
            guard !rows.isEmpty else {
                actionErrorMessage = "These photos aren't indexed yet — their EXIF isn't available."
                return
            }
            do {
                let url = try ExifCSVExporter.writeTemporaryFile(rows)
                PhotoShareSheet.present(items: [url])
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func duplicateSelected(_ model: SmartAlbumDetailModel) {
        guard !selectedIds.isEmpty, !isDuplicating else { return }
        let assets = selectedIds.compactMap { model.asset(for: $0) }
        guard !assets.isEmpty else { return }
        isDuplicating = true
        Task {
            defer { isDuplicating = false }
            do {
                _ = try await photoLibrary.duplicateAssets(assets)
                photoLibrary.publishAppCreatedAsset()
                withAnimation { stopSelecting() }
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // During selection the nav bar is hidden entirely (controls live in the
        // floating overlay), so this only renders while browsing.
        ToolbarItem(placement: .topBarTrailing) {
            if model?.items.isEmpty == false, !isSelecting {
                Button {
                    isSelecting = true
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .accessibilityLabel("Select photos")
            }
        }
    }
}
