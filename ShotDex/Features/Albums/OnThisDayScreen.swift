import Photos
import SwiftUI

/// "On This Day" smart album: photos taken on one calendar date across
/// previous years, grouped by year. Supports changing the date and
/// multi-select deletion.
struct OnThisDayScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary

    @State private var controller: OnThisDayController?
    @State private var selectedPhotoIndex: Int?
    @State private var isDatePickerPresented = false

    /// Delete selection: asset ids, no count cap (unlike Compare).
    @State private var isSelecting = false
    @State private var selectedIds: Set<String> = []
    @State private var swipeBaselineIds: Set<String> = []
    @State private var isSwipeDragActive = false
    @State private var isDeleting = false
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
                if #unavailable(iOS 26.0) {
                    Color.clear.frame(height: 90)
                }
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
        .overlay(alignment: .bottom) {
            if isSelecting {
                deleteTray
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
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
        .fullScreenCover(isPresented: Binding(
            get: { selectedPhotoIndex != nil },
            set: { if !$0 { selectedPhotoIndex = nil } }
        )) {
            if let controller, let index = selectedPhotoIndex {
                PhotoDetailScreen(controller: controller, currentIndex: index)
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
                            gridTile(metadata, index: index, controller: controller)
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
        index: Int,
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
            } else {
                selectedPhotoIndex = index
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
            selectedIds = select
                ? swipeBaselineIds.union(ids)
                : swipeBaselineIds.subtracting(ids)
        case .ended:
            swipeBaselineIds = []
        }
    }

    private func stopSelecting() {
        isSelecting = false
        selectedIds = []
        swipeBaselineIds = []
    }

    private var deleteTray: some View {
        SelectionActionsTray(
            selectionCount: selectedIds.count,
            onCompare: nil,
            onDelete: deleteSelected,
            isDeleting: isDeleting
        )
        .padding(.horizontal)
        .padding(.bottom, bottomChromeInset)
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isDatePickerPresented = true
            } label: {
                Image(systemName: "calendar")
            }
            .accessibilityLabel("Change date")
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
