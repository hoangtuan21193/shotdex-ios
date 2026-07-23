import SwiftUI

/// Root scaffold: a ZStack holding one NavigationStack per tab plus the
/// floating glass chrome. Tabs stay alive (and keep their navigation state)
/// when switching, like the system TabView.
struct HomeTabScaffold: View {
    @Environment(AppDependencies.self) private var dependencies

    @State private var navigation = AppNavigation()
    @State private var isSearchPresented = false
    @State private var libraryController: LibraryController?

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
        .tabBarMinimizeBehavior(.onScrollDown)
        .settingsDrawer(isOpen: $navigation.isSettingsDrawerOpen, libraryController: libraryController)
        .keepScreenAwakeWhileIndexing(libraryController: libraryController)
        .environment(navigation)
        .task {
            if libraryController == nil {
                libraryController = LibraryController(dependencies: dependencies)
            }
            autoIndex()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { autoIndex() }
        }
        .onChange(of: navigation.pendingLibraryFilter) { _, pending in
            guard let pending else { return }
            libraryController?.criteria = pending
            navigation.pendingLibraryFilter = nil
        }
    }

    private var mainScaffold: some View {
        ZStack(alignment: .bottom) {
            tabContent

            if !navigation.hidesTabBar {
                LiquidGlassTabBar(
                    selection: $navigation.selectedTab,
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
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: navigation.hidesTabBar)
        .settingsDrawer(isOpen: $navigation.isSettingsDrawerOpen, libraryController: libraryController)
        .keepScreenAwakeWhileIndexing(libraryController: libraryController)
        .environment(navigation)
        .task {
            if libraryController == nil {
                libraryController = LibraryController(dependencies: dependencies)
            }
            autoIndex()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { autoIndex() }
        }
        .onChange(of: navigation.pendingLibraryFilter) { _, pending in
            guard let pending else { return }
            libraryController?.criteria = pending
            navigation.pendingLibraryFilter = nil
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
            tabStack(.library) { LibraryScreen(controller: libraryController) }
            tabStack(.albums) { AlbumsScreen() }
            tabStack(.statistics) { StatisticsScreen() }
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
