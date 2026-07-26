import Photos
import SwiftUI

/// "On This Day" smart album: photos taken on one calendar date across
/// previous years, grouped by year. Supports changing the date and
/// multi-select deletion. Uses the shared UIKit grid with screen-supplied
/// year sections.
struct OnThisDayScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(AppNavigation.self) private var navigation

    @State private var controller: OnThisDayController?
    @State private var viewerTarget: PhotoViewerTarget?
    @State private var isDatePickerPresented = false

    /// Delete selection: asset ids in pick order, no count cap (unlike
    /// Compare), so Compare panes and the bottom tray follow the taps.
    @State private var isSelecting = false
    @State private var isComparePresented = false
    @State private var selectedIds: [String] = []
    @State private var swipeBaseline: [String] = []
    @State private var isDeleting = false
    @State private var isPreparingShare = false
    @State private var deleteErrorMessage: String?

    /// Persisted density (column count), shared with the Library grid.
    @AppStorage(SettingsKeys.gridColumns) private var storedColumns = 3

    var body: some View {
        Group {
            if let controller {
                if controller.photos.isEmpty {
                    placeholder(isLoading: controller.isLoading)
                } else {
                    photoGrid(controller)
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
                let newController = OnThisDayController(dependencies: dependencies)
                newController.reload()
                controller = newController
            }
        }
        .onChange(of: photoLibrary.libraryChangeToken) {
            // Skip while selecting so an external change doesn't wipe the
            // selection mid-flow; our own deletes already prune locally.
            guard !isSelecting else { return }
            controller?.reload()
        }
        .sheet(isPresented: $isDatePickerPresented) {
            datePickerSheet
        }
        .fullScreenCover(item: $viewerTarget) { target in
            if let controller {
                PhotoDetailScreen(controller: controller, currentIndex: target.startIndex)
            }
        }
        .fullScreenCover(isPresented: $isComparePresented, onDismiss: stopSelecting) {
            if let photos = comparePhotos() {
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

    private var dateTitle: String {
        (controller?.selectedDate ?? .now)
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

    private func photoGrid(_ controller: OnThisDayController) -> some View {
        PhotoGridCollectionView(
            photos: controller.photos,
            assetProvider: { _, item in controller.assetsById[item.assetId] },
            // Year groups are semantic, not derived from the date granularity
            // the grid would pick for itself.
            sectionMode: .custom(controller.gridSections),
            anchorsBottom: false,
            contentVersion: controller.contentGeneration,
            contentRefreshVersion: controller.contentRefreshGeneration,
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
                    // `controller.photos` — no lookup needed.
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

    /// Config the scaffold renders as the bottom bar — same as the other
    /// albums: Compare (2–4) + Delete + thumbnail preview, all in pick order.
    private func makeSelectionConfig() -> SelectionBarConfig {
        SelectionBarConfig(
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
        guard let controller,
              (2...CompareScreen.maxPhotoCount).contains(selectedIds.count) else { return nil }
        let photos = selectedIds.compactMap { id -> ComparePhoto? in
            guard let asset = controller.assetsById[id] else { return nil }
            return ComparePhoto(metadata: controller.metadata(for: id), asset: asset)
        }
        return photos.count >= 2 ? photos : nil
    }

    private func shareSelected() {
        guard let controller, !selectedIds.isEmpty, !isPreparingShare else { return }
        let assets = selectedIds.compactMap { controller.assetsById[$0] }
        isPreparingShare = true
        Task {
            let items = await PhotoShareSheet.gather(assets: assets)
            isPreparingShare = false
            PhotoShareSheet.present(items: items)
        }
    }

    private func deleteSelected() {
        guard let controller, !selectedIds.isEmpty else { return }
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
                        get: { controller?.selectedDate ?? .now },
                        set: { controller?.selectedDate = $0 }
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
                        controller?.selectedDate = .now
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
