import Photos
import SwiftUI

/// Paginated grid of one album, reusing PhotoGridTile. Tapping opens the
/// fullscreen viewer; multi-select (tap, long-press or swipe) offers
/// Compare (2–4 photos) and Delete.
struct AlbumDetailScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(AppNavigation.self) private var navigation

    let album: AlbumItem

    @State private var controller: AlbumDetailController?
    @State private var viewerTarget: PhotoViewerTarget?

    /// Multi-select: uncapped asset ids, kept in pick order (Compare panes
    /// follow it).
    @State private var isSelecting = false
    @State private var selectedIds: [String] = []
    @State private var isComparePresented = false
    @State private var swipeBaseline: [String] = []
    @State private var isDeleting = false
    @State private var isPreparingShare = false
    @State private var deleteErrorMessage: String?

    /// Persisted density (column count), shared with the Library grid.
    @AppStorage(SettingsKeys.gridColumns) private var storedColumns = 3

    var body: some View {
        Group {
            if let controller {
                photoGrid(controller)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 80)
            }
        }
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onChange(of: isSelecting) { navigation.hidesTabBar = isSelecting }
        .onChange(of: selectionSnapshot) {
            navigation.selectionBar = isSelecting ? makeSelectionConfig() : nil
        }
        .onAppear {
            if isSelecting { navigation.selectionBar = makeSelectionConfig() }
        }
        .onDisappear {
            navigation.hidesTabBar = false
            if isSelecting { navigation.selectionBar = nil }
        }
        .task {
            if controller == nil {
                let newController = AlbumDetailController(album: album, dependencies: dependencies)
                newController.loadNextPage()
                controller = newController
            }
        }
        .fullScreenCover(item: $viewerTarget) { target in
            if let controller {
                PhotoDetailScreen(controller: controller, currentIndex: target.startIndex)
            }
        }
        .fullScreenCover(isPresented: $isComparePresented, onDismiss: stopSelecting) {
            if let controller, let photos = comparePhotos(controller) {
                CompareScreen(photos: photos)
            }
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

    private func photoGrid(_ controller: AlbumDetailController) -> some View {
        PhotoGridCollectionView(
            photos: controller.photos,
            assetProvider: { _, item in controller.assetsById[item.assetId] },
            // Album fetch is hard-sorted by creationDate, so date headers
            // always apply here.
            isDateSectioned: true,
            anchorsBottom: false,
            // Constant: album content is only ever appended (paging) or
            // pruned (delete) — count changes reload without re-anchoring.
            contentVersion: 0,
            contentRefreshVersion: 0,
            jumpToNewestToken: 0,
            columnCount: Binding(
                get: { GridDensity.clamped(storedColumns) },
                set: { storedColumns = $0 }
            ),
            isSelecting: isSelecting,
            selectedIds: selectedIds,
            bottomInset: isSelecting ? navigation.selectionGridInset : bottomChromeInset,
            photoLibrary: photoLibrary,
            onTap: { _, metadata in
                if isSelecting {
                    toggleSelection(of: metadata.assetId)
                } else if let index = controller.index(of: metadata.assetId) {
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
            onNearEnd: { controller.loadNextPage() },
            onUserScroll: {}
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

    private func stopSelecting() {
        isSelecting = false
        selectedIds = []
        swipeBaseline = []
    }

    /// Compare panes follow the pick order of the selection.
    private func comparePhotos(_ controller: AlbumDetailController) -> [ComparePhoto]? {
        guard (2...CompareScreen.maxPhotoCount).contains(selectedIds.count) else { return nil }
        // Videos have no metadata row (index is image-only) — require the
        // asset instead, and let the caption go missing.
        let photos = selectedIds.compactMap { id -> ComparePhoto? in
            guard let asset = controller.assetsById[id] else { return nil }
            return ComparePhoto(metadata: controller.metadata(for: id), asset: asset)
        }
        return photos.count >= 2 ? photos : nil
    }

    private func shareSelected(_ controller: AlbumDetailController) {
        guard !selectedIds.isEmpty, !isPreparingShare else { return }
        let assets = selectedIds.compactMap { controller.assetsById[$0] }
        isPreparingShare = true
        Task {
            let items = await PhotoShareSheet.gather(assets: assets)
            isPreparingShare = false
            PhotoShareSheet.present(items: items)
        }
    }

    private func deleteSelected(_ controller: AlbumDetailController) {
        guard !selectedIds.isEmpty else { return }
        let ids = Set(selectedIds)
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await controller.deleteAssets(ids: ids)
                withAnimation { stopSelecting() }
            } catch let error as PHPhotosError where error.code == .userCancelled {
                // User dismissed the system confirm — keep the selection.
            } catch {
                deleteErrorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Tray & toolbar

    private struct SelectionSnapshot: Equatable {
        var isSelecting: Bool
        var ids: [String]
        var isDeleting: Bool
    }
    private var selectionSnapshot: SelectionSnapshot {
        SelectionSnapshot(isSelecting: isSelecting, ids: selectedIds, isDeleting: isDeleting)
    }

    /// Config the scaffold renders as the bottom bar (Compare 2–4 + Delete +
    /// thumbnail preview; Share is in the toolbar).
    private func makeSelectionConfig() -> SelectionBarConfig? {
        guard let controller else { return nil }
        return SelectionBarConfig(
            selectionCount: selectedIds.count,
            thumbnailIds: selectedIds,
            photoLibrary: photoLibrary,
            onCompare: { isComparePresented = true },
            onDelete: { deleteSelected(controller) },
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
            if let controller { shareSelected(controller) }
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
            if controller?.photos.isEmpty == false {
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
