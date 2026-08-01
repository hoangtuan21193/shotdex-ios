import SwiftUI

/// Root container: a ZStack holding one NavigationStack per tab plus the
/// floating glass chrome. Tabs stay alive (and keep their navigation state)
/// when switching, like the system TabView.
struct RootTabView: View {
    @Environment(AppDependencies.self) private var dependencies

    @State private var navigation = AppNavigation()
    @State private var isSearchPresented = false
    @State private var libraryModel: LibraryModel?
    /// Owned here, not by `AlbumsScreen`, so the album snapshot can be built in
    /// the background after Library first paint instead of when the user taps
    /// the tab — enumerating every collection's assets took 300–670ms, which
    /// was dead time on every visit.
    @State private var albumsModel: AlbumsModel?
    /// Pre-iOS 26 keeps a custom ZStack so visited tabs preserve navigation
    /// state, but mounts each tab only on first selection. Hidden, never-visited
    /// Albums/Statistics screens therefore do no PhotoKit/aggregate work during
    /// Library first paint.
    @State private var mountedLegacyTabs: Set<AppTab> = [.library]
    @State private var hasPassedInitialIndexDelay = false
    @State private var hasScheduledAlbumCoverPreheat = false
    /// Albums is the only tab pushed programmatically (a tapped "On This Day"
    /// reminder), so it is the only one that needs a bound path.
    @State private var albumsPath = NavigationPath()

    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(\.scenePhase) private var scenePhase

    /// Starts indexing whenever the library is readable. Lives at the root
    /// (always alive) rather than in `LibraryScreen` — on iOS 26 tab content
    /// is built lazily, so a launch into any other tab would otherwise never
    /// trigger indexing. Idempotent: `startIndexing` guards on `isIndexing`.
    private func autoIndex() {
        guard photoLibrary.authorizationState.canReadLibrary else { return }
        libraryModel?.startIndexing()
    }

