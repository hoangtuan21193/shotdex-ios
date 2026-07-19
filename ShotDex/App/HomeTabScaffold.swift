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
                        SearchTab(controller: libraryController) {
                            navigation.selectedTab = .library
                        }
                    } else {
                        ProgressView()
                    }
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .settingsDrawer(isOpen: $navigation.isSettingsDrawerOpen, libraryController: libraryController)
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
        }
        .settingsDrawer(isOpen: $navigation.isSettingsDrawerOpen, libraryController: libraryController)
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
                SearchSheet(controller: libraryController)
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

/// iOS 26 search tab content: the `.search`-role tab anchors the search
/// field to the bottom edge (Music-app style). Applying a query jumps to
/// the Library tab with the search criteria set.
@available(iOS 26.0, *)
struct SearchTab: View {
    let controller: LibraryController
    var onApply: () -> Void

    @State private var query = ""

    var body: some View {
        List {
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
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
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
