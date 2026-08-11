import Photos
import SwiftUI

/// Library tab: permission-aware photo grid with filter, sort and search.
struct LibraryScreen: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppNavigation.self) private var navigation

    /// Owned by RootTabView so the search sheet shares the same state.
    let model: LibraryModel?

    @State private var isAdvancedSearchPresented = false
    /// Persisted density (column count), shared with Album Detail.
    @AppStorage(SettingsKeys.gridColumns) private var storedColumns = 3
    @State private var viewerTarget: PhotoViewerTarget?

    /// Multi-select mode: uncapped selection of asset ids kept in pick
    /// order (Compare panes follow it); ids survive grid reloads.
    @State private var isSelecting = false
    @State private var selectedIds: [String] = []
    @State private var isComparePresented = false
    @State private var compressionPresentation: CompressionPresentation?
    @State private var collagePresentation: CollagePresentation?
    @State private var videoStudioPresentation: VideoStudioPresentation?
    @State private var addToCollectionPresentation: AddToCollectionPresentation?
    /// Selection snapshot at swipe-drag start; each move re-applies the
    /// dragged range on top of it so backtracking un-does.
    @State private var swipeBaseline: [String] = []
    /// Bumped on Library-tab retap — the collection view scrolls back to
    /// the newest photos.
    @State private var retapResetCount = 0
    @State private var isDeleting = false
    @State private var isPreparingShare = false
    @State private var isDuplicating = false
    @State private var deleteErrorMessage: String?
    /// Errors from the ⋯ actions (Export EXIF, Duplicate) — its own alert so it
    /// never collides with the delete alert.
    @State private var actionErrorMessage: String?
    /// Index indicator: a compact token in the top-leading toolbar (right of
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
                if let model {
                    gridContent(model)
                } else {
                    ProgressView()
                }
            }
        }
        .toolbar { toolbarContent }
        // Selection mode runs full-bleed: the floating `SelectionOverlay` owns all
        // controls, so both the nav bar and the tab bar hide and the grid shows
        // through beneath the glass.
        .toolbar(isSelecting ? .hidden : .automatic, for: .navigationBar, .tabBar)
        .onChange(of: isSelecting) { navigation.hidesTabBar = isSelecting }
        // Publish the selection to the root tab view, which hosts the bar in the tab
        // bar's slot. Republished on any selection change so counts/thumbnails
        // stay live.
        .onChange(of: selectionSnapshot) {
            navigation.selectionBar = isSelecting ? selectionBarModel() : nil
        }
        // Re-publish on reappear: switching tabs clears the bar in onDisappear,
        // but selectionSnapshot is unchanged on return so onChange never re-fires.
        .onAppear {
            if isSelecting { navigation.selectionBar = selectionBarModel() }
        }
        .onDisappear {
            navigation.hidesTabBar = false
            if isSelecting { navigation.selectionBar = nil }
        }
        // Inline (not the default large-title) mode: keeps the bar a thin
        // translucent strip the grid scrolls under, instead of a tall empty
        // band. Matches Album Detail.
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(photoLibrary.authorizationState.canReadLibrary)-\(model != nil)") {
            guard photoLibrary.authorizationState.canReadLibrary, let model else { return }
            // Full-screen covers can cause this task to re-enter on dismissal.
            // The model owns the one-shot guard so returning from Detail
            // never restarts the two-phase load or re-anchors the grid.
            model.loadIfNeeded()
            model.refreshFilterOptions()
            // RootTabView owns auto-index scheduling so first paint gets a
            // short head start and indexing remains independent of lazy tabs.
        }
        .onChange(of: photoLibrary.assetChangeToken) {
            // Structural token only: viewing photos in Detail makes PhotoKit
            // cache renditions, and reacting to those would reload the grid and
            // start an index run every time Detail closes.
            // Reload-then-index outside a run; coalesced into the end-of-run
            // reload while indexing (see LibraryModel.libraryDidChange).
            model?.libraryDidChange()
        }
        .onChange(of: navigation.advancedSearchToken) {
            // Advanced search is routed here from the search tab (a sheet can't
            // present over the iOS 26 search-role tab); open it on Library.
            isAdvancedSearchPresented = true
        }
        .sheet(isPresented: $isAdvancedSearchPresented) {
            if let model {
                AdvancedSearchSheet(model: model, dependencies: dependencies) {}
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
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
        .fullScreenCover(item: $compressionPresentation) { presentation in
            CompressionScreen(
                assets: presentation.assets,
                sourceAlbum: presentation.sourceAlbum
            )
        }
        .fullScreenCover(item: $collagePresentation) { presentation in
            CollageScreen(assets: presentation.assets, onSaved: openSavedPhoto)
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

    private func presentCompression(_ model: LibraryModel) {
        let selected = Set(selectedIds)
        let photoIDs = model.items
            .filter { selected.contains($0.assetId) && $0.mediaType == PHAssetMediaType.image.rawValue }
            .map(\.assetId)
        let fetched = PhotoLibraryService.fetchAssets(ids: photoIDs)
        let byID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.localIdentifier, $0) })
        let assets: [PHAsset] = photoIDs.compactMap { byID[$0] }
        guard !assets.isEmpty else { return }
        compressionPresentation = CompressionPresentation(
            assets: assets,
            sourceAlbum: nil
        )
    }

    /// Selected *image* asset ids, in pick order (videos dropped) — the
    /// selection itself stays mixed; Collage just ignores the videos.
    private func selectedImageIDs(_ model: LibraryModel) -> [String] {
        let imageIDs = Set(
            model.items
                .filter { $0.mediaType == PHAssetMediaType.image.rawValue }
                .map(\.assetId)
        )
        return selectedIds.filter { imageIDs.contains($0) }
    }

    private func presentCollage(_ model: LibraryModel) {
        let assets = PhotoLibraryService.fetchAssets(ids: selectedImageIDs(model))
        guard CollageTemplateCatalog.supportedCounts.contains(assets.count) else { return }
        collagePresentation = CollagePresentation(assets: assets)
    }

    /// Opens the freshly-saved collage's detail once the grid reload (triggered
    /// by `publishAppCreatedAsset`) has surfaced it (§12). Polls briefly because
    /// the reload is asynchronous and the collage cover is still dismissing.
    private func openSavedPhoto(_ assetID: String) {
        guard let model else { return }
        Task { @MainActor in
            for _ in 0..<25 {
                if let index = model.index(of: assetID) {
                    viewerTarget = PhotoViewerTarget(id: assetID, startIndex: index)
                    return
                }
                try? await Task.sleep(for: .seconds(0.12))
            }
        }
    }

    private func presentVideoStudio(_ model: LibraryModel) {
        let assets = PhotoLibraryService.fetchAssets(ids: selectedIds)
        guard !assets.isEmpty else { return }
        videoStudioPresentation = VideoStudioPresentation(assets: assets, mode: .multiClip)
    }

    private func deleteSelected(_ model: LibraryModel) {
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
    private func comparePhotos(_ model: LibraryModel) -> [ComparePhoto]? {
        guard (2...CompareScreen.maxPhotoCount).contains(selectedIds.count) else { return nil }
        let metadataById = (try? dependencies.libraryQueries.metadata(assetIds: selectedIds)) ?? [:]
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
    private func gridContent(_ model: LibraryModel) -> some View {
        gridBody(model)
            // Banner + tokens ride in the top safe-area inset (not a VStack)
            // so the grid stays the root scroll view: photos scroll under the
            // translucent nav bar chrome edge-to-edge, matching Album Detail.
            .safeAreaInset(edge: .top, spacing: 0) {
                topAccessories(model)
            }
            .onChange(of: navigation.libraryRetapToken) {
            retapResetCount += 1
        }
        // Index-detail dropdown: opened from the toolbar token, drops into the
        // grid's top safe area (just below the nav bar, clear of the toolbar
        // buttons). Full-width, single GlassPanel material.
        .overlay(alignment: .top) {
            if isIndexPanelExpanded,
               model.isIndexing || model.isIndexStreamingPaused || model.indexICloudRetryDate != nil,
               !isSelecting {
                indexDetailPanel(model)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // Reset the expanded state once no index status is active, so a later
        // run doesn't reopen the dropdown.
        .onChange(of: model.isIndexing || model.isIndexStreamingPaused || model.indexICloudRetryDate != nil) { _, active in
            if !active { isIndexPanelExpanded = false }
        }
    }

    @ViewBuilder
    private func gridBody(_ model: LibraryModel) -> some View {
        if model.items.isEmpty {
            ScrollView {
                emptyState(model)
                    .padding(.top, 80)
            }
        } else {
            photoGrid(model)
        }
    }

    /// Limited-access banner + active filter tokens, pinned in the top safe
    /// area above the scrolling grid. Empty (zero height, no inset) when
    /// neither applies.
    @ViewBuilder
    private func topAccessories(_ model: LibraryModel) -> some View {
        VStack(spacing: 0) {
            if photoLibrary.authorizationState == .limited {
                LimitedAccessBanner {
                    photoLibrary.presentLimitedLibraryPicker()
                }
                .padding(.top, 4)
            }

            if let advancedQuery = model.advancedQuery, !advancedQuery.isEmpty {
                AdvancedSearchBar(
                    query: advancedQuery,
                    onEdit: { isAdvancedSearchPresented = true },
                    onRemoveRule: { ruleId in
                        var updated = advancedQuery
                        updated.rules.removeAll { $0.id == ruleId }
                        model.advancedQuery = updated.isEmpty ? nil : updated
                    },
                    onClear: { model.advancedQuery = nil }
                )
            } else if !model.criteria.isEmpty {
                FilterTokenBar(
                    criteria: Binding(
                        get: { model.criteria },
                        set: { model.criteria = $0 }
                    )
                )
            }
        }
    }

    /// Equatable digest of the selection so a single `.onChange` republishes the
    /// root-hosted bar whenever anything it shows changes.
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
    /// action set (Share, Close, Compare, Compress, Collage, Video, Delete, plus
    /// the ⋯ menu) with the selection thumbnail tray.
    private func selectionBarModel() -> SelectionBarModel? {
        guard let model else { return nil }
        return SelectionBarModel(
            selectionCount: selectedIds.count,
            imageSelectionCount: selectedImageIDs(model).count,
            thumbnailIds: selectedIds,
            photoLibrary: photoLibrary,
            isDeleting: isDeleting,
            isPreparingShare: isPreparingShare,
            onShare: shareSelected,
            onClose: { withAnimation { stopSelecting() } },
            onDeselect: { toggleSelection(of: $0) },
            onCollage: { presentCollage(model) },
            onVideo: { presentVideoStudio(model) },
            onCompare: { isComparePresented = true },
            onCompress: { presentCompression(model) },
            onDelete: { deleteSelected(model) },
            onAddToCollection: { addToCollection() },
            onExportEXIF: { exportEXIF(model) },
            onDuplicate: { duplicateSelected() }
        )
    }

    // MARK: ⋯ actions

    /// Opens the album picker for the current selection.
    private func addToCollection() {
        let assets = PhotoLibraryService.fetchAssets(ids: selectedIds)
        guard !assets.isEmpty else { return }
        addToCollectionPresentation = AddToCollectionPresentation(assets: assets)
    }

    /// Exports the selected *images'* indexed EXIF to a CSV and shares it.
    private func exportEXIF(_ model: LibraryModel) {
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

    /// Duplicates the selected assets as new library items.
    private func duplicateSelected() {
        guard !selectedIds.isEmpty, !isDuplicating else { return }
        let assets = PhotoLibraryService.fetchAssets(ids: selectedIds)
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

    private func photoGrid(_ model: LibraryModel) -> some View {
        PhotoGridCollectionView(
            photos: model.items,
            assetProvider: { index, _ in model.asset(atFlatIndex: index) },
            sectionMode: model.sort.isDateSort ? .dates : .flat,
            anchorsBottom: true,
            contentVersion: model.contentGeneration,
            contentRefreshVersion: model.contentRefreshGeneration,
            jumpToNewestToken: retapResetCount,
            columnCount: Binding(
                get: { GridDensity.clamped(storedColumns) },
                set: { storedColumns = $0 }
            ),
            isSelecting: isSelecting,
            selectedIds: selectedIds,
            bottomInset: isSelecting ? navigation.selectionGridInset : bottomChromeInset,
            photoLibrary: photoLibrary,
            onTap: { _, item in
                if isIndexPanelExpanded { setIndexPanelExpanded(false) }
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
            onUserScroll: {
                if isIndexPanelExpanded { setIndexPanelExpanded(false) }
            },
            trailingFooterText: model.hasActiveQuery ? matchCountFooter(model.matchCount) : nil,
            lazyMetadataProvider: { assetId in
                await model.lazyBadgeItem(assetId: assetId)
            }
        )
        // Fill behind the top nav bar too (not just bottom): the collection
        // view's automatic content-inset adjustment + anchor() position items
        // below the bar, so photos scroll under the translucent chrome instead
        // of leaving a black band behind the buttons.
        .ignoresSafeArea()
        .sensoryFeedback(.selection, trigger: selectedIds.count)
    }

    private func matchCountFooter(_ count: Int) -> String {
        "\(count.formatted()) \(count == 1 ? "photo" : "photos")"
    }

    @ViewBuilder
    private func emptyState(_ model: LibraryModel) -> some View {
        if let retryAt = model.indexICloudRetryDate {
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
                Text("\(model.pendingICloudCount) items are waiting. Indexing keeps retrying on its own — cellular or a different network usually helps too.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                HStack(spacing: 12) {
                    Button("Retry Now") {
                        model.retryIncompleteAssets()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Use Cellular") {
                        model.resumeIndexingOverCellular()
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else if model.isIndexing {
            VStack(spacing: 12) {
                if let progress = model.indexProgress, progress.total > 0 {
                    ProgressView(value: progress.fraction)
                        .frame(maxWidth: 220)
                    Text("Reading photo and video info · \(progress.percent)%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("\(progress.processed.formatted()) of \(progress.total.formatted()) photos and videos")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                    Text("Reading photo and video info…")
                        .foregroundStyle(.secondary)
                }
                if let throughput = model.indexThroughput {
                    Text(throughput.summaryLine)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let network = model.indexNetworkStatus {
                    Text(network.displayLine)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let diagnostics = model.indexDiagnostics {
                    ForEach(diagnostics.advisories, id: \.self) { advisory in
                        Label(advisory, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                Text("ShotDex is reading the camera, lens and exposure info from each photo and video. For items kept in iCloud it downloads only the small part of the file holding that info — nothing is saved to this iPhone. The app may feel slow until this finishes.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        } else if model.isIndexStreamingPaused {
            VStack(spacing: 12) {
                Image(systemName: "wifi.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Indexing paused — waiting for Wi-Fi")
                    .foregroundStyle(.secondary)
                Text("\(model.pendingICloudCount) items in iCloud will finish indexing once you're on Wi-Fi. Local metadata was read without using cellular data.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Use Cellular") {
                    model.resumeIndexingOverCellular()
                }
                .buttonStyle(.borderedProminent)
            }
        } else if model.isLoading {
            // The full-library query is async — don't flash "No Photos"
            // while the first load is in flight.
            ProgressView()
        } else if model.hasActiveQuery {
            ContentUnavailableView {
                Label("No photos match these filters.", systemImage: "camera.filters")
            } actions: {
                Button("Clear Filters") {
                    model.criteria = .empty
                    model.advancedQuery = nil
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
    /// Compact status token living in the top-leading toolbar, right of the Settings
    /// gear; a tap opens the detail popover (progress / paused / retry).
    private func indexStatusButton(_ model: LibraryModel) -> some View {
        Button {
            setIndexPanelExpanded(!isIndexPanelExpanded)
        } label: {
            indexStatusLabel(model)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            model.indexProgress.map { "Indexing, \($0.percent) percent" } ?? "Indexing"
        )
        .accessibilityHint("Shows indexing details")
    }

    @ViewBuilder
    private func indexStatusLabel(_ model: LibraryModel) -> some View {
        let content = HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            if let progress = model.indexProgress, progress.total > 0 {
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
            // Pre-26 toolbar buttons are bare — give the token its own capsule
            // so it reads as a distinct control with breathing room.
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .glassBackground(Capsule())
        }
    }

    /// Detail dropdown shown under the toolbar: live progress while indexing,
    /// the countdown card when iCloud isn't responding, or the Wi-Fi-paused
    /// card. One `GlassPanel` material — no nested popover container.
    @ViewBuilder
    private func indexDetailPanel(_ model: LibraryModel) -> some View {
        if model.isIndexing {
            expandedIndexCard(model)
        } else if let retryAt = model.indexICloudRetryDate {
            // Between runs: iCloud couldn't serve, the next automatic
            // attempt is counting down. Indexing never sits dead.
            autoRetryCard(model, retryAt: retryAt)
        } else {
            // Not actively indexing, but iCloud-only photos are waiting on
            // a Wi-Fi connection (metered cellular, not opted in).
            pausedIndexCard(model)
        }
    }

    /// iCloud-not-responding card shown while the automatic retry counts
    /// down: live countdown, skip-the-wait retry, and the cellular shortcut.
    private func autoRetryCard(_ model: LibraryModel, retryAt: Date) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                Label("iCloud not responding", systemImage: "icloud.slash")
                    .font(.caption.weight(.medium))
                HStack(spacing: 4) {
                    Text("Retrying in")
                    Text(timerInterval: Date.now...max(Date.now, retryAt), countsDown: true)
                        .monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                if model.pendingICloudCount > 0 {
                    Text("\(model.pendingICloudCount) items still waiting for iCloud.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 12) {
                    Button("Retry Now") {
                        model.retryIncompleteAssets()
                    }
                    .font(.caption.weight(.medium))
                    Button("Use Cellular") {
                        model.resumeIndexingOverCellular()
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
    private func pausedIndexCard(_ model: LibraryModel) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "Indexing paused — waiting for Wi-Fi",
                    systemImage: "wifi.slash"
                )
                .font(.caption.weight(.medium))
                if model.pendingICloudCount > 0 {
                    Text("\(model.pendingICloudCount) items in iCloud left to read.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Use Cellular") {
                    model.resumeIndexingOverCellular()
                }
                .font(.caption.weight(.medium))
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Indexing paused, waiting for Wi-Fi")
    }

    /// Expanded state (on tap): progress in words and photos, how long it has
    /// left, what it is downloading, anything holding it back, the explainer,
    /// and Cancel. Anchored top-right, width-capped; tapping it or the grid
    /// collapses back to the token.
    ///
    /// "Indexing" stays the feature's name in Settings and on the toolbar
    /// token; the live cards say what it *does* instead, and every number is
    /// labelled — the old card read `Thermal: Fair · 6 readers` and
    /// `iCloud: 4 in flight · 132 requested`, which no photographer can act on.
    private func expandedIndexCard(_ model: LibraryModel) -> some View {
        let progress = model.indexProgress
        return GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    if let progress {
                        Text("Reading photo and video info · \(progress.percent)%")
                            .font(.caption.weight(.medium).monospacedDigit())
                    } else {
                        Text("Reading photo and video info…")
                            .font(.caption.weight(.medium))
                    }
                    Spacer()
                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress?.fraction ?? 0)
                if let progress, progress.total > 0 {
                    Text("\(progress.processed.formatted()) of \(progress.total.formatted()) photos and videos")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let throughput = model.indexThroughput {
                    Text(throughput.summaryLine)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let network = model.indexNetworkStatus {
                    Text(network.displayLine)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Only surfaces when something is actually holding the run
                // back (warm device, Low Power Mode, iCloud not answering).
                if let diagnostics = model.indexDiagnostics {
                    ForEach(diagnostics.advisories, id: \.self) { advisory in
                        Label(advisory, systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("ShotDex is reading the camera, lens and exposure info from each photo and video. For items kept in iCloud it downloads only the small part of the file holding that info — nothing is saved to this iPhone. The app may feel slow until this finishes.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Cancel") {
                    model.cancelIndexing()
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // During selection the nav bar is hidden entirely (all controls live in
        // the floating overlay), so these items only ever render when browsing.
        ToolbarItem(placement: .topBarLeading) {
            SettingsButton()
                .tint(.primary)
        }
        // Break the shared Liquid Glass container so the indexing token reads as
        // its own control, not part of the Settings gear's tap target.
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .topBarLeading)
        }
        ToolbarItem(placement: .topBarLeading) {
            if let model,
               model.isIndexing || model.isIndexStreamingPaused || model.indexICloudRetryDate != nil,
               !isSelecting {
                indexStatusButton(model)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if model != nil, !isSelecting {
                Button {
                    isSelecting = true
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .tint(.primary)
                .accessibilityLabel("Select photos")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if let model, !isSelecting {
                Menu {
                    Picker("Sort", selection: Binding(
                        get: { model.sort },
                        set: { model.sort = $0 }
                    )) {
                        ForEach(SortOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
                .tint(.primary)
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
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    return NavigationStack {
        LibraryScreen(model: LibraryModel(dependencies: dependencies))
    }
    .environment(dependencies)
    .environment(dependencies.photoLibrary)
    .environment(AppNavigation())
}
