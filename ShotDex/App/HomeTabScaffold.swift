import SwiftUI

/// Root scaffold: a ZStack holding one NavigationStack per tab plus the
/// floating glass chrome. Tabs stay alive (and keep their navigation state)
/// when switching, like the system TabView.
struct HomeTabScaffold: View {
    @Environment(AppDependencies.self) private var dependencies

    @State private var navigation = AppNavigation()
    @State private var isSearchPresented = false
    @State private var libraryController: LibraryController?
    /// Pre-iOS 26 keeps a custom ZStack so visited tabs preserve navigation
    /// state, but mounts each tab only on first selection. Hidden, never-visited
    /// Albums/Statistics screens therefore do no PhotoKit/aggregate work during
    /// Library first paint.
    @State private var mountedLegacyTabs: Set<AppTab> = [.library]
    @State private var hasPassedInitialIndexDelay = false

    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(\.scenePhase) private var scenePhase

    /// Starts indexing whenever the library is readable. Lives at the root
    /// (always alive) rather than in `LibraryScreen` — on iOS 26 tab content
    /// is built lazily, so a launch into any other tab would otherwise never
    /// trigger indexing. Idempotent: `startIndexing` guards on `isIndexing`.
    private func autoIndex() {
        guard photoLibrary.authorizationState.canReadLibrary else { return }
        libraryController?.startIndexing()
    }

