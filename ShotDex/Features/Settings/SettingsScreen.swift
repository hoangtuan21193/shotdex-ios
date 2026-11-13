import ShotDexKit
import SwiftUI

/// Settings content, hosted in a bottom sheet: photo library /
/// index controls, display options, camera database, statistics options,
/// privacy.
struct SettingsScreen: View {
    /// Shorthand for the row labels, which every section reads from.
    private typealias Row = SettingsRowLabel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.isDuoInner) private var isDuoInner
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppNavigation.self) private var appNavigation

    let libraryModel: LibraryModel?

    @AppStorage(SettingsKeys.autoplayVideos) private var autoplayVideos = true
    @AppStorage(SettingsKeys.viewFullHDR) private var viewFullHDR = false
    @AppStorage(SettingsKeys.shareMetadataLevel) private var shareMetadataLevel = MetadataLevel.all
    /// Add a Source, from Add Folder or Drive… or Grant Access….
    @State private var isAddingSource = false
    /// The source Remove Source… asks about.
    @State private var removingSource: SourcesModel.Row?
    @State private var storage: LibraryQueries.StorageTotals?
    @AppStorage("display.showISO") private var showsISO = true
    @AppStorage("display.showAperture") private var showsAperture = true
    @AppStorage("display.showShutter") private var showsShutter = false
    @AppStorage("display.showFocal") private var showsFocal = true
    @AppStorage("display.showMegapixels") private var showsMegapixels = false
    @AppStorage("display.showFileSize") private var showsFileSize = false
    @AppStorage(SettingsKeys.showFileTypeBadge) private var showsFileTypeBadge = true
    @AppStorage("display.focalStyleEquivalent") private var showsEquivalentFocalLength = false
    @AppStorage(SettingsKeys.allowCellularIndexing) private var allowCellularIndexing = false
    @AppStorage(SettingsKeys.showsInsights) private var showsInsights = true
    @AppStorage(SettingsKeys.keepScreenAwakeMode) private var keepScreenAwakeMode = KeepScreenAwake.stored.rawValue
    @AppStorage(SettingsKeys.lookUpPlaces) private var looksUpPlaces = true
    @AppStorage(SettingsKeys.sharesIndex) private var sharesIndex = true
    /// Pulled from iCloud: a Mac on this account indexes for every device.
    @AppStorage(SettingsKeys.macIndexesForAll) private var macIndexesForAll = false
    @AppStorage(SettingsKeys.macIndexesForAllName) private var macIndexesForAllName = ""
    @AppStorage(SettingsKeys.ignoresMacIndex) private var ignoresMacIndex = false
    @AppStorage(SettingsKeys.onThisDayNotificationsEnabled) private var isOnThisDayReminderEnabled = false
    /// Minutes since local midnight. The default matches the scheduler's, which
    /// has to spell it out separately because `UserDefaults.integer` cannot tell
    /// an unwritten key from midnight.
    @AppStorage(SettingsKeys.onThisDayNotifyMinutes) private var onThisDayNotifyMinutes =
        OnThisDayNotificationSchedule.defaultNotifyMinutes

    /// Rows whose EXIF read has finished — the numerator of "how far along is
    /// indexing", never the row count (see `MetadataStore.rowCount`).
    @State private var readCount = 0
    /// Every asset the index knows about, read or not: the denominator.
    @State private var totalCount = 0
    /// Rows whose read hasn't finished for **any** reason — `pendingRead`
    /// placeholders included. The denominator of "is there anything left to
    /// do", and what the Continue action offers to finish.
    @State private var unfinishedCount = 0
    @State private var lastIndexedAt: Date?
    /// The library split by kind, for the "Your library" card. Read from the
    /// index rather than `LibraryModel.items`, which is the grid's *filtered*
    /// list — a search left in Library would shrink the card's count.
    @State private var photoCount = 0
    @State private var videoCount = 0
    /// Value-line facts that cost a query, read off the main actor when
    /// Settings opens and whenever the root list comes back on screen — the
    /// screens they summarise are pushed from it and can change them.
    @State private var unknownCameraCount = 0
    @State private var fileServerNames: [String] = []
    @State private var isClearIndexConfirmationPresented = false
    @State private var isResetMappingsConfirmationPresented = false
    @State private var isClearScanConfirmationPresented = false
    @State private var notificationAuthorization: NotificationAuthorizationState = .notDetermined
    /// Debounces the reminder-time picker: `.hourAndMinute` publishes on every
    /// detent, and each refresh is seven queries plus seven scheduling calls, so
    /// one scroll would otherwise trigger dozens of full reschedules.
    @State private var notifyTimeRefreshTask: Task<Void, Never>?

    /// Where the reader is: the selected sidebar item, what the compact layout
    /// has pushed, the search query and the row a result is sending them to.
    /// Created here, so closing Settings forgets all four.
    @State private var navigation = SettingsNavigation()
    /// The sidebar stays out while a detail screen is pushed — a bound value
    /// rather than a constant, which SwiftUI resolves into an update loop.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        // Split in three so the type-checker can keep up: the container, its
        // lifecycle modifiers, then the three destructive alerts.
        lifecycleBody
            .destructiveAlerts(
                clearIndex: $isClearIndexConfirmationPresented,
                resetMappings: $isResetMappingsConfirmationPresented,
                clearScan: $isClearScanConfirmationPresented,
                onClearIndex: {
                    try? dependencies.metadataStore.deleteAll()
                    libraryModel?.reload()
                    Task { await refreshIndexInfo() }
                },
                onResetMappings: { try? dependencies.metadataStore.deleteAllCustomMappings() },
                onClearScan: { dependencies.subjectScan.clear() }
            )
    }

    /// Everything that has to outlive a pane.
    ///
    /// All of it sits **above** the container branch, not inside a pane, and
    /// each one has a reason: the three alerts fire from two different panes;
    /// the index counts are three `COUNT(*)` over the whole library and would
    /// otherwise re-run on every sidebar tap while going stale on the panes the
    /// reader is not looking at; the reminder toggle rolls itself back when
    /// permission is refused, and a cancelled pane would leave a preference
    /// stored that can never fire; the time picker's debounce would be cancelled
    /// the same way.
    private var lifecycleBody: some View {
        layoutRoot
            .environment(navigation)
            // Above the panes: a sheet hung on a list section is torn down
            // with the row that presented it.
            .sheet(isPresented: $isAddingSource) {
                AddSourceSheet()
                    .environment(dependencies)
            }
            .removeSourceAlert($removingSource, dependencies: dependencies)
            .task(id: libraryModel?.isIndexing) {
                await refreshIndexInfo()
                // A finished run changes the unknown cameras and what the
                // people scan has left to look at.
                await refreshSummaries()
            }
            .task {
                // Opened from another tab to a row: land on it like a search result.
                if let row = appNavigation.consumePendingSettingsRow() {
                    navigation.open(SettingsSearchIndex.entry(for: row), usesSplitView: usesSplitView)
                }
                notificationAuthorization = await dependencies.onThisDayNotifications.authorizationState()
            }
            .task { await refreshSummaries() }
            .onChange(of: isOnThisDayReminderEnabled) { _, isEnabled in
                Task { await applyReminderToggle(isEnabled) }
            }
            .onChange(of: onThisDayNotifyMinutes) {
                notifyTimeRefreshTask?.cancel()
                notifyTimeRefreshTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    await dependencies.onThisDayNotifications.refresh()
                }
            }
            .onChange(of: usesSplitView) { _, isSplit in
                navigation.layoutChanged(usesSplitView: isSplit)
            }
    }

    /// Which container Settings is: a sidebar and a detail pane at regular
    /// width, the single list everywhere else (`DESIGN.md` §10.1f).
    ///
    /// No animation or transition wraps this branch on purpose. Animating a
    /// swap of navigation containers is the shape of the preference-loop crash
    /// this screen has hit twice; if the swap ever needs taming, the answer is
    /// to remove animation from it, not to add some.
    @ViewBuilder
    private var layoutRoot: some View {
        if usesSplitView { splitLayout } else { compactLayout }
    }

    private var usesSplitView: Bool {
        SettingsLayout.usesSplitView(horizontalSizeClass: horizontalSizeClass)
    }

    // MARK: Compact — the root list of items, each pushing its page

    private var compactLayout: some View {
        @Bindable var navigation = navigation
        return NavigationStack(path: $navigation.compactPath) {
            settingsOrResults { compactRoot }
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.large)
                .settingsSubtitle(Self.subtitle)
                .toolbar { doneToolbarItem }
                .navigationDestination(for: SettingsDestination.self) { destination in
                    destinationRoot(for: destination)
                        .toolbar { doneToolbarItem }
                }
                .searchable(
                    text: $navigation.query,
                    isPresented: $navigation.isSearchPresented,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Search Settings")
                )
        }
    }

    /// The phone's root (FS-08.01b §1): the library card, then the four
    /// headings of item rows, each saying its own value — no switch lives
    /// here, every one is a tap away on its item's page.
    private var compactRoot: some View {
        List {
            if #unavailable(iOS 26.0) {
                legacySubtitleRow
            }
            Section {
                rootLibraryCard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            ForEach(SettingsCategory.allCases) { category in
                Section {
                    ForEach(category.destinations) { destination in
                        NavigationLink(value: destination) {
                            SettingsTileRowLabel(
                                title: String(localized: destination.title),
                                value: summary(for: destination),
                                systemImage: destination.systemImage,
                                tint: destination.tint
                            )
                        }
                        .settingsRowInsets()
                        .accessibilityIdentifier("settings.root.\(destination.rawValue)")
                    }
                } header: {
                    SettingsSectionHeader(category.title)
                }
            }
            Section {
                rootFooter
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .onAppear { Task { await refreshSummaries() } }
    }

    /// One row of the root, opened.
    @ViewBuilder
    private func destinationRoot(for destination: SettingsDestination) -> some View {
        switch destination {
        case .resizePresets:
            CompressionPresetsScreen()
        case .fileServers:
            FileServerListScreen()
        case .support:
            supportScreen
        case .ai:
            SettingsAIScreen()
        default:
            groupedList(destination.groups)
                .navigationTitle(destination.title)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// The version, and where the things that are not settings live.
    private var rootFooter: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Text(Self.versionLine)
                .frame(maxWidth: .infinity)
            Text("Albums and smart albums are in Collections; charts and gear statistics are in Collections › Utilities › Statistics. Pinch the photo grid to change how many columns it shows.", comment: "Settings root footer: where the things that are not settings live")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, AppTheme.Spacing.xs)
    }

    /// Before iOS 26 a navigation bar has no subtitle, so the line opens the
    /// list instead.
    private var legacySubtitleRow: some View {
        Self.subtitle
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .listRowInsets(EdgeInsets(top: 0, leading: AppTheme.Spacing.xs, bottom: 0, trailing: AppTheme.Spacing.xs))
            .listRowBackground(Color.clear)
    }

    private static let subtitle = Text(
        "How ShotDex reads, shows and shares your photos",
        comment: "Settings: the line under the large title, saying what the screen is for"
    )

    private static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return String(localized: "ShotDex \(version) (\(build))", comment: "Settings root footer: app version and build number")
    }

    // MARK: Regular — sidebar and detail

    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            // A stack per pane, keyed to the item. Keyed so a pushed screen
            // cannot survive into another item's pane; a real stack because
            // Save in the sensor mapping screen pops with `dismiss()` — with no
            // stack here it would close Settings — and because the widget
            // designs screen declares a `navigationDestination` that needs one.
            NavigationStack {
                detailRoot(for: navigation.selection ?? .photoLibrary)
            }
            .id(navigation.selection ?? .photoLibrary)
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// The sidebar.
    ///
    /// The `List` is the **direct** child of the split view's sidebar column,
    /// and search swaps the rows inside it rather than replacing the list.
    /// Measured on an iPad: wrapped in a conditional, the same list stopped
    /// selecting — a tap on an item did nothing at all, because SwiftUI only
    /// gives a sidebar's own list the single-tap selection behaviour.
    private var sidebar: some View {
        @Bindable var navigation = navigation
        return List(selection: $navigation.selection) {
            if navigation.isSearching {
                searchResultRows
            } else {
                if #unavailable(iOS 26.0) {
                    legacySubtitleRow
                }
                // The same four headings as the phone's root, drawn as gaps:
                // a heading over two rows in a 320pt column is more label
                // than list.
                ForEach(SettingsCategory.allCases) { category in
                    Section {
                        ForEach(category.sections) { item in
                            sidebarRow(item)
                                // "Support" is a sidebar item, a pane title and a
                                // row on the phone's list all at once, so the
                                // driver cannot pick this one out by label.
                                .accessibilityIdentifier("settings.sidebar.\(item.rawValue)")
                                .tag(item)
                        }
                    }
                }
            }
        }
        // 44pt rows (FS-08.01b §2); the sidebar style's own default is taller.
        .environment(\.defaultMinListRowHeight, AppTheme.Size.minTouch)
        .overlay {
            if navigation.isSearching, SettingsSearchIndex.results(for: navigation.query).isEmpty {
                ContentUnavailableView.search(text: navigation.query)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        // The Duo's inner display is too short for a large title: the bar
        // goes inline, and the line squeezed between the title, Done and
        // the sidebar button ended "How ShotDex reads, s…".
        .settingsSubtitle(isDuoInner ? nil : Self.subtitle)
        .navigationSplitViewColumnWidth(
            min: AppTheme.Size.settingsSidebarWidthMin,
            ideal: AppTheme.Size.settingsSidebarWidth,
            max: AppTheme.Size.settingsSidebarWidthMax
        )
        .toolbar { doneToolbarItem }
        .searchable(
            text: $navigation.query,
            isPresented: $navigation.isSearchPresented,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("Search Settings")
        )
        .task { await refreshSummaries() }
    }

    /// A 44pt sidebar row: 28pt tile, title, and the short form of the value
    /// at the trailing edge (FS-08.01b §2) — "76%", "6 unknown", "9:00 AM".
    private func sidebarRow(_ item: SettingsSection) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // The tile keeps its colour on the selected row: iOS 26 draws the
            // selection as a grey capsule with tinted text, and a white tile on
            // grey disappears.
            SettingsTileIcon(
                systemImage: item.systemImage,
                tint: item.tint,
                isCompact: true
            )
            Text(item.title)
                .lineLimit(1)
            Spacer(minLength: AppTheme.Spacing.sm)
            if let value = shortSummary(for: item) {
                Text(value)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: AppTheme.Size.minTouch)
        .listRowInsets(EdgeInsets(
            top: 0, leading: AppTheme.Spacing.sm, bottom: 0, trailing: AppTheme.Spacing.md
        ))
        .accessibilityElement(children: .combine)
    }

    /// One sidebar item's content.
    ///
    /// Support is the one item that is a whole screen rather than a group of
    /// sections: its threads are the point, and putting them behind one more
    /// row would be a pane whose only content is a link.
    @ViewBuilder
    private func detailRoot(for item: SettingsSection) -> some View {
        switch item {
        case .support:
            supportScreen
        case .ai:
            SettingsAIScreen()
        default:
            groupedList(item.groups)
                .navigationTitle(item.title)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var supportScreen: some View {
        SupportScreen(
            service: dependencies.support,
            metadataStore: dependencies.metadataStore
        )
    }

    // MARK: Shared pieces

    /// Results as rows of the sidebar's own list, so the list keeps being the
    /// sidebar's list — see the note on `sidebar`.
    @ViewBuilder
    private var searchResultRows: some View {
        ForEach(SettingsSearchIndex.results(for: navigation.query)) { entry in
            SettingsSearchResultRow(entry: entry) {
                navigation.open(entry, usesSplitView: usesSplitView)
            }
        }
    }

    /// The settings themselves, or the search results when something is typed.
    @ViewBuilder
    private func settingsOrResults(@ViewBuilder content: () -> some View) -> some View {
        if navigation.isSearching {
            SettingsSearchResultsList(query: navigation.query) { entry in
                navigation.open(entry, usesSplitView: usesSplitView)
            }
        } else {
            content()
        }
    }

    /// A page of sections, able to be sent to one of its rows by a search result.
    ///
    /// A page holding one group drops that group's header: the navigation
    /// title already says it, and "Notifications" over "Notifications" is
    /// the same word twice.
    private func groupedList(_ groups: [SettingsGroup]) -> some View {
        let showsHeaders = groups.count > 1
        return ScrollViewReader { proxy in
            List {
                ForEach(groups) { group($0, showsHeader: showsHeaders) }
            }
            .listStyle(.insetGrouped)
            // Held to a readable width and centred, with the grouped grey put
            // back behind the whole pane. Measured on a 13" iPad: a row left to
            // fill the pane is 1006pt across and stands "Access" 900pt from
            // "Full Access" — the phone layout stretched, which §10.1c forbids.
            // Settings on iPadOS holds the same content to 844pt.
            .scrollContentBackground(.hidden)
            .frame(maxWidth: AppTheme.Size.settingsDetailContentMaxWidth)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
            .task(id: navigation.pendingScrollTarget) {
                await revealPendingRow(in: groups, proxy: proxy)
            }
        }
    }

    /// Scrolls to the row a search result asked for and lights it up briefly.
    ///
    /// The row is claimed only by the list that actually draws it — in the split
    /// view the other panes do not exist yet, but two lists must not both
    /// answer for the same target.
    private func revealPendingRow(in groups: [SettingsGroup], proxy: ScrollViewProxy) async {
        guard let target = navigation.pendingScrollTarget, groups.contains(target.group) else { return }
        _ = navigation.consumeScrollTarget()
        withAnimation(AppTheme.Motion.standard) {
            proxy.scrollTo(target.scrollAnchor, anchor: .center)
        }
        navigation.flash(target)
    }

    /// A full screen has no swipe to dismiss at all, so Done is the only way out
    /// and has to be there. (It was already required as a sheet: the drag
    /// indicator was easy to miss on iPad.)
    @ToolbarContentBuilder
    private var doneToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
        }
    }

    // MARK: The fourteen sections, addressed by name

    /// One `Section`, picked by its case.
    ///
    /// Both layouts render their sections through here, so the phone's pages
    /// and an iPad detail pane are drawing the same views off the same state —
    /// this screen keeps owning every `@AppStorage` and `@State` it always had.
    /// No `AnyView`: erasing the type would blur the row identity `List`
    /// animates against, which is the diff bug `indexControls` documents below.
    @ViewBuilder
    private func group(_ group: SettingsGroup, showsHeader: Bool) -> some View {
        switch group {
        case .sources: sourcesSection
        case .photoLibrary: photoLibrarySection(showsHeader: showsHeader)
        case .notifications: notificationsSection(showsHeader: showsHeader)
        case .widgets: widgetsSection(showsHeader: showsHeader)
        case .display: displaySection(showsHeader: showsHeader)
        case .statistics: statisticsSection(showsHeader: showsHeader)
        case .playback: playbackSection(showsHeader: showsHeader)
        case .ai: aiSection
        case .subjectScan: subjectScanSection(showsHeader: showsHeader)
        case .libraryStorage: storageSection(showsHeader: showsHeader)
        case .sharing: sharingSection(showsHeader: showsHeader)
        case .export: exportSection(showsHeader: showsHeader)
        case .fileServers: fileServersSection(showsHeader: showsHeader)
        case .cameraDatabase: cameraDatabaseSection(showsHeader: showsHeader)
        case .support: supportSection
        case .privacy: privacySection(showsHeader: showsHeader)
        }
    }

    // MARK: Row building

    /// A row's tile, title and value line, from its `SettingsRowLabel`.
    private func rowLabel(
        _ row: Row,
        value: String? = nil,
        title: String? = nil,
        style: SettingsTileRowLabel.TitleStyle = .standard
    ) -> SettingsTileRowLabel {
        SettingsTileRowLabel(
            title: title ?? row.title,
            value: value,
            systemImage: row.systemImage,
            tint: row.tint,
            titleStyle: style,
            valueLineLimit: 2
        )
    }

    /// A row that only reads out: tile, title, value line, and a number at
    /// the trailing edge. Not `LabeledContent`, which drops its value under
    /// the label once a two-line label leaves it short of room — measured on
    /// the phone, "13.1 MB" fell to a line of its own.
    private func valueRow(_ row: Row, value: String? = nil, trailing: String? = nil) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            rowLabel(row, value: value)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .monospacedDigit()
                    .foregroundStyle(Color(.secondaryLabel))
                    // Pinned: a greedy label must not push the number off the row.
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "On · …" / "Off · …" — a switch's state, then what that state means.
    /// The Mac that indexes for every device, as its own Settings named it.
    private var macName: String {
        macIndexesForAllName.isEmpty ? String(localized: "Your Mac", comment: "Settings: a Mac whose name is unknown") : macIndexesForAllName
    }

    private func toggleValue(_ isOn: Bool, on: String, off: String) -> String {
        isOn
            ? SettingsSummary.joined(String(localized: "On", comment: "Settings: a switch that is on, at the start of its value line"), on)
            : SettingsSummary.joined(String(localized: "Off", comment: "Settings: a switch that is off, at the start of its value line"), off)
    }

    // MARK: Sources

    /// Every source, then the two ways to add one (FS-19.01 §1, board
    /// `PH_SettingsSources`).
    private var sourcesSection: some View {
        Section {
            ForEach(dependencies.sources.rows) { row in
                SourceRowView(row: row)
                    .settingsRowInsets()
                    .sourceRemoval(row) { removingSource = row }
            }
            Button { isAddingSource = true } label: {
                rowLabel(.addFolderOrDrive, style: .action)
            }
            .settingsRow(.addFolderOrDrive)
            NavigationLink {
                FileServerListScreen()
            } label: {
                rowLabel(.connectToServer, style: .action)
            }
            .settingsRow(.connectToServer)
        } footer: {
            Text("Folders, drives and servers are indexed in place. ShotDex never edits file contents; ratings and keywords go to .xmp sidecars.",
                 comment: "Settings → Sources: footer under the list of sources")
        }
        .onAppear { dependencies.sources.load() }
    }

    // MARK: Photo Library

    /// The library card, then access and the indexing switches. The card is
    /// where Indexed Photos and Videos, Last Indexed and Re-index live now —
    /// one status in one place (FS-08.01b §1), the row labels kept so search
    /// still lands on it.
    @ViewBuilder
    private func photoLibrarySection(showsHeader: Bool) -> some View {
        Section {
            pageLibraryCard
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
        Section {
            valueRow(.access, value: SettingsSummary.accessDetail(photoLibrary.authorizationState))
                .settingsRow(.access)
            if photoLibrary.authorizationState == .limited {
                Button {
                    photoLibrary.presentLimitedLibraryPicker()
                } label: {
                    rowLabel(.manageSelectedPhotos, style: .action)
                }
                .settingsRow(.manageSelectedPhotos)
            }
            if photoLibrary.authorizationState == .denied {
                Button { openAppSettings() } label: {
                    rowLabel(.openPhotoSettings, style: .action)
                }
                .settingsRow(.openPhotoSettings)
            }

            if let model = libraryModel {
                indexControls(model)
            }

            Toggle(isOn: $allowCellularIndexing) {
                rowLabel(.useCellularData, value: toggleValue(
                    allowCellularIndexing,
                    on: String(localized: "a few hundred KB per photo", comment: "Settings, Use Cellular Data value line when on"),
                    off: String(localized: "Wi-Fi is always allowed", comment: "Settings, Use Cellular Data value line when off")
                ))
            }
            .settingsRow(.useCellularData)
            Picker(selection: $keepScreenAwakeMode) {
                ForEach(KeepScreenAwake.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            } label: {
                rowLabel(.keepScreenAwake, value: (KeepScreenAwake(rawValue: keepScreenAwakeMode) ?? .off).detail)
            }
            .pickerStyle(.menu)
            .settingsRow(.keepScreenAwake)
            Toggle(isOn: $looksUpPlaces) {
                rowLabel(.lookUpPlaceNames, value: toggleValue(
                    looksUpPlaces,
                    on: String(localized: "asks Apple Maps once per place", comment: "Settings, Look Up Place Names value line when on"),
                    off: String(localized: "places stay as coordinates", comment: "Settings, Look Up Place Names value line when off")
                ))
            }
            .settingsRow(.lookUpPlaceNames)
            Toggle(isOn: $sharesIndex) {
                rowLabel(.shareIndexAcrossDevices, value: toggleValue(
                    sharesIndex,
                    on: String(localized: "your devices read each photo once, through iCloud", comment: "Settings, Share Index Across Devices value line when on"),
                    off: String(localized: "this device reads every photo itself", comment: "Settings, Share Index Across Devices value line when off")
                ))
            }
            .settingsRow(.shareIndexAcrossDevices)
            // Only while a Mac indexes for every device (its own Settings):
            // the one way to keep reading iCloud photos here anyway.
            if sharesIndex && macIndexesForAll {
                Toggle(isOn: $ignoresMacIndex) {
                    rowLabel(.indexOnThisDevice, value: ignoresMacIndex
                        ? String(localized: "On · reads photos in iCloud too", comment: "Settings, Index on This Device value line when on")
                        : String(localized: "Off · \(macName) indexes photos in iCloud for this device", comment: "Settings, Index on This Device value line when off; the argument is the Mac's name"))
                }
                .settingsRow(.indexOnThisDevice)
            }
        } header: {
            if showsHeader {
                SettingsSectionHeader(LocalizedStringResource("Access and indexing", comment: "Settings → Photo Library: section header"))
            }
        } footer: {
            Text("Indexing reads the camera, lens and exposure info out of each photo and video. In Low Power Mode automatic indexing pauses. Place names are looked up once per place, then remembered. Shared index results go to your own iCloud account only.", comment: "Settings → Photo Library: footer under the indexing switches")
        }
    }

    /// The library status, read from the same counts the Photo Library page
    /// always showed.
    private var libraryStatus: SettingsLibraryStatus {
        let progress = libraryModel?.indexProgress
        return SettingsLibraryStatus(.init(
            access: photoLibrary.authorizationState,
            photoCount: photoCount,
            videoCount: videoCount,
            readCount: readCount,
            totalCount: totalCount,
            isIndexing: libraryModel?.isIndexing ?? false,
            runFraction: progress.flatMap { $0.total > 0 ? $0.fraction : nil },
            lastIndexedAt: lastIndexedAt
        ))
    }

    private var canReindex: Bool {
        guard let libraryModel else { return false }
        return photoLibrary.authorizationState.canReadLibrary && !libraryModel.isIndexing
    }

    private func reindex() {
        libraryModel?.startIndexing(fullReindex: true, manual: true)
    }

    /// The root's card: the status only. Everything about a run in progress
    /// is one tap away on the Photo Library page.
    private var rootLibraryCard: some View {
        SettingsLibraryCard(status: libraryStatus, canReindex: canReindex, reindex: reindex)
            .accessibilityIdentifier("settings.libraryCard")
    }

    /// The page's card, which a search for "indexed", "last indexed" or
    /// "re-index" lands on — so it carries those rows' scroll id and flash.
    private var pageLibraryCard: some View {
        let isFlashing = navigation.flashedRow.map { $0.scrollAnchor == .indexedPhotosAndVideos } ?? false
        return SettingsLibraryCard(status: libraryStatus, canReindex: canReindex, reindex: reindex) {
            if let model = libraryModel, model.isIndexing {
                indexRunDetails(model)
            }
        }
        .overlay {
            RoundedRectangle.app(AppTheme.Radius.lg)
                .fill(Color.accentColor.opacity(isFlashing ? 0.18 : 0))
                .allowsHitTesting(false)
        }
        .animation(AppTheme.Motion.standard, value: isFlashing)
        .id(Row.indexedPhotosAndVideos)
        .accessibilityIdentifier(
            isFlashing ? "settings.libraryCard.flashing" : "settings.libraryCard"
        )
    }

    /// The index actions that are rows — Continue Indexing — disabled while a
    /// run is going. Re-index is the card's button.
    ///
    /// "Continue Indexing" is keyed to `unfinishedCount`, not the retryable
    /// (`pendingICloud`/`error`) count: a run stopped part-way leaves its
    /// remainder at `pendingRead`, so the retryable count was 0 and the only
    /// offer left was Re-index Library — throwing away tens of thousands of
    /// finished reads to redo work that just needed picking back up. The model
    /// still picks the cheaper targeted retry when every unread row is one it
    /// can serve.
    ///
    /// The row stays put while a run goes instead of disappearing: `List`
    /// animates a change in its row set, so a tap would slide the page around
    /// instead of acknowledging the tap. Disabling it is also the feedback the
    /// tap needs — it greys out on the same frame (a manual run sets
    /// `isIndexing` synchronously), and a disabled row can't be hammered into
    /// starting the run twice.
    @ViewBuilder
    private func indexControls(_ model: LibraryModel) -> some View {
        if photoLibrary.authorizationState.canReadLibrary, unfinishedCount > 0 {
            // The count rides inside the localized string, not appended to
            // it: "Continue Indexing (%@)" is one phrase to translate, and
            // splitting it would leave the brackets to English word order.
            Button {
                model.continueIndexing()
            } label: {
                rowLabel(
                    .continueIndexing,
                    value: String(localized: "Picks up where the last run stopped", comment: "Settings, Continue Indexing value line"),
                    title: String(localized: "Continue Indexing (\(unfinishedCount.formatted()))"),
                    style: .action
                )
            }
            .disabled(model.isIndexing)
            .settingsRow(.continueIndexing)
        }
    }

    /// What a run in progress is doing, under the card's bar on the Photo
    /// Library page: counts, speed, network, warnings, and Cancel.
    private func indexRunDetails(_ model: LibraryModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            if let progress = model.indexProgress, progress.total > 0 {
                Text("\(progress.processed.formatted()) of \(progress.total.formatted()) photos and videos")
            }
            if let throughput = model.indexThroughput {
                Text(throughput.summaryLine)
            }
            if let network = model.indexNetworkStatus {
                Text(network.displayLine)
            }
            if let diagnostics = model.indexDiagnostics {
                ForEach(diagnostics.advisories, id: \.self) { advisory in
                    Label(advisory, systemImage: "exclamationmark.triangle")
                }
            }
            Text(Self.explainer)
            Button("Cancel") { model.cancelIndexing() }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
                .padding(.top, AppTheme.Spacing.xs)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.top, AppTheme.Spacing.sm)
        // A state readout, not a transition.
        .transaction { $0.animation = nil }
    }

    private func sharingSection(showsHeader: Bool) -> some View {
        Section {
            Picker(selection: $shareMetadataLevel) {
                ForEach(MetadataLevel.allCases, id: \.self) { level in
                    Text(level.title).tag(level)
                }
            } label: {
                rowLabel(.metadataWhenSharing, value: String(localized: "Each share can change it", comment: "Settings, Metadata When Sharing value line"))
            }
            .settingsRow(.metadataWhenSharing)
            watermarkWhenSharingPicker {
                rowLabel(.watermarkWhenSharing, value: WatermarkCopy.sharingValueLine())
            }
        } header: {
            if showsHeader {
                SettingsSectionHeader(LocalizedStringResource("Sharing", comment: "Settings: section header over Metadata When Sharing"))
            }
        } footer: {
            Text("What goes with a photo when it leaves ShotDex: Share, Save Copy, Paste Edits, Resize and dragging it into another app. Each of them can choose differently for one time. No Location removes where it was taken; camera, lens, exposure and date still go with it. No Metadata keeps only what the picture needs to look right, and the Artist and Copyright.\n\nVideos always keep their metadata: removing it would mean copying the whole clip.")
        }
    }

    /// Settings → Watermark When Sharing (FS-05.04 §4): Off or a saved
    /// preset, stamped on every share and drag; each share can change it for
    /// one time.
    private func watermarkWhenSharingPicker<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        Picker(selection: Binding(
            get: { dependencies.watermarkSettings.sharingPresetID },
            set: { dependencies.watermarkSettings.setSharingPreset($0) }
        )) {
            Text(WatermarkCopy.off()).tag(UUID?.none)
            ForEach(dependencies.signaturePresets.presets) { preset in
                Text(preset.name).tag(UUID?.some(preset.id))
            }
        } label: {
            label()
        }
        .settingsRow(.watermarkWhenSharing)
    }

    // MARK: People and pets

    /// The opt-in Vision pass, and the only bulk image decode in the app.
    ///
    /// It lives behind a button rather than running with indexing on purpose:
    /// indexing reads EXIF headers, this reads whole photos, and the user
    /// should be the one who decides to pay for that. What it produces is
    /// deliberately modest — "has a person in it", "has a cat or dog in it" —
    /// because Vision publishes no face-identity request, so no app can tell
    /// one person from another or name them.
    @ViewBuilder
    private func subjectScanSection(showsHeader: Bool) -> some View {
        @Bindable var scan = dependencies.subjectScan
        Section {
            valueRow(.scanned, trailing: subjectScanCountLabel)
                .settingsRow(.scanned)

            if scan.isScanning {
                subjectScanProgressRow(scan)
                    .transaction { $0.animation = nil }
            } else {
                Button {
                    scan.start()
                } label: {
                    rowLabel(scan.isComplete ? .scanAgain : .findPeopleAndPets, style: .action)
                }
                .disabled(!photoLibrary.authorizationState.canReadLibrary)
                .settingsRow(scan.isComplete ? .scanAgain : .findPeopleAndPets)
                if scan.scannedCount > 0 {
                    // Confirmed like the other two destructive rows on this
                    // screen: the scan it throws away is the slowest thing the
                    // app does.
                    Button(role: .destructive) {
                        isClearScanConfirmationPresented = true
                    } label: {
                        rowLabel(.clearScanResults, style: .destructive)
                    }
                    .settingsRow(.clearScanResults)
                }
            }
        } header: {
            if showsHeader {
                SettingsSectionHeader(SettingsSection.subjectScan.title)
            }
        } footer: {
            Text("Looks through your photos for faces and for cats and dogs, then offers them as collections. This is the one thing ShotDex does that opens each photo in full, so it is slower than indexing and better left to a charger.\n\nIt all happens on this iPhone, and it counts faces without recognising anyone — iOS gives apps no way to tell one person from another.")
        }
        .task { dependencies.subjectScan.refreshCoverage() }
    }

    private func subjectScanProgressRow(_ scan: SubjectScanModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let progress = scan.progress, progress.total > 0 {
                    ProgressView(value: progress.fraction)
                    Text("\(Int(progress.fraction * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                    Text("Looking through your photos…")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { scan.cancel() }
            }
            if let progress = scan.progress, progress.total > 0 {
                Text("\(progress.processed.formatted()) of \(progress.total.formatted()) photos")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subjectScanCountLabel: String {
        let scan = dependencies.subjectScan
        guard scan.totalCount > 0 else { return "No photos yet" }
        return "\(scan.scannedCount.formatted()) of \(scan.totalCount.formatted())"
    }

    /// Shared by the live row and the empty/dim states elsewhere: what indexing
    /// is doing, in words a photographer can act on.
    private static let explainer = "ShotDex is reading the camera, lens and exposure info from each photo and video. For items kept in iCloud it downloads only the small part of the file holding that info — nothing is saved to this iPhone. The app may feel slow until this finishes."

    // MARK: Notifications

    private func notificationsSection(showsHeader: Bool) -> some View {
        Section {
            Toggle(isOn: $isOnThisDayReminderEnabled) {
                rowLabel(.dailyOnThisDayReminder)
            }
            .settingsRow(.dailyOnThisDayReminder)
            if isOnThisDayReminderEnabled, notificationAuthorization.canNotify {
                DatePicker(
                    selection: notifyTimeBinding,
                    displayedComponents: .hourAndMinute
                ) {
                    rowLabel(.remindMeAt)
                }
                .settingsRow(.remindMeAt)
            }
            if notificationAuthorization == .denied {
                valueRow(.notificationsDenied, trailing: String(localized: "Denied", comment: "Settings → Notifications: iOS refuses this app's notifications"))
                    .settingsRow(.notificationsDenied)
                Button { openAppSettings() } label: {
                    rowLabel(.openNotificationSettings, style: .action)
                }
                .settingsRow(.openNotificationSettings)
            }
        } header: {
            if showsHeader {
                SettingsSectionHeader(SettingsSection.notifications.title)
            }
        } footer: {
            Text("A daily reminder of what you shot on this date in past years, and how much space it takes. Days with nothing are skipped.")
        }
    }

    /// The stored minutes-since-midnight as a `Date` for the picker. The
    /// conversion lives in `OnThisDayNotificationSchedule` so it is unit-tested
    /// rather than inlined here.
    private var notifyTimeBinding: Binding<Date> {
        Binding(
            get: {
                OnThisDayNotificationSchedule.date(
                    fromMinutesSinceMidnight: onThisDayNotifyMinutes,
                    on: .now,
                    calendar: .current
                ) ?? .now
            },
            set: { newValue in
                onThisDayNotifyMinutes = OnThisDayNotificationSchedule.minutesSinceMidnight(
                    from: newValue, calendar: .current
                )
            }
        )
    }

    /// Turning the reminder on asks for permission first; a refusal (including a
    /// denial made earlier in system Settings, where the request returns without
    /// prompting) puts the toggle back rather than storing a preference that can
    /// never fire.
    private func applyReminderToggle(_ isEnabled: Bool) async {
        let service = dependencies.onThisDayNotifications
        if isEnabled {
            let granted = await service.enable()
            notificationAuthorization = await service.authorizationState()
            if !granted { isOnThisDayReminderEnabled = false }
        } else {
            await service.disable()
        }
    }

    // MARK: Widgets

    private func widgetsSection(showsHeader: Bool) -> some View {
        Section {
            NavigationLink {
                PhotoWidgetDesignsScreen()
            } label: {
                rowLabel(.photoWidget, value: photoWidgetSummary)
            }
            .settingsRow(.photoWidget)
        } header: {
            if showsHeader {
                SettingsSectionHeader(SettingsSection.widgets.title)
            }
        } footer: {
            Text("Add widgets by touching and holding the Home Screen. A photo widget draws the time, the date, the month, today's events or the weather over a photo you choose — make a design for each one you want. On This Day needs no setting up.")
        }
    }

    /// How many designs there are, because the row leads to a list rather
    /// than to one widget's settings.
    private var photoWidgetSummary: String {
        let designs = dependencies.photoWidgetSettings.designs
        return designs.count == 1
            ? designs[0].name
            : SettingsSummary.widgetsShort(designCount: designs.count)
    }

    // MARK: Display

    private func displaySection(showsHeader: Bool) -> some View {
        Section {
            Toggle(isOn: $showsFileTypeBadge) { rowLabel(.fileTypeBadge) }.settingsRow(.fileTypeBadge)
            Toggle(isOn: $showsISO) { rowLabel(.iso) }.settingsRow(.iso)
            Toggle(isOn: $showsAperture) { rowLabel(.aperture) }.settingsRow(.aperture)
            Toggle(isOn: $showsShutter) { rowLabel(.shutterSpeed) }.settingsRow(.shutterSpeed)
            Toggle(isOn: $showsFocal) { rowLabel(.focalLength) }.settingsRow(.focalLength)
            Picker(selection: $showsEquivalentFocalLength) {
                Text("Actual").tag(false)
                Text("FF Equivalent").tag(true)
            } label: {
                rowLabel(.focalLengthStyle)
            }
            .settingsRow(.focalLengthStyle)
            Toggle(isOn: $showsMegapixels) { rowLabel(.megapixels) }.settingsRow(.megapixels)
            Toggle(isOn: $showsFileSize) { rowLabel(.fileSize) }.settingsRow(.fileSize)
        } header: {
            if showsHeader {
                SettingsSectionHeader(LocalizedStringResource("Thumbnail metadata", comment: "Settings → Display: section header over the thumbnail switches"))
            }
        } footer: {
            Text("Pinch the photo grid to change how many columns it shows.")
        }
    }

    private func statisticsSection(showsHeader: Bool) -> some View {
        Section {
            Toggle(isOn: $showsInsights) { rowLabel(.showInsights) }.settingsRow(.showInsights)
        } header: {
            if showsHeader {
                SettingsSectionHeader(LocalizedStringResource("Statistics", comment: "Settings → Display: section header over Show Insights"))
            }
        } footer: {
            Text("Insights are short sentences about your own library at the top of Statistics.")
        }
    }

    /// Only reached from a search result: the AI item opens its screen
    /// directly.
    private var aiSection: some View {
        Section {
            NavigationLink {
                SettingsAIScreen()
            } label: {
                rowLabel(.ai, value: aiSummary)
            }
            .settingsRow(.ai)
        }
    }

    /// `Apple Intelligence` — who helps AI Search (FS-08.07 §1); `Not set
    /// up` when it is off.
    private var aiSummary: String {
        let providers = (try? dependencies.aiProviders.providers()) ?? []
        let search = AIChoice.search(stored: UserDefaults.standard.string(forKey: SettingsKeys.aiSearch), providers: providers, onDevice: OnDeviceAI.choices)
        return SettingsSummary.ai(search: search == .off ? nil : AIChoiceTitle.title(search, providers: providers))
    }

    private func playbackSection(showsHeader: Bool) -> some View {
        Section {
            Toggle(isOn: $autoplayVideos) { rowLabel(.autoplayVideos) }.settingsRow(.autoplayVideos)
            Toggle(isOn: $viewFullHDR) { rowLabel(.viewFullHDR) }.settingsRow(.viewFullHDR)
        } header: {
            if showsHeader {
                SettingsSectionHeader(SettingsSection.playback.title)
            }
        } footer: {
            Text("When autoplay is off, a video waits for you to press play. Looping is a button on the player itself. Full HDR shows high-range photos at their real brightness, which makes everything around them look darker.")
        }
    }

    /// How much of the device the library takes up, from the indexed file
    /// sizes. Photos reports the same figure in Settings, and for a metadata
    /// app it is one of the more interesting numbers there is.
    private func storageSection(showsHeader: Bool) -> some View {
        Section {
            valueRow(
                .photosAndVideos,
                value: String(localized: "Summed from the file sizes the index has read", comment: "Settings → Library size: value line under Photos and Videos"),
                trailing: storageTotalLabel
            )
            .settingsRow(.photosAndVideos)
            if let storage, storage.knownCount < storage.totalCount {
                valueRow(.measured, trailing: "\(storage.knownCount.formatted()) of \(storage.totalCount.formatted())")
                    .settingsRow(.measured)
            }
        } header: {
            if showsHeader {
                SettingsSectionHeader(LocalizedStringResource("Library size", comment: "Settings → Photo Library: section header over the library's size"))
            }
        } footer: {
            Text("Photos still stored only in iCloud are counted at their full size.", comment: "Settings → Library size footer")
        }
        .task { await loadStorage() }
    }

    private var storageTotalLabel: String {
        guard let storage else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let formatted = formatter.string(fromByteCount: storage.bytes)
        return storage.knownCount < storage.totalCount ? "~\(formatted)" : formatted
    }

    private func loadStorage() async {
        guard storage == nil else { return }
        storage = try? await dependencies.libraryQueries.storageTotals()
    }

    // MARK: Export

    private func exportSection(showsHeader: Bool) -> some View {
        Section {
            NavigationLink {
                CompressionPresetsScreen()
            } label: {
                rowLabel(.resizePresets, value: resizePresetsSummary)
            }
            .settingsRow(.resizePresets)
        } header: {
            if showsHeader {
                SettingsSectionHeader(LocalizedStringResource("Export", comment: "Settings: section header over Resize Presets"))
            }
        } footer: {
            Text("Built-in presets keep the original proportions. Add named presets for exact dimensions.")
        }
    }

    private var resizePresetsSummary: String {
        SettingsSummary.resizePresets(
            builtIn: ResizePreset.builtIns.count,
            custom: dependencies.compressionPresets.customPresets.count
        )
    }

    // MARK: File Servers

    private func fileServersSection(showsHeader: Bool) -> some View {
        Section {
            NavigationLink {
                FileServerListScreen()
            } label: {
                rowLabel(.fileServers, value: SettingsSummary.fileServers(names: fileServerNames))
            }
            .settingsRow(.fileServers)
        } header: {
            if showsHeader {
                SettingsSectionHeader(LocalizedStringResource("Upload", comment: "Settings: section header over File Servers"))
            }
        } footer: {
            Text("Upload originals to your NAS or computer over SMB or SFTP, then free up space on this device.")
        }
        .onAppear { Task { await refreshSummaries() } }
    }

    // MARK: Camera Database

    /// The camera database, then the credit for the lens data beside it —
    /// the same pane on iPad and the same page on the phone.
    @ViewBuilder
    private func cameraDatabaseSection(showsHeader: Bool) -> some View {
        Section {
            NavigationLink {
                CameraDatabaseScreen(libraryModel: libraryModel)
            } label: {
                rowLabel(.unknownCameras, value: SettingsSummary.cameraDatabase(unknownCameras: unknownCameraCount))
            }
            .settingsRow(.unknownCameras)
            Button(role: .destructive) {
                isResetMappingsConfirmationPresented = true
            } label: {
                rowLabel(
                    .resetCustomMappings,
                    value: String(localized: "Undoes the formats you picked by hand", comment: "Settings, Reset Custom Mappings value line"),
                    style: .destructive
                )
            }
            .settingsRow(.resetCustomMappings)
        } header: {
            if showsHeader {
                SettingsSectionHeader(SettingsSection.cameraDatabase.title)
            }
        }
        .onAppear { Task { await refreshSummaries() } }
        acknowledgementsSection
    }

    // MARK: Support

    /// Only reached through search on a layout that draws groups — both
    /// layouts open Support as its own screen.
    private var supportSection: some View {
        Section {
            NavigationLink {
                supportScreen
            } label: {
                rowLabel(.support, value: SettingsSummary.support())
            }
            .settingsRow(.support)
        } footer: {
            Text("Report a bug or ask for a feature. Replies come back here — there is no account and no email address to give.")
        }
    }

    // MARK: Privacy

    /// Credit for the data and libraries ShotDex ships with. Lensfun's
    /// licence (CC-BY-SA) asks for it; GRDB's (MIT) asks for the notice to
    /// travel with the app.
    private var acknowledgementsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                Text("Lensfun")
                Text("Lens profiles for distortion correction. Lensfun database, CC-BY-SA 3.0.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Link("lensfun.github.io", destination: URL(string: "https://lensfun.github.io")!)
                .font(.footnote)
            VStack(alignment: .leading, spacing: 2) {
                Text("GRDB.swift")
                Text("SQLite toolkit by Gwendal Roué. MIT License.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            SettingsSectionHeader(LocalizedStringResource("Acknowledgements", comment: "Settings → Camera Database: section header over the data credits"))
        }
    }

    private func privacySection(showsHeader: Bool) -> some View {
        Section {
            Button(role: .destructive) {
                isClearIndexConfirmationPresented = true
            } label: {
                rowLabel(
                    .clearLocalMetadataIndex,
                    value: String(localized: "Your photos are not affected", comment: "Settings, Clear Local Metadata Index value line"),
                    style: .destructive
                )
            }
            .settingsRow(.clearLocalMetadataIndex)
        } header: {
            if showsHeader {
                SettingsSectionHeader(LocalizedStringResource("Privacy", comment: "Settings → Photo Library: section header over Clear Local Metadata Index"))
            }
        } footer: {
            Text("Photos and metadata stay on this device. They leave it only when you upload them to a server you set up, or in a support message you write yourself, which carries no photos.")
        }
    }

    // MARK: Value lines

    /// The value line under a root row (FS-08.01b §1) — live state from the
    /// same sources the row's page reads.
    private func summary(for destination: SettingsDestination) -> String {
        switch destination {
        case .photoLibrary:
            SettingsSummary.photoLibrary(
                access: photoLibrary.authorizationState,
                allowsCellular: allowCellularIndexing
            )
        case .display:
            SettingsSummary.display(
                showsISO: showsISO,
                showsAperture: showsAperture,
                showsShutterSpeed: showsShutter,
                showsFocalLength: showsFocal,
                showsMegapixels: showsMegapixels,
                showsFileSize: showsFileSize,
                showsFileType: showsFileTypeBadge
            )
        case .playback:
            SettingsSummary.playback(autoplaysVideos: autoplayVideos, viewsFullHDR: viewFullHDR)
        case .ai:
            aiSummary
        case .subjectScan:
            SettingsSummary.subjectScan(
                scanned: dependencies.subjectScan.scannedCount,
                total: dependencies.subjectScan.totalCount,
                scanningPercent: subjectScanPercent
            )
        case .cameraDatabase:
            SettingsSummary.cameraDatabase(unknownCameras: unknownCameraCount)
        case .metadataWhenSharing:
            SettingsSummary.metadataWhenSharing(shareMetadataLevel)
        case .resizePresets:
            resizePresetsSummary
        case .fileServers:
            SettingsSummary.fileServers(names: fileServerNames)
        case .widgets:
            SettingsSummary.widgets(designCount: dependencies.photoWidgetSettings.designs.count)
        case .notifications:
            SettingsSummary.notifications(
                isReminderOn: isOnThisDayReminderEnabled,
                isDenied: notificationAuthorization == .denied,
                time: reminderTimeText
            )
        case .support:
            SettingsSummary.support()
        }
    }

    /// The sidebar's short form of the same facts — `nil` where the item has
    /// nothing short to say.
    private func shortSummary(for item: SettingsSection) -> String? {
        switch item {
        case .photoLibrary:
            SettingsSummary.photoLibraryShort(
                indexingPercent: (libraryModel?.isIndexing ?? false) ? libraryModel?.indexProgress?.percent : nil
            )
        case .subjectScan:
            SettingsSummary.subjectScanShort(
                scanned: dependencies.subjectScan.scannedCount,
                total: dependencies.subjectScan.totalCount,
                scanningPercent: subjectScanPercent
            )
        case .cameraDatabase:
            SettingsSummary.cameraDatabaseShort(unknownCameras: unknownCameraCount)
        case .widgets:
            SettingsSummary.widgetsShort(designCount: dependencies.photoWidgetSettings.designs.count)
        case .notifications:
            SettingsSummary.notificationsShort(
                isReminderOn: isOnThisDayReminderEnabled,
                isDenied: notificationAuthorization == .denied,
                time: reminderTimeText
            )
        case .display, .playback, .ai, .sharingAndExport, .support:
            nil
        }
    }

    private var subjectScanPercent: Int? {
        let scan = dependencies.subjectScan
        guard scan.isScanning else { return nil }
        return Int(((scan.progress?.fraction ?? 0) * 100).rounded(.down))
    }

    private var reminderTimeText: String {
        notifyTimeBinding.wrappedValue.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Helpers

    /// Off-main: four `COUNT(*)` over a 55k-row table plus a state read, none of
    /// them indexed by `exifStatus` — run on the main actor they land right on the
    /// frame that opens the sheet or reacts to a tap, which is exactly when the UI
    /// has to feel instant.
    private func refreshIndexInfo() async {
        let store = dependencies.metadataStore
        let queries = dependencies.libraryQueries
        let info = await Task.detached(priority: .userInitiated) { () -> (read: Int, total: Int, unfinished: Int, videos: Int, lastIndexedAt: Date?) in
            var videosOnly = FilterCriteria()
            videosOnly.mediaKinds = [.video]
            return (
                read: (try? store.completedCount()) ?? 0,
                total: (try? store.rowCount()) ?? 0,
                unfinished: (try? store.unfinishedCount()) ?? 0,
                videos: (try? queries.count(matching: videosOnly)) ?? 0,
                lastIndexedAt: (try? store.indexState())?.lastIndexedAt
                    .map { Date(timeIntervalSince1970: TimeInterval($0)) }
            )
        }.value
        readCount = info.read
        totalCount = info.total
        unfinishedCount = info.unfinished
        videoCount = info.videos
        photoCount = max(0, info.total - info.videos)
        lastIndexedAt = info.lastIndexedAt
    }

    /// The value-line facts that need a query: unknown cameras and the file
    /// servers' names. Small reads, but off the main actor all the same.
    private func refreshSummaries() async {
        let store = dependencies.metadataStore
        let servers = dependencies.fileServers
        let facts = await Task.detached(priority: .userInitiated) { () -> (unknown: Int, names: [String]) in
            (
                unknown: (try? store.unknownCameraModels().count) ?? 0,
                names: (try? servers.fetchAll().map(\.name)) ?? []
            )
        }.value
        unknownCameraCount = facts.unknown
        fileServerNames = facts.names
        dependencies.subjectScan.refreshCoverage()
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    // No `NavigationStack` here: the screen brings its own container, and which
    // one depends on the size class.
    return SettingsScreen(libraryModel: nil)
        .environment(dependencies)
        .environment(dependencies.photoLibrary)
        .environment(AppNavigation())
}

/// The three destructive confirmations Settings owns.
///
/// `.alert`, not `.confirmationDialog`: on iOS 26 the dialog is drawn as a
/// floating popover that hides the `.cancel` button, leaving a red button and
/// no way out — the trap DESIGN.md §10.5 documents for the editor's discard
/// prompt. Written as a modifier because three alerts inline pushed the
/// screen's body past what the type-checker will solve.
private extension View {
    func destructiveAlerts(
        clearIndex: Binding<Bool>,
        resetMappings: Binding<Bool>,
        clearScan: Binding<Bool>,
        onClearIndex: @escaping () -> Void,
        onResetMappings: @escaping () -> Void,
        onClearScan: @escaping () -> Void
    ) -> some View {
        self
            .alert("Clear the local metadata index?", isPresented: clearIndex) {
                Button("Cancel", role: .cancel) {}
                Button("Clear Index", role: .destructive, action: onClearIndex)
            } message: {
                Text("Your photos are not affected. ShotDex reads the camera and exposure data again the next time it scans your library.")
            }
            .alert("Reset all custom camera mappings?", isPresented: resetMappings) {
                Button("Cancel", role: .cancel) {}
                Button("Reset Mappings", role: .destructive, action: onResetMappings)
            } message: {
                Text("Cameras you matched to a sensor format by hand go back to what the sensor database says.")
            }
            .alert("Clear the People and Pets results?", isPresented: clearScan) {
                Button("Cancel", role: .cancel) {}
                Button("Clear Results", role: .destructive, action: onClearScan)
            } message: {
                Text("The scan opens every photo in full, so building these again takes a while.")
            }
    }
}

private extension View {
    /// Remove Source… on a source's row — swipe, and the context menu for a
    /// pointer (FS-19.01 §1, as on the Mac: FS-18.04 §3 AC-72). The Photos
    /// library is not a source that can be removed.
    @ViewBuilder
    func sourceRemoval(_ row: SourcesModel.Row, ask: @escaping () -> Void) -> some View {
        if row.text.kind == .photos {
            self
        } else {
            self
                .swipeActions {
                    Button(String(localized: "Remove", comment: "Settings › Sources: swipe to remove a source"), role: .destructive, action: ask)
                        // The list's accent tint otherwise paints it orange.
                        .tint(.red)
                }
                .contextMenu {
                    Button(role: .destructive, action: ask) {
                        Label(String(localized: "Remove Source…", comment: "Settings › Sources: remove a source"), systemImage: "minus.circle")
                    }
                }
        }
    }

    /// `.alert` for the reason `destructiveAlerts` gives.
    func removeSourceAlert(_ removing: Binding<SourcesModel.Row?>, dependencies: AppDependencies) -> some View {
        let model = dependencies.sources
        return self
            .alert(removing.wrappedValue.map { String(localized: "Remove “\($0.name)”?", comment: "Settings › Sources: Remove Source alert title") } ?? "",
                   isPresented: Binding(get: { removing.wrappedValue != nil }, set: { if !$0 { removing.wrappedValue = nil } }),
                   presenting: removing.wrappedValue) { row in
                Button(String(localized: "Cancel", comment: "Settings › Sources: keep the source"), role: .cancel) {}
                Button(String(localized: "Remove", comment: "Settings › Sources: confirm Remove Source"), role: .destructive) {
                    guard model.readingSourceId != row.id else {
                        model.failure = .error(String(localized: "“\(row.name)” is being read. Remove it when the read finishes.",
                                                      comment: "Settings › Sources: remove while the source is read"))
                        return
                    }
                    Task {
                        await model.remove(sourceId: row.id)
                        dependencies.folderRoots.forget(row.id)
                        // The grid's on-server glyph reads presence again.
                        dependencies.onServerCheck.onBatch?()
                    }
                }
            } message: { row in
                Text(row.text.removeMessage)
            }
            .alert(model.failure?.title ?? "",
                   isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } })) {
                Button(String(localized: "OK", comment: "Settings › Sources: dismiss an error")) {}
            } message: {
                Text(model.failure?.message ?? "")
            }
    }
}

/// A section header in sentence case (FS-08.01b §1): "Library and viewing",
/// not "LIBRARY AND VIEWING".
struct SettingsSectionHeader: View {
    let title: LocalizedStringResource

    init(_ title: LocalizedStringResource) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color(.secondaryLabel))
            .textCase(nil)
    }
}

private extension View {
    /// The line under the large title. A navigation bar has a subtitle only
    /// from iOS 26; earlier, the list draws the line as its first row.
    @ViewBuilder
    func settingsSubtitle(_ subtitle: Text?) -> some View {
        if #available(iOS 26.0, *), let subtitle {
            navigationSubtitle(subtitle)
        } else {
            self
        }
    }
}
