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
        .onChange(of: photoLibrary.libraryChangeToken) {
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
            onUserScroll: {}
        )
        .ignoresSafeArea(edges: .bottom)
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
    }
    private var selectionSnapshot: SelectionSnapshot {
        SelectionSnapshot(isSelecting: isSelecting, ids: selectedIds, isDeleting: isDeleting)
    }

    /// The selection-bar model the root tab view renders — same as the other
    /// albums: Compare (2–4) + Delete + thumbnail preview, all in pick order.
    private func selectionBarModel() -> SelectionBarModel {
        SelectionBarModel(
            selectionCount: selectedIds.count,
            thumbnailIds: selectedIds,
            photoLibrary: photoLibrary,
            onCompare: { isComparePresented = true },
            onDelete: deleteSelected,
            onDeselect: { toggleSelection(of: $0) },
            isDeleting: isDeleting
        )
    }

    /// Compare panes follow the pick order of the selection.
    private func comparePhotos() -> [ComparePhoto]? {
        guard let model,
              (2...CompareScreen.maxPhotoCount).contains(selectedIds.count) else { return nil }
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

    @ViewBuilder
    private var shareToolbarButton: some View {
        Button(action: shareSelected) {
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
            if isSelecting {
                Menu {
                    Button(action: presentCompression) {
                        Label(
                            "Resize & Compress",
                            systemImage: "arrow.down.right.and.arrow.up.left"
                        )
                    }
                    .disabled(
                        !selectedIds.contains {
                            model?.assetsById[$0]?.mediaType == .image
                        }
                    )
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More selection actions")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if !isSelecting {
                Button {
                    isDatePickerPresented = true
                } label: {
                    Image(systemName: "calendar")
                }
                .accessibilityLabel("Change date")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if model?.photos.isEmpty == false {
                Button {
                    if isSelecting {
                        stopSelecting()
                    } else {
                        isSelecting = true
                    }
                } label: {
                    Image(systemName: isSelecting ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .accessibilityLabel(isSelecting ? "Cancel selection" : "Select photos to delete")
            }
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
