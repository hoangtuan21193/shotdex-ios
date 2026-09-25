import Photos
import SwiftUI

/// Grid of the photos matching a smart album's saved criteria, with the
/// conditions shown as read-only tokens at the top. Structurally a sibling of
/// `AlbumDetailScreen` (same viewer / multi-select / compare / delete), but
/// driven by a `SmartAlbumDetailModel` (criteria query) instead of a
/// PhotoKit collection.
struct SmartAlbumDetailScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    /// The coordinator whose sheets are attached above this screen — the
    /// window root's, not `dependencies.assetActions`.
    @Environment(\.assetActions) private var assetActions
    @Environment(\.presentServerUpload) private var presentServerUpload
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(AppNavigation.self) private var navigation

    let album: SmartAlbum

    @State private var model: SmartAlbumDetailModel?
    @State private var viewerTarget: PhotoViewerTarget?
    /// Date of the photos under the top of the grid, shown under the title.
    @State private var visibleDate: String?

    @State private var isSelecting = false
    @State private var selectedIds: [String] = []
    /// The Filter menu's narrowing (FS-06.09) — screen state, so the next
    /// visit starts from the whole album.
    @State private var filter = AlbumFilter()
    @State private var isAdvancedFilterPresented = false
    @State private var isComparePresented = false
    @State private var compressionPresentation: CompressionPresentation?
    @State private var stackPresentation: PhotoStackPresentation?
    @State private var panoramaPresentation: PanoramaMergePresentation?
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

    @AppStorage(SettingsKeys.gridColumns) private var storedColumns = 3

    var body: some View {
        filterWiring(content)
        // Empty while selecting, or the bar falls back to it once the
        // principal title below is cleared.
        .navigationTitle(isSelecting ? "" : album.name)
        .navigationBarTitleDisplayMode(.inline)
        // Title plus the date of what is on screen. The grid draws no date
        // headers any more, so this is where "when am I" lives.
        .toolbar {
            // Cleared while selecting, as in Library: the selection's own
            // Compare / Edit / ⋯ / × need the width, and on the pre-26 bar the
            // title otherwise lands against Edit and reads as part of it.
            ToolbarItem(placement: .principal) {
                if !isSelecting {
                    VStack(spacing: 0) {
                        Text(album.name)
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
        }

        .toolbar { toolbarContent }
        // Selection keeps the navigation bar (its ⋯ and × live there, Photos
        // style) so the title and the grid's pinned date header stay put; only
        // the tab bar hides, clearing the bottom for `SelectionOverlay`.
        .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
        .disablesBackSwipe(isSelecting)
        // Selection is left with ×, as in Photos: Back would walk out
        // mid-selection, and without it the bar holds exactly Library's
        // Compare · Edit · Filter · ⋯ · × — with it, × is pushed off a 402pt bar.
        .navigationBarBackButtonHidden(isSelecting)
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
            topAccessories
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
        .multiEditCover($multiEditPresentation, sourceAlbum: nil, onDismiss: stopSelecting)
        .panoramaMergeCover($panoramaPresentation, onSaved: { assetID in
            stopSelecting()
            navigation.openPhoto(assetId: assetID)
        })
        .photoStackCover($stackPresentation, onSaved: { assetID in
            // A smart album is a query the new photo may not match: open it in
            // Library (FS-01.09 §3).
            stopSelecting()
            navigation.openPhoto(assetId: assetID)
        })
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

    @ViewBuilder
    private var content: some View {
        if let model {
            photoGrid(model)
                .overlay {
                    if filter.isActive, model.items.isEmpty, !model.isLoading {
                        FilterEmptyState { filter.clear() }
                    }
                }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 80)
        }
    }

    /// Filter state into the model, and picks the new filter hides out of the
    /// selection (FS-01.06 §2) — kept out of `body` so it type-checks.
    private func filterWiring(_ content: some View) -> some View {
        content
            .sheet(isPresented: $isAdvancedFilterPresented) {
                if let model {
                    // Inside the album: Apply, the album's own count, no Save.
                    AdvancedSearchSheet(
                        initialQuery: filter.advancedQuery,
                        dependencies: dependencies,
                        confirmTitle: "Apply",
                        allowsSaveAsSmartAlbum: false,
                        countMatches: { query in await model.countMatching(query) },
                        onApply: { query in filter.setAdvancedQuery(query) }
                    )
                }
            }
            .onChange(of: filter) {
                Task { await model?.setFilter(filter) }
            }
            .onChange(of: model?.contentGeneration) {
                guard isSelecting, !selectedIds.isEmpty, let model else { return }
                let showing = Set(model.items.lazy.map(\.assetId))
                let kept = selectedIds.filter(showing.contains)
                if kept.count != selectedIds.count { selectedIds = kept }
            }
    }

    /// Library's Limited Access banner, then the saved conditions with the
    /// Filter menu's chips on the same row (FS-06.09 §4).
    private var topAccessories: some View {
        VStack(spacing: 0) {
            if photoLibrary.authorizationState == .limited {
                LimitedAccessBanner {
                    photoLibrary.presentLimitedLibraryPicker()
                }
                .padding(.top, 4)
            }
            if !album.query.isEmpty {
                SmartAlbumConditionsBar(
                    query: album.query,
                    matchCount: model?.matchCount ?? 0,
                    unfilteredCount: filter.isActive ? model?.unfilteredCount : nil,
                    filterChips: filterChips,
                    onEditFilter: filter.advancedQuery != nil ? { isAdvancedFilterPresented = true } : nil,
                    onClearFilter: filter.isActive ? { filter.clear() } : nil
                )
            } else if let advanced = filter.advancedQuery {
                AdvancedSearchBar(
                    query: advanced,
                    onEdit: { isAdvancedFilterPresented = true },
                    onRemoveRule: { ruleId in
                        var updated = advanced
                        updated.rules.removeAll { $0.id == ruleId }
                        filter.setAdvancedQuery(updated)
                    },
                    onClear: { filter.clear() },
                    onToggleMatchMode: {
                        var updated = advanced
                        updated.matchMode = updated.matchMode == .all ? .any : .all
                        filter.setAdvancedQuery(updated)
                    }
                )
            } else if !filter.criteria.isEmpty {
                FilterTokenBar(criteria: Binding(
                    get: { filter.criteria },
                    set: { filter.setCriteria($0) }
                ))
            }
        }
    }

    private var filterChips: [SmartAlbumConditionsBar.FilterChip] {
        if let advanced = filter.advancedQuery {
            return advanced.validRules.map { rule in
                SmartAlbumConditionsBar.FilterChip(
                    id: rule.id.uuidString,
                    label: rule.compactDisplaySummary,
                    removalAccessibilityLabel: "Remove condition: \(rule.displaySummary)",
                    onRemove: {
                        var updated = advanced
                        updated.rules.removeAll { $0.id == rule.id }
                        filter.setAdvancedQuery(updated)
                    }
                )
            }
        }
        return FilterTokenBar.tokens(for: filter.criteria).map { token in
            SmartAlbumConditionsBar.FilterChip(
                id: token.id,
                label: token.label,
                removalAccessibilityLabel: token.removalAccessibilityLabel,
                onRemove: {
                    var criteria = filter.criteria
                    token.clear(&criteria)
                    filter.setCriteria(criteria)
                }
            )
        }
    }

    private func filterMenu(_ model: SmartAlbumDetailModel) -> some View {
        PhotoFilterMenu(
            criteria: Binding(
                get: { filter.criteria },
                set: { filter.setCriteria($0) }
            ),
            isShowingAllItems: !filter.isActive,
            onShowAllItems: { filter.clear() },
            onAdvancedFilter: { isAdvancedFilterPresented = true }
        ) {
            Picker("Sort By", selection: Binding(
                get: { model.sortOrder },
                set: { order in Task { await model.setSortOrder(order) } }
            )) {
                ForEach(AlbumSortOrder.allCases.filter { $0 != .albumOrder }) { order in
                    Text(order.displayName).tag(order)
                }
            }
        }
    }

    private func photoGrid(_ model: SmartAlbumDetailModel) -> some View {
        PhotoGridCollectionView(
            photos: model.items,
            assetProvider: { index, _ in model.asset(atFlatIndex: index) },
            // One unbroken run; the date rides in the subtitle instead.
            sectionMode: .flat,
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
            onUserScroll: {},
            onVisibleDateChange: { visibleDate = $0 },
            removal: model.lastRemoval,
            contextMenuProvider: { item in
                tileMenu(assetId: item.assetId).makeMenu()
            }
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

    /// Opens the editor on the whole selection — a smart album ("Sony A7IV +
    /// 35mm, last 7 days") is exactly the run a photographer wants to grade as
    /// one.
    private func presentMultiEdit(_ model: SmartAlbumDetailModel) {
        let assets: [PHAsset] = selectedIds.compactMap { id -> PHAsset? in
            guard let asset = model.asset(for: id), asset.mediaType == .image else { return nil }
            return asset
        }
        guard let first = assets.first else { return }
        multiEditPresentation = MultiEditPresentation(assets: assets, first: first)
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

    /// Opens the Combine Photos row the user picked on the selection's photos.
    private func presentCombine(_ purpose: CombinePurpose, _ model: SmartAlbumDetailModel) {
        let assets = selectedImageIDs(model).compactMap { model.asset(for: $0) }
        guard assets.count >= CombinePurpose.minimumPhotoCount else { return }
        switch purpose {
        case .focusStack, .stackExposures:
            stackPresentation = PhotoStackPresentation(assets: assets, purpose: purpose)
        case .panorama:
            panoramaPresentation = PanoramaMergePresentation(assets: assets)
        }
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
        guard selectedIds.count >= CompareScreen.minPhotoCount else { return nil }
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
            onCombine: { presentCombine($0, model) },
            onDelete: { deleteSelected(model) },
            onAddToCollection: { addToCollection(model) },
            onExportEXIF: { exportEXIF(model) },
            onDuplicate: { duplicateSelected(model) },
            onUploadToServer: presentServerUpload.map { present in { present(selectedIds) } },
            assetActions: assetActions,
            onSelectAll: { selectedIds = model.items.map(\.assetId) }
        )
    }

    private var bottomChromeInset: CGFloat {
        AppTheme.Size.bottomChromeClearance
    }


    /// The long-press menu for one tile.
    private func tileMenu(assetId: String) -> PhotoTileContextMenu {
        // The shared instance only when nothing hosts this screen (previews).
        let actions = assetActions ?? dependencies.assetActions
        let isVideo = PhotoLibraryService.fetchAssets(ids: [assetId])
            .first?.mediaType == .video
        return PhotoTileContextMenu(
            assetId: assetId,
            isVideo: isVideo,
            actions: actions,
            onShare: { actions.share(ids: [assetId]) },
            onAddToCollection: { actions.presentAddToCollection(ids: [assetId]) },
            onDuplicate: { actions.duplicate(ids: [assetId]) },
            onDelete: { actions.delete(ids: [assetId]) }
        )
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
                let created = try await photoLibrary.duplicateAssets(assets)
                photoLibrary.publishAppCreatedAsset()
                // The selection stays: duplicating is a step in the middle of
                // a job (copy these, then add the copies to an album, or edit
                // them), and dropping out of selection mode makes the user
                // pick the same photos again to do the next thing.
                //
                // A copy is made resource by resource, and a resource that
                // cannot be written is skipped rather than throwing — so
                // "nothing was copied" arrives here as a zero, not an error,
                // and has to be said out loud or the command looks ignored.
                if created == 0 {
                    actionErrorMessage = "Those photos couldn't be copied."
                }
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Filter leads the trailing group and stays while selecting, as in
        // Library; the selection's ⋯ joins its capsule.
        ToolbarItem(placement: .topBarTrailing) {
            if let model, model.unfilteredCount > 0 || filter.isActive || !model.items.isEmpty {
                filterMenu(model)
            }
        }
        if isSelecting, let selectionModel = selectionBarModel() {
            SelectionToolbarItems(model: selectionModel)
        }
        if !isSelecting {
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if model?.items.isEmpty == false {
                    // Spelled out, like Photos.
                    Button("Select") {
                        isSelecting = true
                    }
                    .tint(.primary)
                    .accessibilityLabel("Select photos")
                }
            }
        }
    }
}
