import SwiftUI

struct OnThisIPhoneDestination: Hashable {}

/// Utilities › On This iPhone (board `PH_OnThisIPhone`): everything kept for
/// offline use, from every source. On top, the room it takes and what is
/// still coming down; then the albums kept as a whole; then every kept photo
/// and video. Remove from iPhone deletes the kept copies — never the photos.
/// Named "On This iPhone", not "Offline": "Offline" already means a source
/// that is not connected.
struct OnThisIPhoneScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.assetActions) private var assetActions
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(AppNavigation.self) private var navigation

    @State private var model: OnThisIPhoneModel?
    @State private var viewerTarget: PhotoViewerTarget?
    @State private var isSelecting = false
    @State private var selectedIds: [String] = []
    @State private var swipeBaseline: [String] = []
    @State private var isConfirmingRemoveAll = false
    @State private var removingAlbum: KeptAlbum?

    @AppStorage(SettingsKeys.gridColumns) private var storedColumns = 3

    private var runner: KeepRunner { dependencies.keepRunner }

    var body: some View {
        content
            .navigationTitle(isSelecting ? "" : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if isSelecting {
                        GridNavigationTitle(title: title, subtitle: String(localized: "\(selectedIds.count) selected", comment: "On This iPhone subtitle while selecting"))
                    }
                }
                if isSelecting, let selectionModel = selectionBarModel() {
                    SelectionToolbarItems(model: selectionModel)
                } else {
                    ToolbarItem(placement: .topBarTrailing) { moreMenu }
                    if model?.items.isEmpty == false {
                        ToolbarItem(placement: .topBarTrailing) {
                            SelectPhotosButton { isSelecting = true }
                        }
                    }
                }
            }
            .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
            .disablesBackSwipe(isSelecting)
            .navigationBarBackButtonHidden(isSelecting)
            .onChange(of: isSelecting) { navigation.hidesTabBar = isSelecting }
            .onChange(of: selectedIds) {
                navigation.selectionBar = isSelecting ? selectionBarModel() : nil
            }
            .onChange(of: isSelecting) {
                navigation.selectionBar = isSelecting ? selectionBarModel() : nil
            }
            .onDisappear {
                navigation.hidesTabBar = false
                if isSelecting { navigation.selectionBar = nil }
            }
            .task {
                runner.refreshAlbums()
                if model == nil { model = OnThisIPhoneModel(dependencies: dependencies) }
            }
            // Every finished download, removal and failure.
            .task(id: runner.revision) { await model?.load() }
            .fullScreenCover(item: $viewerTarget, onDismiss: reload) { target in
                if let model {
                    PhotoDetailScreen(model: model, currentIndex: target.startIndex)
                }
            }
            .confirmationDialog(
                String(localized: "Remove everything from this \(KeepDevice.name)?", comment: "On This iPhone: confirm Remove All"),
                isPresented: $isConfirmingRemoveAll,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Remove All from \(KeepDevice.name)", comment: "On This iPhone: delete every kept copy"), role: .destructive) {
                    runner.removeAll()
                }
            } message: {
                Text("The kept copies are deleted. The photos stay in your library and open again when you are online.",
                     comment: "On This iPhone: what Remove All does")
            }
            .confirmationDialog(
                String(localized: "Stop keeping “\(removingAlbum?.title ?? "")”?", comment: "On This iPhone: confirm removing a kept album"),
                isPresented: Binding(get: { removingAlbum != nil }, set: { if !$0 { removingAlbum = nil } }),
                titleVisibility: .visible,
                presenting: removingAlbum
            ) { album in
                Button(String(localized: "Remove from \(KeepDevice.name)", comment: "On This iPhone: delete the kept copies of an album"), role: .destructive) {
                    runner.removeAlbum(id: album.id)
                }
            }
            .sensoryFeedback(.selection, trigger: selectedIds.count)
    }

    private var title: String {
        String(localized: "On This \(KeepDevice.name)", comment: "Title of the screen listing photos kept for offline use")
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let model, model.isLoaded {
            if model.items.isEmpty && model.waitingCount == 0 && model.failed.isEmpty && model.albums.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "Nothing Kept Yet", comment: "On This iPhone empty state title"), systemImage: "arrow.down.circle")
                } description: {
                    Text("Select photos or open an album, then choose Keep on This \(KeepDevice.name) in the ⋯ menu. They open here without a connection.",
                         comment: "On This iPhone empty state: how to keep photos")
                }
            } else {
                photoGrid(model)
                    .safeAreaInset(edge: .top) { header(model) }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 80)
        }
    }

    private func header(_ model: OnThisIPhoneModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            OnThisIPhoneStatusCard(
                keptBytes: model.keptBytes,
                waiting: model.waitingCount,
                failed: model.failed.count,
                progress: runner.progress,
                isPaused: runner.isPaused,
                onPause: { runner.setPaused(!runner.isPaused) },
                onRetry: { model.failed.forEach { runner.retry(id: $0.id) } }
            )
            .padding(.horizontal)
            if !model.albums.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(model.albums) { album in
                            albumChip(album, progress: model.albumProgress[album.id])
                        }
                    }
                    .padding(.horizontal)
                }
                .scrollClipDisabled()
            }
        }
        .padding(.bottom, AppTheme.Spacing.sm)
    }

    /// A kept album: its name, how much of it is here, and whether it keeps
    /// photos added later. The menu changes that or removes the album.
    private func albumChip(_ album: KeptAlbum, progress: (onDevice: Int, total: Int)?) -> some View {
        let done = progress?.onDevice ?? 0
        let total = progress?.total ?? 0
        let detail = done < total
            ? String(localized: "\(done) of \(total)", comment: "Kept album chip: how many of its photos are here")
            : String(localized: "\(total) items", comment: "Kept album chip: item count")
        return Menu {
            Toggle(String(localized: "Keep New Photos Added Later", comment: "Kept album menu toggle"), isOn: Binding(
                get: { album.keepsNewPhotos },
                set: { newValue in
                    var updated = album
                    updated.keepsNewPhotos = newValue
                    try? dependencies.kept.save(updated)
                    runner.refreshAlbums()
                    reload()
                }
            ))
            Button(role: .destructive) {
                removingAlbum = album
            } label: {
                Label(String(localized: "Remove from \(KeepDevice.name)", comment: "Kept album menu: delete its kept copies"), systemImage: "minus.circle")
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: album.keepsNewPhotos ? "arrow.down.circle" : "checkmark.circle")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(album.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(.label))
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(minHeight: 52)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle.app(AppTheme.Radius.lg))
        }
        .accessibilityLabel(album.keepsNewPhotos
            ? String(localized: "\(album.title), \(detail), keeps new photos", comment: "VoiceOver: a kept album chip")
            : String(localized: "\(album.title), \(detail)", comment: "VoiceOver: a kept album chip"))
    }

    private var moreMenu: some View {
        Menu {
            if runner.pendingCount > 0 || runner.isPaused {
                Button {
                    runner.setPaused(!runner.isPaused)
                } label: {
                    Label(runner.isPaused
                          ? String(localized: "Resume Downloads", comment: "On This iPhone menu")
                          : String(localized: "Pause Downloads", comment: "On This iPhone menu"),
                          systemImage: runner.isPaused ? "play" : "pause")
                }
            }
            Button(role: .destructive) {
                isConfirmingRemoveAll = true
            } label: {
                Label(String(localized: "Remove All from \(KeepDevice.name)…", comment: "On This iPhone menu: delete every kept copy"), systemImage: "trash")
            }
            .disabled(model?.isLoaded != true || (model?.items.isEmpty == true && model?.albums.isEmpty == true && runner.pendingCount == 0))
        } label: {
            Image(systemName: "ellipsis")
        }
        .tint(.primary)
        .accessibilityLabel(String(localized: "More", comment: "On This iPhone: the ⋯ menu"))
    }

    private func photoGrid(_ model: OnThisIPhoneModel) -> some View {
        PhotoGridCollectionView(
            photos: model.items,
            assetProvider: { index, _ in model.asset(atFlatIndex: index) },
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
            bottomInset: isSelecting ? navigation.selectionGridInset : AppTheme.Size.bottomChromeClearance,
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
            trailingFooterText: footer(model),
            removal: model.lastRemoval
        )
        .ignoresSafeArea(edges: .bottom)
    }

    private func footer(_ model: OnThisIPhoneModel) -> String {
        [
            model.keptPhotoCount > 0 ? String(localized: "\(model.keptPhotoCount) photos", comment: "On This iPhone footer: kept photo count") : nil,
            model.keptVideoCount > 0 ? String(localized: "\(model.keptVideoCount) videos", comment: "On This iPhone footer: kept video count") : nil,
            KeepOnIPhoneSheet.format(model.keptBytes),
        ].compactMap { $0 }.joined(separator: " · ")
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

    private func stopSelecting() {
        isSelecting = false
        selectedIds = []
        swipeBaseline = []
    }

    private func removeSelected() {
        let ids = selectedIds
        runner.remove(ids: ids)
        model?.dropped(Set(ids))
        withAnimation { stopSelecting() }
    }

    private func reload() {
        guard let model else { return }
        Task { await model.load() }
    }

    private func selectionBarModel() -> SelectionBarModel? {
        guard model != nil else { return nil }
        let actions = assetActions ?? dependencies.assetActions
        return SelectionBarModel(
            selectionCount: selectedIds.count,
            selectedIds: selectedIds,
            photoLibrary: photoLibrary,
            libraryQueries: dependencies.libraryQueries,
            onShare: { [selectedIds] in actions.share(ids: selectedIds) },
            onClose: { withAnimation { stopSelecting() } },
            onDeselect: { toggleSelection(of: $0) },
            onDeselectAll: { selectedIds = [] },
            onDelete: {},
            onRemoveFromDevice: { removeSelected() },
            onSelectAll: { selectedIds = model?.items.map(\.assetId) ?? [] }
        )
    }
}

