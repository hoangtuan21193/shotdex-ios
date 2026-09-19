import Photos
import SwiftUI

/// Paginated grid of one album, on the shared UIKit grid. Tapping opens the
/// fullscreen viewer; multi-select (tap, long-press or swipe) offers
/// Compare (2–4 photos) and Delete.
struct AlbumDetailScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(AppNavigation.self) private var navigation

    let album: AlbumItem

    @State private var model: AlbumDetailModel?
    @State private var viewerTarget: PhotoViewerTarget?
    /// Date of the photos under the top of the grid, shown under the title.
    @State private var visibleDate: String?

    /// Multi-select: uncapped asset ids, kept in pick order (Compare panes
    /// follow it).
    @State private var isSelecting = false
    @State private var selectedIds: [String] = []
    @State private var isComparePresented = false
    @State private var compressionPresentation: CompressionPresentation?
    @State private var multiEditPresentation: MultiEditPresentation?
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

    /// Persisted density (column count), shared with the Library grid.
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
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        // Title plus the date of what is on screen. The grid draws no date
        // headers any more, so this is where "when am I" lives.
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(album.title)
                        .font(.headline)
                        .lineLimit(1)
                    if let visibleDate {
                        Text(visibleDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.18), value: visibleDate)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }

        .toolbar { toolbarContent }
        // Selection keeps the navigation bar (its ⋯ and × live there, Photos
        // style) so the title and the grid's pinned date header stay put; only
        // the tab bar hides, clearing the bottom for `SelectionOverlay`.
        .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
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
        .task {
            if model == nil {
                let newModel = AlbumDetailModel(album: album, dependencies: dependencies)
                newModel.loadNextPage()
                model = newModel
            }
        }
        .onChange(of: photoLibrary.assetChangeToken) {
            guard !isSelecting else { return }
            let refreshed = AlbumDetailModel(album: album, dependencies: dependencies)
            refreshed.loadNextPage()
            model = refreshed
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
        .multiEditCover($multiEditPresentation, sourceAlbum: model?.sourceAlbum, onDismiss: stopSelecting)
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

    private func photoGrid(_ model: AlbumDetailModel) -> some View {
        PhotoGridCollectionView(
            photos: model.photos,
            assetProvider: { _, item in model.assetsById[item.assetId] },
            // Date headers only make sense while the album is in date order;
            // in the album's own arrangement they would cut the user's
            // sequence into groups it does not have.
            // Always one unbroken run. The album's date now rides in the
            // subtitle under its name, so a header every few rows would only
            // repeat it while pushing photos off screen.
            sectionMode: .flat,
            anchorsBottom: false,
            // Otherwise constant: album content is only ever appended (paging)
            // or pruned (delete), and count changes reload on their own.
            contentVersion: model.contentVersion,
            contentRefreshVersion: 0,
            jumpToNewestToken: 0,
            columnCount: Binding(
                get: { GridDensity.clamped(storedColumns) },
                set: { storedColumns = $0 }
            ),
            isSelecting: isSelecting,
            selectedIds: selectedIds,
            bottomInset: isSelecting ? navigation.selectionGridInset : bottomChromeInset,
            cullStates: dependencies.cullStore.states,
            cullVersion: dependencies.cullStore.version,
            photoLibrary: photoLibrary,
            onTap: { _, metadata in
                if isSelecting {
                    toggleSelection(of: metadata.assetId)
                } else if let index = model.index(of: metadata.assetId) {
                    viewerTarget = PhotoViewerTarget(id: metadata.assetId, startIndex: index)
                }
            },
            onLongPress: { metadata in
                if !isSelecting {
                    isSelecting = true
                    toggleSelection(of: metadata.assetId)
                }
            },
            onSwipeEvent: handleSwipeEvent,
            onNearEnd: { model.loadNextPage() },
            onUserScroll: {},
            onVisibleDateChange: { visibleDate = $0 },
            removal: model.lastRemoval,
            contextMenuProvider: { metadata in
                tileMenu(model, assetId: metadata.assetId).makeMenu()
            }
        )
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: Selection

    private func isPhotoSelected(_ assetId: String) -> Bool {
        selectedIds.contains(assetId)
    }

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

    /// Opens the editor on the whole selection. Same run a shoot lives in: an
    /// album is where a day's frames land, so batch editing has to reach here.
    private func presentMultiEdit(_ model: AlbumDetailModel) {
        let assets: [PHAsset] = selectedIds.compactMap { id -> PHAsset? in
            guard let asset = model.assetsById[id], asset.mediaType == .image else { return nil }
            return asset
        }
        guard let first = assets.first else { return }
        multiEditPresentation = MultiEditPresentation(assets: assets, first: first)
    }

    private func presentCompression(_ model: AlbumDetailModel) {
        let assets: [PHAsset] = selectedIds.compactMap { id -> PHAsset? in
            guard let asset = model.assetsById[id], asset.mediaType == .image else { return nil }
            return asset
        }
        guard !assets.isEmpty else { return }
        compressionPresentation = CompressionPresentation(
            assets: assets,
            sourceAlbum: model.sourceAlbum
        )
    }

    /// Selected *image* asset ids in pick order (videos dropped) for Collage.
    private func selectedImageIDs(_ model: AlbumDetailModel) -> [String] {
        selectedIds.filter { model.assetsById[$0]?.mediaType == .image }
    }

    private func presentCollage(_ model: AlbumDetailModel) {
        let assets = selectedImageIDs(model).compactMap { model.assetsById[$0] }
        guard CollageTemplateCatalog.supportedCounts.contains(assets.count) else { return }
        collagePresentation = CollagePresentation(assets: assets)
    }

    private func presentVideoStudio(_ model: AlbumDetailModel) {
        let assets = selectedIds.compactMap { model.assetsById[$0] }
        guard !assets.isEmpty else { return }
        videoStudioPresentation = VideoStudioPresentation(assets: assets, mode: .multiClip)
    }

    private func stopSelecting() {
        isSelecting = false
        selectedIds = []
        swipeBaseline = []
    }

    /// Compare panes follow the pick order of the selection.
    private func comparePhotos(_ model: AlbumDetailModel) -> [ComparePhoto]? {
        guard selectedIds.count >= CompareScreen.minPhotoCount else { return nil }
        // Videos have no metadata row (index is image-only) — require the
        // asset instead, and let the caption go missing.
        let photos = selectedIds.compactMap { id -> ComparePhoto? in
            guard let asset = model.assetsById[id] else { return nil }
            return ComparePhoto(metadata: model.metadata(for: id), asset: asset)
        }
        return photos.count >= 2 ? photos : nil
    }

    private func shareSelected(_ model: AlbumDetailModel) {
        guard !selectedIds.isEmpty, !isPreparingShare else { return }
        let assets = selectedIds.compactMap { model.assetsById[$0] }
        isPreparingShare = true
        Task {
            let items = await PhotoShareSheet.gather(assets: assets)
            isPreparingShare = false
            PhotoShareSheet.present(items: items)
        }
    }

    /// Removes the selection from this album without deleting the photos.
    private func removeFromAlbum(_ model: AlbumDetailModel, album: PHAssetCollection) {
        guard !selectedIds.isEmpty else { return }
        let ids = Set(selectedIds)
        Task {
            do {
                try await model.removeFromAlbum(ids: ids)
                withAnimation { stopSelecting() }
            } catch {
                deleteErrorMessage = error.localizedDescription
            }
        }
    }

    private func deleteSelected(_ model: AlbumDetailModel) {
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
            selectedIds: selectedIds,
            photoLibrary: photoLibrary,
            libraryQueries: dependencies.libraryQueries,
            isDeleting: isDeleting,
            isPreparingShare: isPreparingShare,
            onShare: { shareSelected(model) },
            onClose: { withAnimation { stopSelecting() } },
            onDeselect: { toggleSelection(of: $0) },
            onDeselectAll: { selectedIds = [] },
            onCollage: { presentCollage(model) },
            onVideo: { presentVideoStudio(model) },
            onCompare: { isComparePresented = true },
            onCompress: { presentCompression(model) },
            onEdit: { presentMultiEdit(model) },
            onDelete: { deleteSelected(model) },
            onAddToCollection: { addToCollection(model) },
            onExportEXIF: { exportEXIF(model) },
            onDuplicate: { duplicateSelected(model) },
            assetActions: dependencies.assetActions,
            onSelectAll: { selectedIds = model.photos.map(\.assetId) },
            // Only a real, mutable user album offers this; "All Photos" and
            // smart albums have no membership to remove from.
            onRemoveFromAlbum: model.sourceAlbum.map { album in
                { removeFromAlbum(model, album: album) }
            }
        )
    }

    private var bottomChromeInset: CGFloat {
        if #available(iOS 26.0, *) { 8 } else { 100 }
    }


    /// The long-press menu for one tile. Album Detail is the only screen that
    /// can also take a photo out of the album it is showing.
    private func tileMenu(_ model: AlbumDetailModel, assetId: String) -> PhotoTileContextMenu {
        let actions = dependencies.assetActions
        let isVideo = model.assetsById[assetId]?.mediaType == .video
        return PhotoTileContextMenu(
            assetId: assetId,
            isVideo: isVideo,
            actions: actions,
            onShare: { actions.share(ids: [assetId]) },
            onAddToAlbum: { actions.presentAddToAlbum(ids: [assetId]) },
            onDuplicate: { actions.duplicate(ids: [assetId]) },
            onDelete: {
                Task { try? await model.deleteAssets(ids: [assetId]) }
            },
            onRemoveFromAlbum: model.sourceAlbum == nil ? nil : {
                Task { try? await model.removeFromAlbum(ids: [assetId]) }
            }
        )
    }

    // MARK: ⋯ actions

    private func addToCollection(_ model: AlbumDetailModel) {
        let assets = selectedIds.compactMap { model.assetsById[$0] }
        guard !assets.isEmpty else { return }
        addToCollectionPresentation = AddToCollectionPresentation(assets: assets)
    }

    private func exportEXIF(_ model: AlbumDetailModel) {
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

    private func duplicateSelected(_ model: AlbumDetailModel) {
        guard !selectedIds.isEmpty, !isDuplicating else { return }
        let assets = selectedIds.compactMap { model.assetsById[$0] }
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

    /// Newest / oldest / the album's own order, remembered per album.
    private func sortMenu(_ model: AlbumDetailModel) -> some View {
        Menu {
            ForEach(AlbumSortOrder.allCases) { order in
                if order != .albumOrder || model.supportsAlbumOrder {
                    Button {
                        model.setSortOrder(order)
                    } label: {
                        if order == model.sortOrder {
                            Label(order.displayName, systemImage: "checkmark")
                        } else {
                            Label(order.displayName, systemImage: order.systemImage)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .tint(.primary)
        .accessibilityLabel("Sort photos")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Browsing: just Select. Selecting: the shared ⋯ + × items below.
        ToolbarItem(placement: .topBarTrailing) {
            if let model, !model.photos.isEmpty, !isSelecting {
                sortMenu(model)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if model?.photos.isEmpty == false, !isSelecting {
                // Spelled out, like Photos.
                Button("Select") {
                    isSelecting = true
                }
                .tint(.primary)
                .accessibilityLabel("Select photos")
            }
        }
        if isSelecting, let selectionModel = selectionBarModel() {
            SelectionToolbarItems(model: selectionModel)
        }
    }
}