    /// Albums is mounted lazily, but its hero should already be sharp — and its
    /// snapshot already built — when the user first opens the tab. Both start
    /// after the launch frame so this PhotoKit work does not delay initial
    /// interaction.
    private func preheatAlbumCoverIfNeeded() {
        guard photoLibrary.authorizationState.canReadLibrary,
              !hasScheduledAlbumCoverPreheat
        else { return }
        hasScheduledAlbumCoverPreheat = true
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await AlbumsModel.preheatOnThisDayCover(using: photoLibrary)
            albumsModel?.load(forAssetToken: photoLibrary.assetChangeToken)
        }
    }

    /// Rebuilds the week of "On This Day" reminders. Safe to call blindly — the
    /// scheduler bails on one `UserDefaults` read when the reminder is off.
    private func refreshOnThisDayNotifications() {
        Task { await dependencies.onThisDayNotifications.refresh() }
    }

    /// Picks up a reminder tapped before this view existed (cold launch straight
    /// from the notification, where the delegate fires while the UI is still
    /// being built and no `.onChange` is installed yet).
    private func drainPendingOnThisDayOpen() {
        guard let date = dependencies.onThisDayNotifications.consumePendingOpenDate() else { return }
        navigation.openOnThisDay(date: date)
    }

    /// Pushes On This Day onto the Albums tab. Replaces the path rather than
    /// appending: a tap while already on the screen for another day must not
    /// stack a second copy.
    private func handleOnThisDayPush() {
        guard let date = navigation.pendingOnThisDayDate else { return }
        albumsPath = NavigationPath([OnThisDayDestination(date: date)])
        navigation.pendingOnThisDayDate = nil
    }

    var body: some View {
        if photoLibrary.authorizationState == .notDetermined {
            OnboardingScreen()
        } else if #available(iOS 26.0, *) {
            nativeTabView
        } else {
            legacyTabView
        }
    }

    /// iOS 26: system TabView with Liquid Glass chrome. The search tab uses
    /// the `.search` role so it renders as the separate pill with a
    /// bottom-anchored search field, like the Music app.
    /// Selection binding that also reports same-tab re-taps (the system
    /// TabView calls the setter on every tab tap). A Library re-tap jumps
    /// the grid to the newest photos. Re-tap also pops the tab's
    /// NavigationStack, but Library never pushes — detail/compare are
    /// fullScreenCovers — so no at-root guard is needed.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { navigation.selectedTab },
            set: { newValue in
                if newValue == .library, navigation.selectedTab == .library {
                    navigation.resetLibraryToRoot()
                }
                navigation.selectedTab = newValue
            }
        )
    }

    /// Mounts a legacy tab before publishing the selection, avoiding a blank
    /// intermediate frame on its first tap.
    private var legacyTabSelection: Binding<AppTab> {
        Binding(
            get: { navigation.selectedTab },
            set: { newValue in
                if newValue != .search {
                    mountedLegacyTabs.insert(newValue)
                }
                navigation.selectedTab = newValue
            }
        )
    }

    @available(iOS 26.0, *)
    private var nativeTabView: some View {
        TabView(selection: tabSelection) {
            Tab(AppTab.library.title, systemImage: AppTab.library.systemImage, value: .library) {
                NavigationStack { LibraryScreen(model: libraryModel) }
            }
            Tab(AppTab.albums.title, systemImage: AppTab.albums.systemImage, value: .albums) {
                NavigationStack(path: $albumsPath) { AlbumsScreen(model: albumsModel) }
            }
            Tab(AppTab.statistics.title, systemImage: AppTab.statistics.systemImage, value: .statistics) {
                NavigationStack { StatisticsScreen() }
            }
            Tab(value: .search, role: .search) {
                NavigationStack {
                    if let libraryModel {
                        SearchTab(
                            model: libraryModel,
                            service: dependencies.searchService,
                            onApply: { navigation.selectedTab = .library },
                            onAdvanced: { navigation.openAdvancedSearch() }
                        )
                    } else {
                        ProgressView()
                    }
                }
            }
        }
        .tabBarMinimizeBehavior(.never)
        // Host the selection controls in the native bottom accessory (the tab bar
        // stays visible and unchanged; it minimizes on scroll and the accessory
        // follows it from expanded to inline placement). See SelectionAccessory.
        .modifier(SelectionBottomAccessory(model: navigation.selectionBar))
        // The selection count floats above the accessory band (out of the glass).
        .overlay(alignment: .bottom) {
            if let model = navigation.selectionBar {
                SelectionCountBanner(model: model)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.25), value: navigation.selectionBar != nil)
        .settingsSheet(isPresented: $navigation.isSettingsSheetPresented, libraryModel: libraryModel)
        .keepScreenAwakeWhileIndexing(libraryModel: libraryModel)
        .environment(navigation)
        .task {
            if libraryModel == nil {
                libraryModel = LibraryModel(dependencies: dependencies)
            }
            if albumsModel == nil {
                albumsModel = AlbumsModel(dependencies: dependencies)
            }
            preheatAlbumCoverIfNeeded()
            drainPendingOnThisDayOpen()
            // Let the Library publish its first interactive frame before the
            // full PhotoKit/index reconciliation starts competing for I/O.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            hasPassedInitialIndexDelay = true
            if scenePhase == .active {
                autoIndex()
                refreshOnThisDayNotifications()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, hasPassedInitialIndexDelay else { return }
            autoIndex()
            refreshOnThisDayNotifications()
        }
        .onChange(of: navigation.pendingLibraryFilter) { _, pending in
            guard let pending else { return }
            libraryModel?.criteria = pending
            navigation.pendingLibraryFilter = nil
        }
        .onChange(of: dependencies.onThisDayNotifications.pendingOpenDate) {
            drainPendingOnThisDayOpen()
        }
        .onChange(of: navigation.onThisDayToken) {
            handleOnThisDayPush()
        }
    }

    private var legacyTabView: some View {
        // Pre-26 has no native tab bar. The custom floating tab bar stays a
        // bottom overlay (its clearance handled by each grid's `bottomChromeInset`,
        // unchanged). During selection it hides and the selection bar takes over a
        // root-level `.safeAreaInset` — real safe area, so grids auto-clear it and
        // only add a small selection pad. One static layout matching the iOS 26
        // expanded form; no inline emulation.
        tabContent
            .overlay(alignment: .bottom) {
                if navigation.selectionBar == nil {
                    LiquidGlassTabBar(
                        selection: legacyTabSelection,
                        onReselect: { tab in
                            if tab == .library {
                                navigation.resetLibraryToRoot()
                            }
                        },
                        onSearchTap: {
                            navigation.selectedTab = .library
                            isSearchPresented = true
                        }
                    )
                    .padding(.bottom, 8)
                    .transition(.opacity)
                } else {
                    // Scrim lives here (root overlay) — not as the bar's own
                    // background — so it ignores the safe area and paints all the
                    // way to the physical bottom edge, covering the home-indicator
                    // strip below the bar (else that strip renders white pre-26).
                    BottomScrim()
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let model = navigation.selectionBar {
                    SelectionBottomBar(model)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
            }
            .animation(.snappy(duration: 0.25), value: navigation.selectionBar != nil)
            .settingsSheet(isPresented: $navigation.isSettingsSheetPresented, libraryModel: libraryModel)
            .keepScreenAwakeWhileIndexing(libraryModel: libraryModel)
            .environment(navigation)
            .task {
                if libraryModel == nil {
                    libraryModel = LibraryModel(dependencies: dependencies)
                }
                if albumsModel == nil {
                    albumsModel = AlbumsModel(dependencies: dependencies)
                }
                preheatAlbumCoverIfNeeded()
                drainPendingOnThisDayOpen()
                // Let the Library publish its first interactive frame before
                // the full PhotoKit/index reconciliation starts competing.
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                hasPassedInitialIndexDelay = true
                if scenePhase == .active {
                    autoIndex()
                    refreshOnThisDayNotifications()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, hasPassedInitialIndexDelay else { return }
                autoIndex()
                refreshOnThisDayNotifications()
            }
            .onChange(of: navigation.pendingLibraryFilter) { _, pending in
                guard let pending else { return }
                libraryModel?.criteria = pending
                navigation.pendingLibraryFilter = nil
            }
            .onChange(of: dependencies.onThisDayNotifications.pendingOpenDate) {
                drainPendingOnThisDayOpen()
            }
            .onChange(of: navigation.onThisDayToken) {
                handleOnThisDayPush()
            }
            .onChange(of: navigation.selectedTab) { _, tab in
                guard tab != .search else { return }
                mountedLegacyTabs.insert(tab)
            }
            .sheet(isPresented: $isSearchPresented) {
                if let libraryModel {
                    SearchSheet(
                        model: libraryModel,
                        service: dependencies.searchService
                    ) {
                        isSearchPresented = false
                        navigation.openAdvancedSearch()
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
    }

    private var tabContent: some View {
        ZStack {
            if mountedLegacyTabs.contains(.library) {
                tabStack(.library) { LibraryScreen(model: libraryModel) }
            }
            if mountedLegacyTabs.contains(.albums) {
                tabStack(.albums, path: $albumsPath) { AlbumsScreen(model: albumsModel) }
            }
            if mountedLegacyTabs.contains(.statistics) {
                tabStack(.statistics) { StatisticsScreen() }
            }
        }
    }

    /// `path` is supplied only for tabs that are pushed programmatically. Which
    /// branch a call site takes is static, so view identity stays stable.
    @ViewBuilder
    private func tabStack<Content: View>(
        _ tab: AppTab,
        path: Binding<NavigationPath>? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Group {
            if let path {
                NavigationStack(path: path) { content() }
            } else {
                NavigationStack { content() }
            }
        }
        .opacity(navigation.selectedTab == tab ? 1 : 0)
        .allowsHitTesting(navigation.selectedTab == tab)
        .accessibilityHidden(navigation.selectedTab != tab)
    }
}

/// Keeps the screen awake — and auto-dims on idle — while indexing runs, gated
/// on the `index.keepScreenAwake` setting. Mounts an invisible touch probe only
/// when active so it never interferes otherwise.
private struct KeepScreenAwakeModifier: ViewModifier {
    let libraryModel: LibraryModel?

    @AppStorage(SettingsKeys.keepScreenAwake) private var keepScreenAwake = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = ScreenAwakeCoordinator()

    private var isIndexing: Bool {
        libraryModel?.isIndexing == true
    }
    private var isLowPowerMode: Bool {
        libraryModel?.isLowPowerMode == true
    }
    private var isManualRun: Bool {
        libraryModel?.isManualIndexRun == true
    }
    /// In Low Power Mode only a manually started run keeps the screen awake;
    /// automatic runs let the display sleep normally.
    private var isActive: Bool {
        keepScreenAwake && isIndexing && (!isLowPowerMode || isManualRun)
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    // Passive, non-blocking probe that resets the idle timer
                    // on any touch. The dim visuals live in a top-level window
                    // (see ScreenAwakeCoordinator), so nothing is drawn here.
                    IdleActivityReporterView { model.registerActivity() }
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: keepScreenAwake) { sync() }
            .onChange(of: isIndexing) { sync() }
            .onChange(of: isLowPowerMode) { sync() }
            .onChange(of: isManualRun) { sync() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    sync()
                } else {
                    model.handleBackground()
                }
            }
    }

    private func sync() {
        model.libraryModel = libraryModel
        model.update(enabled: isActive, indexing: isIndexing)
    }
}

extension View {
    /// Keep the display awake and auto-dim on idle while `libraryModel` is
    /// indexing, honoring the user's `index.keepScreenAwake` setting.
    func keepScreenAwakeWhileIndexing(libraryModel: LibraryModel?) -> some View {
        modifier(KeepScreenAwakeModifier(libraryModel: libraryModel))
    }
}

/// Hosts the multi-select controls in the iOS 26 tab-bar bottom accessory. The
/// accessory content is always supplied (stable identity) and toggled via
/// `isEnabled:` — the intended API for showing/hiding it without leaving an empty
/// accessory band. `isEnabled:` is iOS 26.1+; on 26.0 it falls back to
/// conditional content.
@available(iOS 26.0, *)
private struct SelectionBottomAccessory: ViewModifier {
    let model: SelectionBarModel?

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: model != nil) {
                if let model { SelectionAccessory(model) }
            }
        } else {
            content.tabViewBottomAccessory {
                if let model { SelectionAccessory(model) }
            }
        }
    }
}

/// Focuses the search field where the API exists (iOS 18+). Before that,
/// presenting the field is what raises the keyboard and there is nothing to add.
private struct SearchFieldFocus: ViewModifier {
    var isFocused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.searchFocused(isFocused)
        } else {
            content
        }
    }
}