/// The card at the top: room the kept copies take next to what is free, and
/// — while anything is coming down — how much is left, with Pause.
private struct OnThisIPhoneStatusCard: View {
    let keptBytes: Int64
    let waiting: Int
    let failed: Int
    let progress: Double?
    let isPaused: Bool
    let onPause: () -> Void
    let onRetry: () -> Void

    @State private var space: (free: Int64, total: Int64)?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "\(KeepOnIPhoneSheet.format(keptBytes)) kept", comment: "On This iPhone: bytes the kept copies take"))
                    .font(.headline.monospacedDigit())
                Spacer(minLength: AppTheme.Spacing.sm)
                if let space {
                    Text(String(localized: "\(KeepOnIPhoneSheet.format(space.free)) free on \(KeepDevice.name)", comment: "On This iPhone: free space on the device"))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let space, space.total > 0 {
                GeometryReader { geometry in
                    let used = Double(space.total - space.free) / Double(space.total)
                    let kept = Double(keptBytes) / Double(space.total)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.tertiarySystemFill))
                        Capsule().fill(Color(.systemGray3)).frame(width: geometry.size.width * used)
                        Capsule().fill(Color.accentColor).frame(width: max(4, geometry.size.width * kept))
                    }
                }
                .frame(height: 8)
                .accessibilityHidden(true)
            }
            if waiting > 0 {
                HStack(spacing: AppTheme.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isPaused
                             ? String(localized: "Paused · \(waiting) waiting", comment: "On This iPhone: downloads paused")
                             : String(localized: "Downloading · \(waiting) left", comment: "On This iPhone: downloads running"))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                        if let progress, !isPaused {
                            ProgressView(value: progress)
                        } else if !isPaused {
                            ProgressView(value: nil as Double?)
                                .progressViewStyle(.linear)
                        }
                    }
                    Button(action: onPause) {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .frame(width: 44, height: 44)
                    }
                    .tint(.primary)
                    .accessibilityLabel(isPaused
                        ? String(localized: "Resume Downloads", comment: "On This iPhone menu")
                        : String(localized: "Pause Downloads", comment: "On This iPhone menu"))
                }
            }
            if failed > 0 {
                HStack {
                    Label(String(localized: "\(failed) could not download", comment: "On This iPhone: failed keeps"),
                          systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(String(localized: "Retry", comment: "On This iPhone: try the failed downloads again"), action: onRetry)
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle.app(AppTheme.Radius.lg))
        .task { space = Self.readSpace() }
    }

    private static func readSpace() -> (free: Int64, total: Int64)? {
        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        guard let free = values?.volumeAvailableCapacityForImportantUsage, let total = values?.volumeTotalCapacity else { return nil }
        return (free, Int64(total))
    }
}