    var body: some View {
        if photoLibrary.authorizationState == .notDetermined {
            OnboardingScreen()
        } else if #available(iOS 26.0, *) {
            nativeScaffold
        } else {
            mainScaffold
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
                    navigation.retapLibrary()
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
    private var nativeScaffold: some View {
        TabView(selection: tabSelection) {
            Tab(AppTab.library.title, systemImage: AppTab.library.systemImage, value: .library) {
                NavigationStack { LibraryScreen(controller: libraryController) }
            }
            Tab(AppTab.albums.title, systemImage: AppTab.albums.systemImage, value: .albums) {
                NavigationStack { AlbumsScreen() }
            }
            Tab(AppTab.statistics.title, systemImage: AppTab.statistics.systemImage, value: .statistics) {
                NavigationStack { StatisticsScreen() }
            }
            Tab(value: .search, role: .search) {
                NavigationStack {
                    if let libraryController {
                        SearchTab(
                            controller: libraryController,
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
        .modifier(SelectionBottomAccessory(config: navigation.selectionBar))
        // The selection count floats above the accessory band (out of the glass).
        .overlay(alignment: .bottom) {
            if let config = navigation.selectionBar {
                SelectionCountBanner(config: config)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.25), value: navigation.selectionBar != nil)
        .settingsDrawer(isOpen: $navigation.isSettingsDrawerOpen, libraryController: libraryController)
        .keepScreenAwakeWhileIndexing(libraryController: libraryController)
        .environment(navigation)
        .task {
            if libraryController == nil {
                libraryController = LibraryController(dependencies: dependencies)
            }
            // Let the Library publish its first interactive frame before the
            // full PhotoKit/index reconciliation starts competing for I/O.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            hasPassedInitialIndexDelay = true
            if scenePhase == .active { autoIndex() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, hasPassedInitialIndexDelay { autoIndex() }
        }
        .onChange(of: navigation.pendingLibraryFilter) { _, pending in
            guard let pending else { return }
            libraryController?.criteria = pending
            navigation.pendingLibraryFilter = nil
        }
    }

    private var mainScaffold: some View {
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
                                navigation.retapLibrary()
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
                if let config = navigation.selectionBar {
                    SelectionBottomBar(config)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
            }
            .animation(.snappy(duration: 0.25), value: navigation.selectionBar != nil)
            .settingsDrawer(isOpen: $navigation.isSettingsDrawerOpen, libraryController: libraryController)
            .keepScreenAwakeWhileIndexing(libraryController: libraryController)
            .environment(navigation)
            .task {
                if libraryController == nil {
                    libraryController = LibraryController(dependencies: dependencies)
                }
                // Let the Library publish its first interactive frame before
                // the full PhotoKit/index reconciliation starts competing.
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                hasPassedInitialIndexDelay = true
                if scenePhase == .active { autoIndex() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, hasPassedInitialIndexDelay { autoIndex() }
            }
            .onChange(of: navigation.pendingLibraryFilter) { _, pending in
                guard let pending else { return }
                libraryController?.criteria = pending
                navigation.pendingLibraryFilter = nil
            }
            .onChange(of: navigation.selectedTab) { _, tab in
                guard tab != .search else { return }
                mountedLegacyTabs.insert(tab)
            }
            .sheet(isPresented: $isSearchPresented) {
                if let libraryController {
                    SearchSheet(controller: libraryController) {
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
                tabStack(.library) { LibraryScreen(controller: libraryController) }
            }
            if mountedLegacyTabs.contains(.albums) {
                tabStack(.albums) { AlbumsScreen() }
            }
            if mountedLegacyTabs.contains(.statistics) {
                tabStack(.statistics) { StatisticsScreen() }
            }
        }
    }

    @ViewBuilder
    private func tabStack<Content: View>(
        _ tab: AppTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            content()
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
    let libraryController: LibraryController?

    @AppStorage(SettingsKeys.keepScreenAwake) private var keepScreenAwake = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller = ScreenAwakeController()

    private var isIndexing: Bool {
        libraryController?.isIndexing == true
    }
    private var isLowPowerMode: Bool {
        libraryController?.isLowPowerMode == true
    }
    private var isManualRun: Bool {
        libraryController?.isManualIndexRun == true
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
                    // (see ScreenAwakeController), so nothing is drawn here.
                    IdleActivityDetector { controller.registerActivity() }
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
                    controller.handleBackground()
                }
            }
    }

    private func sync() {
        controller.libraryController = libraryController
        controller.update(enabled: isActive, indexing: isIndexing)
    }
}

extension View {
    /// Keep the display awake and auto-dim on idle while `libraryController` is
    /// indexing, honoring the user's `index.keepScreenAwake` setting.
    func keepScreenAwakeWhileIndexing(libraryController: LibraryController?) -> some View {
        modifier(KeepScreenAwakeModifier(libraryController: libraryController))
    }
}

/// Hosts the multi-select controls in the iOS 26 tab-bar bottom accessory. The
/// accessory content is always supplied (stable identity) and toggled via
/// `isEnabled:` — the intended API for showing/hiding it without leaving an empty
/// accessory band. `isEnabled:` is iOS 26.1+; on 26.0 it falls back to
/// conditional content.
@available(iOS 26.0, *)
private struct SelectionBottomAccessory: ViewModifier {
    let config: SelectionBarConfig?

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: config != nil) {
                if let config { SelectionAccessory(config) }
            }
        } else {
            content.tabViewBottomAccessory {
                if let config { SelectionAccessory(config) }
            }
        }
    }
}

/// iOS 26 search tab content: the `.search`-role tab anchors the search
/// field to the bottom edge (Music-app style). Applying a query jumps to
/// the Library tab with the search criteria set.
@available(iOS 26.0, *)
struct SearchTab: View {
    let controller: LibraryController
    var onApply: () -> Void
    /// Opens the advanced-search sheet. Presented by the scaffold (not here):
    /// a `.sheet` attached inside a `.search`-role tab's searchable scope is
    /// swallowed and never appears.
    var onAdvanced: () -> Void

    @State private var query = ""

    var body: some View {
        List {
            Section {
                Button {
                    onAdvanced()
                } label: {
                    Label("Advanced Search", systemImage: "slider.horizontal.3")
                }
            }
            if query.isEmpty {
                Section {
                    Text("Search by filename, camera, lens, focal length, ISO, aperture or shutter speed.")
                        .foregroundStyle(.secondary)
                    Text("Examples: IMG_1234 · Canon R6 · RF 100-500 · 85mm · ISO 3200 · f/1.8 · 1/500")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Button {
                        apply(query)
                    } label: {
                        Label("Search for “\(query)”", systemImage: "magnifyingglass")
                    }
                    ForEach(controller.suggestions(for: query), id: \.self) { suggestion in
                        Button {
                            apply(suggestion)
                        } label: {
                            Label(suggestion, systemImage: "camera")
                                .foregroundStyle(Color(.label))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: "Canon R6, 85mm, ISO 3200…")
        .onSubmit(of: .search) { apply(query) }
        .navigationTitle("Search")
        .onAppear {
            query = controller.criteria.searchText ?? ""
            controller.refreshFilterOptions()
        }
    }

    private func apply(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        controller.criteria.searchText = trimmed.isEmpty ? nil : trimmed
        onApply()
    }
}

/// Search sheet: query DSL search over the indexed metadata with
/// autosuggest from known camera and lens names.
struct SearchSheet: View {
    @Environment(\.dismiss) private var dismiss

    let controller: LibraryController
    /// Dismisses this sheet and opens advanced search on the Library tab.
    var onAdvanced: () -> Void
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onAdvanced()
                    } label: {
                        Label("Advanced Search", systemImage: "slider.horizontal.3")
                    }
                }
                if query.isEmpty {
                    Section {
                        Text("Search by filename, camera, lens, focal length, ISO, aperture or shutter speed.")
                            .foregroundStyle(.secondary)
                        Text("Examples: IMG_1234 · Canon R6 · RF 100-500 · 85mm · ISO 3200 · f/1.8 · 1/500")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Button {
                            apply(query)
                        } label: {
                            Label("Search for “\(query)”", systemImage: "magnifyingglass")
                        }
                        ForEach(controller.suggestions(for: query), id: \.self) { suggestion in
                            Button {
                                apply(suggestion)
                            } label: {
                                Label(suggestion, systemImage: "camera")
                                    .foregroundStyle(Color(.label))
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Canon R6, 85mm, ISO 3200…")
            .onSubmit(of: .search) { apply(query) }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            query = controller.criteria.searchText ?? ""
            controller.refreshFilterOptions()
        }
    }

    private func apply(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        controller.criteria.searchText = trimmed.isEmpty ? nil : trimmed
        dismiss()
    }
}

#Preview {
    HomeTabScaffold()
        .environment(AppDependencies.preview())
        .environment(AppDependencies.preview().photoLibrary)
}
