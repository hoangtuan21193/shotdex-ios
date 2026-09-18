import Photos
import SwiftUI

/// "On This Day" smart album: photos taken on one calendar date across
/// previous years, grouped by year. Supports changing the date and
/// multi-select deletion. Uses the shared UIKit grid with screen-supplied
/// year sections.
struct OnThisDayScreen: View {
    /// Which day to show. A tapped reminder opens its own day; everywhere else
    /// this is today.
    var initialDate: Date = .now

    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(AppNavigation.self) private var navigation

    @State private var model: OnThisDayModel?
    @State private var viewerTarget: PhotoViewerTarget?
    @State private var isDatePickerPresented = false

    /// Delete selection: asset ids in pick order, no count cap (unlike
    /// Compare), so Compare panes and the selection bar follow the taps.
    @State private var isSelecting = false
    @State private var isComparePresented = false
    @State private var compressionPresentation: CompressionPresentation?
    @State private var selectedIds: [String] = []
    @State private var swipeBaseline: [String] = []
    @State private var isDeleting = false
    @State private var isPreparingShare = false
    @State private var deleteErrorMessage: String?

    /// Persisted density (column count), shared with the Library grid.
    @AppStorage(SettingsKeys.gridColumns) private var storedColumns = 3

    var body: some View {
        Group {
            if let model {
                if model.photos.isEmpty {
                    placeholder(isLoading: model.isLoading)
                } else {
                    photoGrid(model)
                }
            } else {
                placeholder(isLoading: true)
            }
        }
        .navigationTitle(dateTitle)
        .navigationBarTitleDisplayMode(.inline)
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
                let newModel = OnThisDayModel(dependencies: dependencies, selectedDate: initialDate)
                newModel.reload()
                model = newModel
            }
        }
        // `assetChangeToken`, not `libraryChangeToken`: only an asset added or
        // removed can change which photos belong to this day. The broader token
        // also fires for content-only changes — a favorite toggle, the viewer
        // caching a rendition, an iCloud download — and each one reloaded the
        // grid, which jumped the scroll position back to the top.
        .onChange(of: photoLibrary.assetChangeToken) {
            // Skip while selecting so an external change doesn't wipe the
            // selection mid-flow; our own deletes already prune locally.
            guard !isSelecting else { return }
            model?.reload()
        }
        .sheet(isPresented: $isDatePickerPresented) {
            datePickerSheet
        }
        .fullScreenCover(item: $viewerTarget) { target in
            if let model {
                PhotoDetailScreen(model: model, currentIndex: target.startIndex)
            }
        }
        .fullScreenCover(isPresented: $isComparePresented, onDismiss: stopSelecting) {
            if let photos = comparePhotos() {
                CompareScreen(photos: photos)
            }
        }
        .fullScreenCover(item: $compressionPresentation, onDismiss: stopSelecting) { presentation in
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

    private var dateTitle: String {
        (model?.selectedDate ?? .now)
            .formatted(.dateTime.month(.wide).day())
    }

    @ViewBuilder
    private func placeholder(isLoading: Bool) -> some View {
        Group {
            if isLoading {
                ProgressView()
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 80)
    }

    // MARK: Grid

    private func photoGrid(_ model: OnThisDayModel) -> some View {
        PhotoGridCollectionView(
            photos: model.photos,
            assetProvider: { _, item in model.assetsById[item.assetId] },
            // Year groups are semantic, not derived from the date granularity
            // the grid would pick for itself.
            sectionMode: .custom(model.gridSections),
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
            onTap: { flatIndex, metadata in
                if isSelecting {
                    toggleSelection(of: metadata.assetId)
                } else {
                    // The grid's flat index *is* the index into
                    // `model.photos` — no lookup needed.
                    viewerTarget = PhotoViewerTarget(
                        id: metadata.assetId, startIndex: flatIndex
                    )
                }
            },
            onLongPress: { metadata in
                if !isSelecting {
                    isSelecting = true
                    toggleSelection(of: metadata.assetId)
                }
            },
            onSwipeEvent: handleSwipeEvent,
            // Everything is loaded up front — no pagination.
            onNearEnd: {},
            onUserScroll: {},
            removal: model.lastRemoval,
            contextMenuProvider: { metadata in
                tileMenu(assetId: metadata.assetId).makeMenu()
            }
        )
        .ignoresSafeArea(edges: .bottom)
    }


    /// The long-press menu for one tile.
    private func tileMenu(assetId: String) -> PhotoTileContextMenu {
        let actions = dependencies.assetActions
        let isVideo = model?.assetsById[assetId]?.mediaType == .video
        return PhotoTileContextMenu(
            assetId: assetId,
            isVideo: isVideo,
            actions: actions,
            onShare: { actions.share(ids: [assetId]) },
            onAddToAlbum: { actions.presentAddToAlbum(ids: [assetId]) },
            onDuplicate: { actions.duplicate(ids: [assetId]) },
            onDelete: { actions.delete(ids: [assetId]) }
        )
    }

    // MARK: Selection & deletion

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

    private func presentCompression() {
        guard let model else { return }
        let assets: [PHAsset] = selectedIds.compactMap { id -> PHAsset? in
            guard let asset = model.assetsById[id], asset.mediaType == .image else { return nil }
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

    /// The model the floating `SelectionOverlay` renders. On This Day stays
    /// action-lean — Share, Compare (2–4), Resize/Compress and Delete — so the
    /// Create cluster and ⋯ menu are absent (their closures left `nil`).
    private func selectionBarModel() -> SelectionBarModel {
        let imageCount = selectedIds.filter { model?.assetsById[$0]?.mediaType == .image }.count
        return SelectionBarModel(
            selectionCount: selectedIds.count,
            imageSelectionCount: imageCount,
            selectedIds: selectedIds,
            photoLibrary: photoLibrary,
            libraryQueries: dependencies.libraryQueries,
            isDeleting: isDeleting,
            isPreparingShare: isPreparingShare,
            onShare: shareSelected,
            onClose: { withAnimation { stopSelecting() } },
            onDeselect: { toggleSelection(of: $0) },
            onDeselectAll: { selectedIds = [] },
            onCompare: { isComparePresented = true },
            onCompress: presentCompression,
            onDelete: deleteSelected,
            assetActions: dependencies.assetActions,
            onSelectAll: { selectedIds = (model?.photos ?? []).map(\.assetId) }
        )
    }

    /// Compare panes follow the pick order of the selection.
    private func comparePhotos() -> [ComparePhoto]? {
        guard let model,
              selectedIds.count >= CompareScreen.minPhotoCount else { return nil }
        let photos = selectedIds.compactMap { id -> ComparePhoto? in
            guard let asset = model.assetsById[id] else { return nil }
            return ComparePhoto(metadata: model.metadata(for: id), asset: asset)
        }
        return photos.count >= 2 ? photos : nil
    }

    private func shareSelected() {
        guard let model, !selectedIds.isEmpty, !isPreparingShare else { return }
        let assets = selectedIds.compactMap { model.assetsById[$0] }
        isPreparingShare = true
        Task {
            let items = await PhotoShareSheet.gather(assets: assets)
            isPreparingShare = false
            PhotoShareSheet.present(items: items)
        }
    }

    private func deleteSelected() {
        guard let model, !selectedIds.isEmpty else { return }
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

    private var bottomChromeInset: CGFloat {
        if #available(iOS 26.0, *) { 8 } else { 100 }
    }

    // MARK: Date picker

    private var datePickerSheet: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Date",
                    selection: Binding(
                        get: { model?.selectedDate ?? .now },
                        set: { model?.selectedDate = $0 }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding(.horizontal)
                Spacer()
            }
            .navigationTitle("Pick a Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") {
                        model?.selectedDate = .now
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isDatePickerPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Browsing: date picker + Select. Selecting: the shared ⋯ + × items.
        ToolbarItem(placement: .topBarTrailing) {
            if !isSelecting {
                Button {
                    isDatePickerPresented = true
                } label: {
                    Image(systemName: "calendar")
                }
                .tint(.primary)
                .accessibilityLabel("Change date")
            }
        }
        // Select keeps its own Liquid Glass capsule, split off from the date
        // button — Photos separates them the same way.
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
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
        if isSelecting {
            SelectionToolbarItems(model: selectionBarModel())
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Photos on This Day", systemImage: "calendar.badge.clock")
        } description: {
            Text("No photos were taken on \(dateTitle) in previous years.")
        } actions: {
            Button("Pick Another Date") {
                isDatePickerPresented = true
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
