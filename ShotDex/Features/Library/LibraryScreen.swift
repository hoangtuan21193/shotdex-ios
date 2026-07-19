import Photos
import SwiftUI

/// Library tab: permission-aware photo grid with filter, sort and search.
struct LibraryScreen: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppNavigation.self) private var navigation

    /// Owned by HomeTabScaffold so the search sheet shares the same state.
    let controller: LibraryController?

    @State private var isFilterPresented = false
    /// Persisted density (column count), shared with Album Detail.
    @AppStorage(SettingsKeys.gridColumns) private var storedColumns = 3
    @State private var selectedPhotoIndex: Int?

    /// Multi-select mode: uncapped selection of asset ids kept in pick
    /// order (Compare panes follow it); ids survive grid reloads.
    @State private var isSelecting = false
    @State private var selectedIds: [String] = []
    @State private var isComparePresented = false
    /// Selection snapshot at swipe-drag start; each move re-applies the
    /// dragged range on top of it so backtracking un-does.
    @State private var swipeBaseline: [String] = []
    /// Bumped on Library-tab retap — the collection view scrolls back to
    /// the newest photos.
    @State private var retapResetCount = 0
    @State private var isDeleting = false
    @State private var deleteErrorMessage: String?
    /// Index indicator: compact chip by default (top-trailing), tap to
    /// expand into the full detail card; tapping the grid collapses it.
    @State private var isIndexPanelExpanded = false

    var body: some View {
        Group {
            switch photoLibrary.authorizationState {
            case .notDetermined:
                requestAccessState
            case .denied:
                PermissionEmptyState(
                    title: "No Access to Photos",
                    message: "ShotDex needs access to your photo library to read camera and lens metadata. Your photos never leave your device.",
                    actionTitle: "Open Settings",
                    action: openAppSettings
                )
            case .restricted:
                PermissionEmptyState(
                    title: "Photos Access Restricted",
                    message: "Photo library access is restricted on this device, so ShotDex can't analyze your photos.",
                    actionTitle: nil,
                    action: nil
                )
            case .authorized, .limited:
                if let controller {
                    gridContent(controller)
                } else {
                    ProgressView()
                }
            }
        }
        .toolbar { toolbarContent }
        .task(id: "\(photoLibrary.authorizationState.canReadLibrary)-\(controller != nil)") {
            guard photoLibrary.authorizationState.canReadLibrary, let controller else { return }
            controller.reload()
            controller.refreshFilterOptions()
            controller.startIndexing()
        }
        .onChange(of: photoLibrary.libraryChangeToken) {
            // Reload first so PhotoKit-new photos appear immediately (fast
            // path), not only after the index run finishes; then index them.
            controller?.reload()
            controller?.startIndexing()
        }
        .sheet(isPresented: $isFilterPresented) {
            if let controller {
                FilterSheet(
                    criteria: Binding(
                        get: { controller.criteria },
                        set: { controller.criteria = $0 }
                    ),
                    availableBrands: controller.availableBrands,
                    availableBodies: controller.availableBodies,
                    availableLenses: controller.availableLenses
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { selectedPhotoIndex != nil },
            set: { if !$0 { selectedPhotoIndex = nil } }
        )) {
            if let controller, let index = selectedPhotoIndex {
                PhotoDetailScreen(controller: controller, currentIndex: index)
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
            if select {
                let existing = Set(swipeBaseline)
                selectedIds = swipeBaseline + rangeIds.filter { !existing.contains($0) }
            } else {
                let range = Set(rangeIds)
                selectedIds = swipeBaseline.filter { !range.contains($0) }
            }
        case .ended:
            swipeBaseline = []
        }
    }

    private func deleteSelected(_ controller: LibraryController) {
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

    private func stopSelecting() {
        isSelecting = false
        selectedIds = []
        swipeBaseline = []
    }

    private func isPhotoSelected(_ assetId: String) -> Bool {
        selectedIds.contains(assetId)
    }

    /// Compare panes follow the pick order of the selection. Full rows are
    /// fetched on demand — the grid only holds slim items. A photo deleted
    /// mid-selection just drops out.
    private func comparePhotos(_ controller: LibraryController) -> [ComparePhoto]? {
        guard (2...CompareScreen.maxPhotoCount).contains(selectedIds.count) else { return nil }
        let metadataById = (try? dependencies.libraryQueryDAO.metadata(assetIds: selectedIds)) ?? [:]
        let assets = PhotoLibraryService.fetchAssets(ids: selectedIds)
        let assetById = Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) })
        let photos = selectedIds.compactMap { id in
            metadataById[id].map { ComparePhoto(metadata: $0, asset: assetById[id]) }
        }
        return photos.count >= 2 ? photos : nil
    }

    // MARK: Grid

    @ViewBuilder
    private func gridContent(_ controller: LibraryController) -> some View {
        VStack(spacing: 0) {
            if photoLibrary.authorizationState == .limited {
                LimitedAccessBanner {
                    photoLibrary.presentLimitedLibraryPicker()
                }
                .padding(.top, 4)
            }

            if !controller.criteria.isEmpty {
                FilterChipsBar(
                    criteria: Binding(
                        get: { controller.criteria },
                        set: { controller.criteria = $0 }
                    ),
                    matchCount: controller.matchCount
                )
            }

            if controller.items.isEmpty {
                ScrollView {
                    emptyState(controller)
                        .padding(.top, 80)
                }
            } else {
                photoGrid(controller)
            }
        }
        .onChange(of: navigation.libraryRetapToken) {
            retapResetCount += 1
        }
        // Indexing indicator floats at the top-trailing corner, on the same
        // row as the pinned date-section header chip on the left (matching its
        // 4pt top inset) — out of the way of the newest photos at the bottom.
        .overlay(alignment: .topTrailing) {
            if controller.isIndexing, !isSelecting {
                indexIndicator(controller)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .onDisappear { isIndexPanelExpanded = false }
            }
        }
        .overlay(alignment: .bottom) {
            if isSelecting {
                selectionTray(controller)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    /// Floating tray while picking photos: Compare (2–4) + Delete.
    private func selectionTray(_ controller: LibraryController) -> some View {
        SelectionActionsTray(
            selectionCount: selectedIds.count,
            onCompare: { isComparePresented = true },
            onDelete: { deleteSelected(controller) },
            isDeleting: isDeleting
        )
        .padding(.horizontal)
        .padding(.bottom, bottomChromeInset)
    }

    private func photoGrid(_ controller: LibraryController) -> some View {
        PhotoGridCollectionView(
            photos: controller.items,
            assetProvider: { index, _ in controller.asset(atFlatIndex: index) },
            isDateSectioned: controller.sort.isDateSort,
            anchorsBottom: true,
            contentVersion: controller.contentGeneration,
            jumpToNewestToken: retapResetCount,
            columnCount: Binding(
                get: { GridDensity.clamped(storedColumns) },
                set: { storedColumns = $0 }
            ),
            isSelecting: isSelecting,
            selectedIds: selectedIds,
            bottomInset: bottomChromeInset,
            photoLibrary: photoLibrary,
            onTap: { index, item in
                if isIndexPanelExpanded { setIndexPanelExpanded(false) }
                if isSelecting {
                    toggleSelection(of: item.assetId)
                } else {
                    selectedPhotoIndex = index
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
            onUserScroll: {
                if isIndexPanelExpanded { setIndexPanelExpanded(false) }
            }
        )
        .ignoresSafeArea(edges: .bottom)
        .sensoryFeedback(.selection, trigger: selectedIds.count)
    }

    @ViewBuilder
    private func emptyState(_ controller: LibraryController) -> some View {
        if controller.isIndexing {
            VStack(spacing: 12) {
                if let progress = controller.indexProgress, progress.total > 0 {
                    ProgressView(value: progress.fraction)
                        .frame(maxWidth: 220)
                    Text("Indexing \(progress.processed) of \(progress.total) photos (\(progress.percent)%)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                    Text("Indexing your library…")
                        .foregroundStyle(.secondary)
                }
                if let network = controller.indexNetworkStatus {
                    Text(network.displayLine)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text("Only metadata is read — full photos are never downloaded, so memory use stays low. The app may feel slow until indexing finishes.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        } else if controller.isLoading {
            // The full-library query is async — don't flash "No Photos"
            // while the first load is in flight.
            ProgressView()
        } else if !controller.criteria.isEmpty {
            ContentUnavailableView {
                Label("No photos match these filters.", systemImage: "camera.filters")
            } actions: {
                Button("Clear Filters") {
                    controller.criteria = .empty
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView(
                "No Photos",
                systemImage: "photo.on.rectangle",
                description: Text("Your photo library appears to be empty.")
            )
        }
    }

    /// `progress` is nil until the pipeline emits its first callback (run
    /// start, and long skip-scans of an incremental pass) — the panel must
    /// still be visible then, matching the Settings row.
    ///
    /// Compact by default; a tap expands it in place to show the file
    /// currently being read plus the metadata explainer, and any tap
    /// (screen-wide catcher in the overlay) collapses it again.
    @ViewBuilder
    private func indexIndicator(_ controller: LibraryController) -> some View {
        if isIndexPanelExpanded {
            expandedIndexCard(controller)
        } else {
            collapsedIndexChip(controller)
        }
    }

    /// Default state: a compact glass capsule — spinner + "Indexing" + the
    /// percent. Tap expands to the full detail card.
    private func collapsedIndexChip(_ controller: LibraryController) -> some View {
        Button {
            setIndexPanelExpanded(true)
        } label: {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                if let progress = controller.indexProgress, progress.total > 0 {
                    Text("Indexing \(progress.percent)%")
                        .font(.caption.weight(.medium).monospacedDigit())
                } else {
                    Text("Indexing")
                        .font(.caption.weight(.medium))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            controller.indexProgress.map { "Indexing, \($0.percent) percent" } ?? "Indexing"
        )
        .accessibilityHint("Double tap to show indexing details")
    }

    /// Expanded state (on tap): full progress, network status, the files
    /// being read, the metadata explainer, and Cancel. Anchored top-right,
    /// width-capped; tapping it or the grid collapses back to the chip.
    private func expandedIndexCard(_ controller: LibraryController) -> some View {
        let progress = controller.indexProgress
        return GlassPanel {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    if let progress {
                        Text("Indexing \(progress.processed)/\(progress.total) (\(progress.percent)%)")
                            .font(.caption.weight(.medium).monospacedDigit())
                    } else {
                        Text("Indexing…")
                            .font(.caption.weight(.medium))
                    }
                    Spacer()
                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress?.fraction ?? 0)
                if let network = controller.indexNetworkStatus {
                    Text(network.displayLine)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text("Only metadata is read — full photos are never downloaded. The app may feel slow until indexing finishes.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Cancel") {
                    controller.cancelIndexing()
                }
                .font(.caption.weight(.medium))
            }
            .padding(12)
        }
        .frame(maxWidth: 300)
        .contentShape(Rectangle())
        .onTapGesture { setIndexPanelExpanded(false) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            progress.map { "Indexing \($0.processed) of \($0.total) photos, \($0.percent) percent" }
                ?? "Indexing"
        )
        .accessibilityHint("Double tap to collapse")
    }

    private func setIndexPanelExpanded(_ expanded: Bool) {
        withAnimation(.snappy(duration: 0.25)) {
            isIndexPanelExpanded = expanded
        }
    }

    /// Pre-iOS 26 the floating custom chrome overlaps the content bottom.
    private var bottomChromeInset: CGFloat {
        if #available(iOS 26.0, *) { 8 } else { 100 }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Separate items so each button gets its own Liquid Glass circle
        // on iOS 26 instead of sharing one capsule.
        ToolbarItem(placement: .topBarLeading) {
            SettingsDrawerButton()
        }
        ToolbarItem(placement: .topBarTrailing) {
            if controller != nil {
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
        ToolbarItem(placement: .topBarTrailing) {
            if let controller {
                Button {
                    controller.refreshFilterOptions()
                    isFilterPresented = true
                } label: {
                    Image(systemName: controller.criteria.isEmpty
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel("Filters")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if let controller {
                Menu {
                    Picker("Sort", selection: Binding(
                        get: { controller.sort },
                        set: { controller.sort = $0 }
                    )) {
                        ForEach(SortOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
                .accessibilityLabel("Sort")
            }
        }
    }

    // MARK: Permission states

    private var requestAccessState: some View {
        PermissionEmptyState(
            title: "Explore Your Photo Metadata",
            message: "Browse your library by camera, lens and exposure settings. Photos and metadata stay on your device.",
            actionTitle: "Allow Photo Access",
            action: {
                Task { await photoLibrary.requestAuthorization() }
            }
        )
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// Shared empty state for permission-related situations.
struct PermissionEmptyState: View {
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "photo.badge.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// Banner shown when the user granted Limited Photos Access.
struct LimitedAccessBanner: View {
    var onManage: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Limited Access")
                    .font(.subheadline.weight(.semibold))
                Text("ShotDex only analyzes the photos you selected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Manage", action: onManage)
                .font(.subheadline.weight(.medium))
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    return NavigationStack {
        LibraryScreen(controller: LibraryController(dependencies: dependencies))
    }
    .environment(dependencies)
    .environment(dependencies.photoLibrary)
    .environment(AppNavigation())
}
