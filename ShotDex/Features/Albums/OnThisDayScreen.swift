import Photos
import SwiftUI

/// "On This Day" smart album: photos taken on one calendar date across
/// previous years, grouped by year. Supports changing the date and
/// multi-select deletion.
struct OnThisDayScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(AppNavigation.self) private var navigation

    @State private var controller: OnThisDayController?
    @State private var viewerTarget: PhotoViewerTarget?
    @State private var isDatePickerPresented = false

    /// Delete selection: asset ids, no count cap (unlike Compare).
    @State private var isSelecting = false
    @State private var isComparePresented = false
    @State private var selectedIds: Set<String> = []
    @State private var swipeBaselineIds: Set<String> = []
    @State private var isSwipeDragActive = false
    @State private var isDeleting = false
    @State private var isPreparingShare = false
    @State private var deleteErrorMessage: String?
    /// Measured once so tiles size their thumbnails without a per-cell
    /// GeometryReader. Fixed 3-column grid, 2pt gaps.
    @State private var containerWidth: CGFloat = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
    private let calendar = Calendar.current

    private var cellWidth: CGFloat {
        guard containerWidth > 0 else { return 0 }
        return max(1, (containerWidth - 4) / 3)
    }

    var body: some View {
        ScrollView {
            if let controller {
                if controller.photos.isEmpty {
                    if controller.isLoading {
                        ProgressView()
                            .padding(.top, 80)
                    } else {
                        emptyState
                            .padding(.top, 80)
                    }
                } else {
                    sectionedGrid(controller)
                }
                // Bottom clearance: the floating chrome (pre-26 tab bar) or, while
                // selecting, the full-width selection bar — so the last row can
                // be scrolled clear of it.
                Color.clear.frame(height: bottomSpacerHeight)
            } else {
                ProgressView()
                    .padding(.top, 80)
            }
        }
        .coordinateSpace(name: SwipeToSelect.coordinateSpaceName)
        .scrollDisabled(isSwipeDragActive)
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

    // MARK: Grid

    private func sectionedGrid(_ controller: OnThisDayController) -> some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(controller.sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader(section)
                        .padding(.horizontal)
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(section.range, id: \.self) { index in
                            let metadata = controller.photos[index]
                            gridTile(metadata, controller: controller)
                        }
                    }
                }
            }
        }
        .measureWidth(into: $containerWidth)
        .padding(.top, 8)
        .swipeToSelect(
            isEnabled: isSelecting,
            orderedItems: controller.photos,
            isSelected: { selectedIds.contains($0) },
            isDragActive: $isSwipeDragActive,
            onEvent: handleSwipeEvent
        )
    }

    private func sectionHeader(_ section: OnThisDayYearSection) -> some View {
        let yearsAgo = calendar.component(.year, from: .now) - section.year
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(String(section.year))
                .font(.title3.bold())
            Text(yearsAgo == 1 ? "1 year ago" : "\(yearsAgo) years ago")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func gridTile(
        _ metadata: PhotoMetadata,
        controller: OnThisDayController
    ) -> some View {
        PhotoGridTile(
            item: metadata,
            asset: controller.assetsById[metadata.assetId],
            cellWidth: cellWidth
        )
        .overlay(alignment: .topTrailing) {
            if isSelecting {
                SelectionBadge(isSelected: selectedIds.contains(metadata.assetId))
            }
        }
        .overlay {
            if isSelecting, selectedIds.contains(metadata.assetId) {
                Rectangle().strokeBorder(Color.accentColor, lineWidth: 3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                toggleSelection(of: metadata)
            } else if let index = controller.index(of: metadata.assetId) {
                viewerTarget = PhotoViewerTarget(id: metadata.assetId, startIndex: index)
            }
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            if !isSelecting {
                isSelecting = true
                toggleSelection(of: metadata)
            }
        }
        .swipeSelectFrame(id: metadata.assetId, enabled: isSelecting)
    }

    // MARK: Selection & deletion

    private func toggleSelection(of metadata: PhotoMetadata) {
        if selectedIds.contains(metadata.assetId) {
            selectedIds.remove(metadata.assetId)
        } else {
            selectedIds.insert(metadata.assetId)
        }
    }

    private func handleSwipeEvent(_ event: SwipeSelectEvent) {
        switch event {
        case .began:
            swipeBaselineIds = selectedIds
        case .changed(let rangeIds, let select):
            let ids = Set(rangeIds)
            let updated = select
                ? swipeBaselineIds.union(ids)
                : swipeBaselineIds.subtracting(ids)
            if updated != selectedIds { selectedIds = updated }
        case .ended:
            swipeBaselineIds = []
        }
    }

    private func stopSelecting() {
        isSelecting = false
        selectedIds = []
        swipeBaselineIds = []
    }

    /// Selection is a `Set` here; normalize to an array for the snapshot (display
    /// order is applied separately in `orderedSelection`).
    private struct SelectionSnapshot: Equatable {
        var isSelecting: Bool
        var ids: [String]
        var isDeleting: Bool
    }
    private var selectionSnapshot: SelectionSnapshot {
        SelectionSnapshot(isSelecting: isSelecting, ids: Array(selectedIds), isDeleting: isDeleting)
    }

    /// Config the scaffold renders as the bottom bar — same as the other albums:
    /// Compare (2–4) + Delete + thumbnail preview. Selection is a `Set`, so the
    /// preview and Compare panes follow `controller.photos` order (see
    /// `orderedSelection`) rather than an arbitrary set iteration.
    private func makeSelectionConfig() -> SelectionBarConfig {
        SelectionBarConfig(
            selectionCount: selectedIds.count,
            thumbnailIds: orderedSelection,
            photoLibrary: photoLibrary,
            onCompare: { isComparePresented = true },
            onDelete: deleteSelected,
            onDeselect: { selectedIds.remove($0) },
            isDeleting: isDeleting
        )
    }

    /// Selected ids in display order (the grid's chronological order), since the
    /// backing store is an unordered `Set`.
    private var orderedSelection: [String] {
        guard let controller else { return Array(selectedIds) }
        return controller.photos.map(\.assetId).filter(selectedIds.contains)
    }

    /// Compare panes follow the display order of the selection.
    private func comparePhotos() -> [ComparePhoto]? {
        guard let controller,
              (2...CompareScreen.maxPhotoCount).contains(selectedIds.count) else { return nil }
        let photos = orderedSelection.compactMap { id -> ComparePhoto? in
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
        let ids = selectedIds
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

    private var bottomSpacerHeight: CGFloat {
        if isSelecting { return navigation.selectionGridInset }
        if #unavailable(iOS 26.0) { return 90 }
        return 0
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
