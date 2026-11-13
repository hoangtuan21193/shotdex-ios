import SwiftUI

struct HiddenPhotosDestination: Hashable {}

/// Collections › Utilities › Hidden (FS-19.04 §3, board `PH_Hidden`): the
/// photos ShotDex has hidden, with Unhide on the selection bar where the
/// other grids have Delete.
struct HiddenPhotosScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.assetActions) private var assetActions
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss

    @State private var model: HiddenPhotosModel?
    @State private var viewerTarget: PhotoViewerTarget?
    /// Zoom from and back to the tapped tile (FS-02 §8 D5).
    @State private var viewerLink = PhotoViewerLink()
    @State private var isSelecting = false
    @State private var selectedIds: [String] = []
    @State private var swipeBaseline: [String] = []
    @State private var errorMessage: String?

    @AppStorage(SettingsKeys.gridColumns) private var storedColumns = 3

    var body: some View {
        content
            .navigationTitle(isSelecting ? "" : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Always in the principal slot, like an album's title: the
                // plain inline title sat at the leading edge on the Duo's inner
                // display while every other grid centres its own.
                ToolbarItem(placement: .principal) {
                    GridNavigationTitle(title: title, subtitle: isSelecting ? selectedCaption : nil)
                }
                if isSelecting, let selectionModel = selectionBarModel() {
                    SelectionToolbarItems(model: selectionModel)
                } else if model?.items.isEmpty == false {
                    ToolbarItem(placement: .topBarTrailing) {
                        SelectPhotosButton { isSelecting = true }
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
                if model == nil {
                    let newModel = HiddenPhotosModel(dependencies: dependencies)
                    await newModel.load()
                    model = newModel
                }
            }
            .photoViewerCover(item: $viewerTarget, link: viewerLink, onDismiss: reload) { target in
                if let model {
                    PhotoDetailScreen(model: model, currentIndex: target.startIndex)
                }
            }
            .alert(
                String(localized: "Couldn't Unhide Photos", comment: "Hidden section: the flags could not be cleared"),
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sensoryFeedback(.selection, trigger: selectedIds.count)
    }

    private var title: String {
        // Not "0 Hidden Photos" for the moment before the first load.
        guard model?.isLoaded == true else {
            return String(localized: "Hidden", comment: "Utilities row: photos ShotDex has hidden")
        }
        return String(
            localized: "\(model?.items.count ?? 0) Hidden Photos",
            comment: "Hidden section title: how many photos ShotDex has hidden"
        )
    }

    private var selectedCaption: String {
        String(localized: "\(selectedIds.count) selected", comment: "Hidden section subtitle while selecting")
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let model {
            photoGrid(model)
                .safeAreaInset(edge: .top) { explanation }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 80)
        }
    }

    /// What Hidden means here, and what it is not: the files are untouched,
    /// and Photos' own Hidden album is not shown.
    private var explanation: some View {
        Label {
            Text(explanationText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "eye.slash")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.md)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle.app(AppTheme.Radius.md))
        .padding(.horizontal)
        .padding(.bottom, AppTheme.Spacing.sm)
    }

    private var explanationText: String {
        let names = model?.sourceNames.filter { $0 != "Photos" } ?? []
        guard !names.isEmpty else {
            return String(
                localized: "Hidden in ShotDex: out of the library, search, albums and Statistics. The Hidden album of the Photos app is not shown here.",
                comment: "Hidden section explanation, no file or server source"
            )
        }
        let list = names.formatted(.list(type: .and))
        return String(
            localized: "Hidden in ShotDex: out of the library, search, albums and Statistics. The files on \(list) are not changed. The Hidden album of the Photos app is not shown here.",
            comment: "Hidden section explanation; the argument names the sources, e.g. NAS Home"
        )
    }

    private func footer(_ model: HiddenPhotosModel) -> String {
        let count = String(localized: "\(model.items.count) Photos", comment: "Hidden section footer: photo count")
        guard !model.sourceNames.isEmpty else { return count }
        return ([count] + model.sourceNames).joined(separator: " · ")
    }

    private func photoGrid(_ model: HiddenPhotosModel) -> some View {
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
            removal: model.lastRemoval,
            viewerLink: viewerLink
        )
        .ignoresSafeArea(edges: .bottom)
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

    private func unhideSelected() {
        guard let model, !selectedIds.isEmpty else { return }
        do {
            try model.unhide(ids: selectedIds)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        withAnimation { stopSelecting() }
        // The photos are back in the library grid and Statistics.
        dependencies.sources.photosDeleted()
        // Nothing left hidden: the section has nothing to show, and its row
        // leaves Collections.
        if model.items.isEmpty { dismiss() }
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
            onUnhide: { unhideSelected() }
        )
    }
}
