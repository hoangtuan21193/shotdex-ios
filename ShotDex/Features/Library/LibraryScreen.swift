import Photos
import SwiftUI

/// Library tab: permission-aware photo grid with filter, sort and search.
struct LibraryScreen: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppNavigation.self) private var navigation

    /// Owned by HomeTabScaffold so the search sheet shares the same state.
    let controller: LibraryController?

    @State private var isImportPresented = false
    @State private var isAdvancedSearchPresented = false
    /// Persisted density (column count), shared with Album Detail.
    @AppStorage(SettingsKeys.gridColumns) private var storedColumns = 3
    @State private var viewerTarget: PhotoViewerTarget?

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
    @State private var isPreparingShare = false
    @State private var deleteErrorMessage: String?
    /// Measured height of the selection bar; the grid insets by it while
    /// selecting so bottom rows can be scrolled clear of the bar.
    @State private var selectionBarHeight: CGFloat = 96
    /// Index indicator: a compact chip in the top-leading toolbar (right of
    /// the Settings gear); tapping presents the detail popover. This drives
    /// the popover's presentation.
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
        // Select mode replaces the tab bar with the full-width selection bar.
        .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
        .onChange(of: isSelecting) { navigation.hidesTabBar = isSelecting }
        .onDisappear { navigation.hidesTabBar = false }
        // Inline (not the default large-title) mode: keeps the bar a thin
        // translucent strip the grid scrolls under, instead of a tall empty
        // band. Matches Album Detail.
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(photoLibrary.authorizationState.canReadLibrary)-\(controller != nil)") {
            guard photoLibrary.authorizationState.canReadLibrary, let controller else { return }
            controller.reload()
            controller.refreshFilterOptions()
            controller.startIndexing()
        }
        .onChange(of: photoLibrary.libraryChangeToken) {
            // Reload-then-index outside a run; coalesced into the end-of-run
            // reload while indexing (see LibraryController.handleLibraryChange).
            controller?.handleLibraryChange()
        }
        .onChange(of: navigation.advancedSearchToken) {
            // Advanced search is routed here from the search tab (a sheet can't
            // present over the iOS 26 search-role tab); open it on Library.
            isAdvancedSearchPresented = true
        }
        .fullScreenCover(isPresented: $isImportPresented) {
            ImportScreen(service: dependencies.importService)
        }
        .sheet(isPresented: $isAdvancedSearchPresented) {
            if let controller {
                AdvancedSearchSheet(controller: controller, dependencies: dependencies) {}
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
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

    /// Gathers the selected assets (downloading iCloud-only originals) and
    /// presents a single system share sheet.
    private func shareSelected() {
        guard !selectedIds.isEmpty, !isPreparingShare else { return }
        let ids = selectedIds
        isPreparingShare = true
        Task {
            let assets = PhotoLibraryService.fetchAssets(ids: ids)
            let items = await PhotoShareSheet.gather(assets: assets)
            isPreparingShare = false
            PhotoShareSheet.present(items: items)
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
        // Videos have no metadata row (index is image-only) — require the
        // asset instead, and let the caption go missing.
        let photos = selectedIds.compactMap { id -> ComparePhoto? in
            guard let asset = assetById[id] else { return nil }
            return ComparePhoto(metadata: metadataById[id], asset: asset)
        }
        return photos.count >= 2 ? photos : nil
    }

    // MARK: Grid

    @ViewBuilder
    private func gridContent(_ controller: LibraryController) -> some View {
        gridBody(controller)
            // Banner + chips ride in the top safe-area inset (not a VStack)
            // so the grid stays the root scroll view: photos scroll under the
            // translucent nav bar chrome edge-to-edge, matching Album Detail.
            .safeAreaInset(edge: .top, spacing: 0) {
                topAccessories(controller)
            }
            .onChange(of: navigation.libraryRetapToken) {
            retapResetCount += 1
        }
        // Index-detail dropdown: opened from the toolbar chip, drops into the
        // grid's top safe area (just below the nav bar, clear of the toolbar
        // buttons). Full-width, single GlassPanel material.
        .overlay(alignment: .top) {
            if isIndexPanelExpanded,
               controller.isIndexing || controller.indexStreamingPaused || controller.indexAutoRetryDate != nil,
               !isSelecting {
                indexDetailPanel(controller)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if isSelecting {
                selectionTray(controller)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Reset the expanded state once no index status is active, so a later
        // run doesn't reopen the dropdown.
        .onChange(of: controller.isIndexing || controller.indexStreamingPaused || controller.indexAutoRetryDate != nil) { _, active in
            if !active { isIndexPanelExpanded = false }
        }
    }

    @ViewBuilder
    private func gridBody(_ controller: LibraryController) -> some View {
        if controller.items.isEmpty {
            ScrollView {
                emptyState(controller)
                    .padding(.top, 80)
            }
        } else {
            photoGrid(controller)
        }
    }

    /// Limited-access banner + active filter chips, pinned in the top safe
    /// area above the scrolling grid. Empty (zero height, no inset) when
    /// neither applies.
    @ViewBuilder
    private func topAccessories(_ controller: LibraryController) -> some View {
        VStack(spacing: 0) {
            if photoLibrary.authorizationState == .limited {
                LimitedAccessBanner {
                    photoLibrary.presentLimitedLibraryPicker()
                }
                .padding(.top, 4)
            }

            if let advancedQuery = controller.advancedQuery, !advancedQuery.isEmpty {
                AdvancedSearchBar(
                    query: advancedQuery,
                    matchCount: controller.matchCount,
                    onEdit: { isAdvancedSearchPresented = true },
                    onClear: { controller.advancedQuery = nil }
                )
            } else if !controller.criteria.isEmpty {
                FilterChipsBar(
                    criteria: Binding(
                        get: { controller.criteria },
                        set: { controller.criteria = $0 }
                    ),
                    matchCount: controller.matchCount
                )
            }
        }
    }

    /// Full-width bottom bar while picking photos: Share, Compare (2–4),
    /// Delete, plus a thumbnail preview of the selection.
    private func selectionTray(_ controller: LibraryController) -> some View {
        SelectionBottomBar(
            selectionCount: selectedIds.count,
            thumbnailIds: selectedIds,
            photoLibrary: photoLibrary,
            onCompare: { isComparePresented = true },
            onDelete: { deleteSelected(controller) },
            onDeselect: { toggleSelection(of: $0) },
            isDeleting: isDeleting
        )
        .measureHeight(into: $selectionBarHeight)
    }

    private func photoGrid(_ controller: LibraryController) -> some View {
        PhotoGridCollectionView(
            photos: controller.items,
            assetProvider: { index, _ in controller.asset(atFlatIndex: index) },
            isDateSectioned: controller.sort.isDateSort,
            anchorsBottom: true,
            contentVersion: controller.contentGeneration,
            contentRefreshVersion: controller.contentRefreshGeneration,
            jumpToNewestToken: retapResetCount,
            columnCount: Binding(
                get: { GridDensity.clamped(storedColumns) },
                set: { storedColumns = $0 }
            ),
            isSelecting: isSelecting,
            selectedIds: selectedIds,
            bottomInset: isSelecting ? selectionBarHeight : bottomChromeInset,
            photoLibrary: photoLibrary,
            onTap: { _, item in
                if isIndexPanelExpanded { setIndexPanelExpanded(false) }
                if isSelecting {
                    toggleSelection(of: item.assetId)
                } else if let index = controller.index(of: item.assetId) {
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
            onUserScroll: {
                if isIndexPanelExpanded { setIndexPanelExpanded(false) }
            },
            lazyMetadataProvider: { assetId in
                await controller.lazyBadgeItem(assetId: assetId)
            }
        )
        // Fill behind the top nav bar too (not just bottom): the collection
        // view's automatic content-inset adjustment + anchor() position items
        // below the bar, so photos scroll under the translucent chrome instead
        // of leaving a black band behind the buttons.
        .ignoresSafeArea()
        .sensoryFeedback(.selection, trigger: selectedIds.count)
    }

    @ViewBuilder
    private func emptyState(_ controller: LibraryController) -> some View {
        if let retryAt = controller.indexAutoRetryDate {
            VStack(spacing: 12) {
                Image(systemName: "icloud.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("iCloud isn't responding")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 4) {
                    Text("Retrying automatically in")
                    Text(timerInterval: Date.now...max(Date.now, retryAt), countsDown: true)
                        .monospacedDigit()
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                Text("\(controller.pendingICloudCount) photos are waiting. Indexing keeps retrying on its own — cellular or a different network usually helps too.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                HStack(spacing: 12) {
                    Button("Retry Now") {
                        controller.retryIncompleteNow()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Use Cellular") {
                        controller.enableCellularAndResume()
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else if controller.isIndexing {
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
        } else if controller.indexStreamingPaused {
            VStack(spacing: 12) {
                Image(systemName: "wifi.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Indexing paused — waiting for Wi-Fi")
                    .foregroundStyle(.secondary)
                Text("\(controller.pendingICloudCount) photos in iCloud will finish indexing once you're on Wi-Fi. Local metadata was read without using cellular data.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Use Cellular") {
                    controller.enableCellularAndResume()
                }
                .buttonStyle(.borderedProminent)
            }
        } else if controller.isLoading {
            // The full-library query is async — don't flash "No Photos"
            // while the first load is in flight.
            ProgressView()
        } else if controller.hasActiveQuery {
            ContentUnavailableView {
                Label("No photos match these filters.", systemImage: "camera.filters")
            } actions: {
                Button("Clear Filters") {
                    controller.criteria = .empty
                    controller.advancedQuery = nil
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
    /// Compact chip living in the top-leading toolbar, right of the Settings
    /// gear; a tap opens the detail popover (progress / paused / retry).
    private func indexChipButton(_ controller: LibraryController) -> some View {
        Button {
            setIndexPanelExpanded(!isIndexPanelExpanded)
        } label: {
            chipLabel(controller)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            controller.indexProgress.map { "Indexing, \($0.percent) percent" } ?? "Indexing"
        )
        .accessibilityHint("Shows indexing details")
    }

    @ViewBuilder
    private func chipLabel(_ controller: LibraryController) -> some View {
        let content = HStack(spacing: 6) {
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
        // Toolbar otherwise truncates the label; take intrinsic width so the
        // full "Indexing NN%" always shows.
        .fixedSize(horizontal: true, vertical: false)

        if #available(iOS 26.0, *) {
            // Native toolbar supplies the Liquid Glass capsule + insets;
            // ToolbarSpacer already separates it from the gear.
            content
                .padding(.horizontal, 8)
        } else {
            // Pre-26 toolbar buttons are bare — give the chip its own capsule
            // so it reads as a distinct control with breathing room.
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
                )
        }
    }

    /// Detail dropdown shown under the toolbar: live progress while indexing,
    /// the countdown card when iCloud isn't responding, or the Wi-Fi-paused
    /// card. One `GlassPanel` material — no nested popover container.
    @ViewBuilder
    private func indexDetailPanel(_ controller: LibraryController) -> some View {
        if controller.isIndexing {
            expandedIndexCard(controller)
        } else if let retryAt = controller.indexAutoRetryDate {
            // Between runs: iCloud couldn't serve, the next automatic
            // attempt is counting down. Indexing never sits dead.
            autoRetryCard(controller, retryAt: retryAt)
        } else {
            // Not actively indexing, but iCloud-only photos are waiting on
            // a Wi-Fi connection (metered cellular, not opted in).
            pausedIndexCard(controller)
        }
    }

    /// iCloud-not-responding card shown while the automatic retry counts
    /// down: live countdown, skip-the-wait retry, and the cellular shortcut.
    private func autoRetryCard(_ controller: LibraryController, retryAt: Date) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 6) {
                Label("iCloud not responding", systemImage: "icloud.slash")
                    .font(.caption.weight(.medium))
                HStack(spacing: 4) {
                    Text("Retrying in")
                    Text(timerInterval: Date.now...max(Date.now, retryAt), countsDown: true)
                        .monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                if controller.pendingICloudCount > 0 {
                    Text("\(controller.pendingICloudCount) photos still waiting for iCloud.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 12) {
                    Button("Retry Now") {
                        controller.retryIncompleteNow()
                    }
                    .font(.caption.weight(.medium))
                    Button("Use Cellular") {
                        controller.enableCellularAndResume()
                    }
                    .font(.caption.weight(.medium))
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("iCloud not responding, retrying automatically")
    }

    /// Persistent "waiting for Wi-Fi" card: no spinner (nothing is streaming),
    /// with a shortcut to opt into cellular and resume now.
    private func pausedIndexCard(_ controller: LibraryController) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    "Indexing paused — waiting for Wi-Fi",
                    systemImage: "wifi.slash"
                )
                .font(.caption.weight(.medium))
                if controller.pendingICloudCount > 0 {
                    Text("\(controller.pendingICloudCount) photos in iCloud left to read.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Use Cellular") {
                    controller.enableCellularAndResume()
                }
                .font(.caption.weight(.medium))
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Indexing paused, waiting for Wi-Fi")
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
                if let throughput = controller.indexThroughput {
                    Text(throughput.remainingText.map { "\(throughput.rateText) · \($0)" } ?? throughput.rateText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let network = controller.indexNetworkStatus {
                    Text(network.displayLine)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let diagnostics = controller.indexDiagnostics {
                    Text(diagnostics.thermalLine)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(diagnostics.iCloudLine)
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
        .frame(maxWidth: .infinity)
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

    /// Share button for the top-bar leading slot during select mode; a spinner
    /// replaces the glyph while the assets are being gathered.
    @ViewBuilder
    private var shareToolbarButton: some View {
        Button {
            shareSelected()
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
        // Separate items so each button gets its own Liquid Glass circle
        // on iOS 26 instead of sharing one capsule. In select mode the leading
        // slot shows Share in place of the Settings gear.
        ToolbarItem(placement: .topBarLeading) {
            if isSelecting {
                shareToolbarButton
            } else {
                SettingsDrawerButton()
            }
        }
        // Break the shared Liquid Glass container so the indexing chip reads as
        // its own control, not part of the Settings gear's tap target.
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .topBarLeading)
        }
        ToolbarItem(placement: .topBarLeading) {
            if let controller,
               controller.isIndexing || controller.indexStreamingPaused || controller.indexAutoRetryDate != nil,
               !isSelecting {
                indexChipButton(controller)
            }
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
            if let controller, !isSelecting {
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
        // Import from an external card/drive — rightmost trailing item, so it
        // sits in the top-right corner. Replaces the old quick-filter button
        // (Advanced Search covers ad-hoc filtering now).
        ToolbarItem(placement: .topBarTrailing) {
            if !isSelecting {
                Button {
                    isImportPresented = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .accessibilityLabel("Import photos")
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