/// iOS 26 search tab content: the `.search`-role tab anchors the search
/// field to the bottom edge (Music-app style). Applying a query jumps to
/// the Library tab with the search criteria set.
@available(iOS 26.0, *)
struct SearchTab: View {
    @Environment(AppNavigation.self) private var navigation

    let model: LibraryModel
    let service: SearchService
    var onApply: () -> Void
    /// Opens the advanced-search sheet. Presented by the root tab view (not here):
    /// a `.sheet` attached inside a `.search`-role tab's searchable scope is
    /// swallowed and never appears.
    var onAdvanced: () -> Void

    @State private var query = ""
    /// Presents the field. Without it the tab opens with the field idle and the
    /// first tap does nothing but focus it — the search screen appears not to work.
    @State private var isFieldActive = false
    /// Raises the keyboard. Presentation alone leaves a field with a caret and no
    /// keyboard, which is the same complaint from the user's side.
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        SearchSuggestionsScreen(
            query: $query,
            model: model,
            service: service,
            onApplied: onApply,
            // Advanced Search sits inside the search field, so the title row does not
            // repeat it. On this tier that costs a ghost copy of the icon in the
            // status-bar strip — a deliberate trade, see SearchFieldTrailingButton.
            onAdvanced: nil
        )
        .searchFieldTrailingButton(
            systemImage: "slider.horizontal.3",
            accessibilityLabel: "Advanced Search",
            action: onAdvanced
        )
        // Attached beside `.searchable`, not inside the content: the keyboard's
        // Search key is delivered to the view that owns the search field, and a
        // submit that reaches nothing is how a search box comes to feel broken.
        .searchable(
            text: $query,
            isPresented: $isFieldActive,
            prompt: SearchSuggestionsScreen.prompt
        )
        .searchFocused($isFieldFocused)
        .onSubmit(of: .search) {
            model.applySearch(query, using: service)
            onApply()
        }
        // No toolbar item for Advanced Search here, and no `navigationTitle`: the
        // `.search`-role tab owns the whole bottom row — the slot left of the field
        // is the system's return-to-previous-tab button, a plain `.bottomBar` item
        // lands *behind* the field, and moving the field into the bottom bar with
        // `DefaultToolbarItem` breaks its layout (the typed text draws outside the
        // pill). iOS 26 also hides the navigation title while the field is active.
        // So the screen draws its own title row and puts Advanced Search on it.
        .onAppear { isFieldActive = true }
        // The tab is not rebuilt when it is selected again and the field stays
        // presented, so `onAppear` alone leaves the second visit with a field that
        // looks active but has no keyboard — the "I have to tap the field again"
        // complaint. Presenting raises the keyboard by itself; only a field that is
        // already presented needs focus put back on it.
        .onChange(of: navigation.selectedTab) { _, tab in
            guard tab == .search else { return }
            // Leaving the tab empties the field on screen without writing the
            // binding, so the old text would still be what the Search key submits.
            query = ""
            if isFieldActive {
                isFieldFocused = true
            } else {
                isFieldActive = true
            }
        }
    }
}

/// Search sheet: query DSL search over the indexed metadata with
/// autosuggest from known camera and lens names.
struct SearchSheet: View {
    @Environment(\.dismiss) private var dismiss

    let model: LibraryModel
    let service: SearchService
    /// Dismisses this sheet and opens advanced search on the Library tab.
    var onAdvanced: () -> Void
    @State private var query = ""
    /// Opens the field — and the keyboard — as the sheet appears.
    @State private var isFieldActive = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack {
            SearchSuggestionsScreen(
                query: $query,
                model: model,
                service: service,
                onApplied: { dismiss() },
                onAdvanced: nil
            )
            .searchFieldTrailingButton(
                systemImage: "slider.horizontal.3",
                accessibilityLabel: "Advanced Search",
                action: onAdvanced
            )
            .searchable(
                text: $query,
                isPresented: $isFieldActive,
                prompt: SearchSuggestionsScreen.prompt
            )
            .modifier(SearchFieldFocus(isFocused: $isFieldFocused))
            .onSubmit(of: .search) {
                model.applySearch(query, using: service)
                dismiss()
            }
            // No title, and no Advanced Search item: an active search field takes
            // over this whole bar on this tier, so anything put here is gone exactly
            // when the user is searching. The screen draws its own title row with
            // Advanced Search on it; Cancel comes from the field itself. The bar
            // stays (hiding it would hide the field with it) and holds Done for when
            // the field is not active.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                isFieldActive = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    isFieldFocused = true
                }
            }
        }
    }
}

#Preview {
    RootTabView()
        .environment(AppDependencies.preview())
        .environment(AppDependencies.preview().photoLibrary)
}
