import SwiftUI

/// Settings content, hosted in a bottom sheet: photo library /
/// index controls, display options, camera database, statistics options,
/// privacy.
struct SettingsScreen: View {
    /// Shorthand for the row labels, which every section reads from.
    private typealias Row = SettingsRowLabel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(AppDependencies.self) private var dependencies

    let libraryModel: LibraryModel?

    @AppStorage(SettingsKeys.autoplayVideos) private var autoplayVideos = true
    @AppStorage(SettingsKeys.viewFullHDR) private var viewFullHDR = false
    @AppStorage(SettingsKeys.shareIncludesLocation) private var shareIncludesLocation = true
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
    @AppStorage(SettingsKeys.keepScreenAwake) private var keepScreenAwake = false
    @AppStorage(SettingsKeys.lookUpPlaces) private var looksUpPlaces = true
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
            .task(id: libraryModel?.isIndexing) {
                await refreshIndexInfo()
            }
            .task {
                notificationAuthorization = await dependencies.onThisDayNotifications.authorizationState()
            }
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

    // MARK: Compact — one list, unchanged

    private var compactLayout: some View {
        @Bindable var navigation = navigation
        return NavigationStack(path: $navigation.compactPath) {
            settingsList
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { doneToolbarItem }
                // Only reached by a window that shrank out of the split view;
                // nothing on this list pushes a section.
                .navigationDestination(for: SettingsSection.self) { item in
                    detailRoot(for: item)
                        .toolbar { doneToolbarItem }
                }
                .searchable(
                    text: $navigation.query,
                    isPresented: $navigation.isSearchPresented,
                    prompt: Text("Search Settings")
                )
        }
    }

    private var settingsList: some View {
        settingsOrResults { groupedList(SettingsGroup.allCases) }
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
                ForEach(SettingsSection.allCases) { item in
                    Label {
                        Text(item.title)
                    } icon: {
                        Image(systemName: item.systemImage)
                            .symbolRenderingMode(.hierarchical)
                    }
                    // "Support" is a sidebar item, a pane title and a row on the
                    // phone's list all at once, so the driver cannot pick this
                    // one out by label.
                    .accessibilityIdentifier("settings.sidebar.\(item.rawValue)")
                    .tag(item)
                }
            }
        }
        .overlay {
            if navigation.isSearching, SettingsSearchIndex.results(for: navigation.query).isEmpty {
                ContentUnavailableView.search(text: navigation.query)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
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
            SupportScreen(
                service: dependencies.support,
                metadataStore: dependencies.metadataStore
            )
        default:
            groupedList(item.groups)
                .navigationTitle(item.title)
                .navigationBarTitleDisplayMode(.inline)
        }
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

    /// A list of sections, able to be sent to one of its rows by a search result.
    private func groupedList(_ groups: [SettingsGroup]) -> some View {
        ScrollViewReader { proxy in
            List {
                ForEach(groups) { group($0) }
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
    /// view the other panes do not exist yet, but the compact list and a detail
    /// pane must not both answer for the same target.
    private func revealPendingRow(in groups: [SettingsGroup], proxy: ScrollViewProxy) async {
        guard let target = navigation.pendingScrollTarget, groups.contains(target.group) else { return }
        _ = navigation.consumeScrollTarget()
        withAnimation(AppTheme.Motion.standard) {
            proxy.scrollTo(target, anchor: .center)
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

    // MARK: The thirteen sections, addressed by name

    /// One `Section`, picked by its case.
    ///
    /// Both layouts render their sections through here, so the phone's list and
    /// an iPad detail pane are drawing the same views off the same state — this
    /// screen keeps owning every `@AppStorage` and `@State` it always had.
    /// No `AnyView`: erasing the type would blur the row identity `List`
    /// animates against, which is the diff bug `indexControls` documents below.
    @ViewBuilder
    private func group(_ group: SettingsGroup) -> some View {
        switch group {
        case .photoLibrary: photoLibrarySection
        case .notifications: notificationsSection
        case .widgets: widgetsSection
        case .display: displaySection
        case .playback: playbackSection
        case .subjectScan: subjectScanSection
        case .libraryStorage: storageSection
        case .sharing: sharingSection
        case .export: exportSection
        case .fileServers: fileServersSection
        case .cameraDatabase: cameraDatabaseSection
        case .support: supportSection
        case .privacy: privacySection
        }
    }

    // MARK: Photo Library

    private var photoLibrarySection: some View {
        Section {
            LabeledContent(Row.access.title, value: authorizationLabel)
                .settingsRow(.access)
            if photoLibrary.authorizationState == .limited {
                Button(Row.manageSelectedPhotos.title) {
                    photoLibrary.presentLimitedLibraryPicker()
                }
                .settingsRow(.manageSelectedPhotos)
            }
            if photoLibrary.authorizationState == .denied {
                Button(Row.openPhotoSettings.title) { openAppSettings() }
                    .settingsRow(.openPhotoSettings)
            }

            // The pair, not a single number: the fast pass writes a row for every
            // asset within seconds, so a plain row count sat at the library total
            // from the first run and read as 100 % done forever.
            LabeledContent(Row.indexedPhotosAndVideos.title, value: readCountLabel)
                .settingsRow(.indexedPhotosAndVideos)
            if let lastIndexedAt {
                LabeledContent(
                    Row.lastIndexed.title,
                    value: lastIndexedAt.formatted(date: .abbreviated, time: .shortened)
                )
                .settingsRow(.lastIndexed)
            }

            if let model = libraryModel {
                indexControls(model)
            }

            Toggle(Row.useCellularData.title, isOn: $allowCellularIndexing)
                .settingsRow(.useCellularData)
            Toggle(Row.keepScreenAwake.title, isOn: $keepScreenAwake)
                .settingsRow(.keepScreenAwake)
            Toggle(Row.lookUpPlaceNames.title, isOn: $looksUpPlaces)
                .settingsRow(.lookUpPlaceNames)
        } header: {
            Text("Photo Library")
        } footer: {
            Text("Indexing reads the camera, lens and exposure info out of each photo and video. Wi-Fi is always allowed; in Low Power Mode automatic indexing pauses.\n\nLook Up Place Names is the only step that leaves this device — one lookup per place, then remembered.")
        }
    }

    /// The index actions — **one row each**, disabled while a run is going —
    /// plus the live progress readout as a single row below them.
    ///
    /// "Continue Indexing" is keyed to `unfinishedCount`, not the retryable
    /// (`pendingICloud`/`error`) count: a run stopped part-way leaves its
    /// remainder at `pendingRead`, so the retryable count was 0 and the only
    /// offer left was Re-index Library — throwing away tens of thousands of
    /// finished reads to redo work that just needed picking back up. The model
    /// still picks the cheaper targeted retry when every unread row is one it
    /// can serve.
    ///
    /// The actions stay put instead of being replaced by the progress rows: the
    /// swap changed the section's row set, and `List` animates that diff, so a
    /// tap slid the whole sheet around instead of acknowledging the tap. Keeping
    /// them and disabling them is also the feedback the tap needs — the row greys
    /// out on the same frame (a manual run sets `isIndexing` synchronously), and a
    /// disabled row can't be hammered into starting the run twice.
    ///
    /// `transaction` on the progress row kills the implicit animation on the one
    /// structural change that remains — this is a state readout, not a transition.
    @ViewBuilder
    private func indexControls(_ model: LibraryModel) -> some View {
        if photoLibrary.authorizationState.canReadLibrary {
            if unfinishedCount > 0 {
                // The count rides inside the localized string, not appended to
                // it: "Continue Indexing (%@)" is one phrase to translate, and
                // splitting it would leave the brackets to English word order.
                Button("Continue Indexing (\(unfinishedCount.formatted()))") {
                    model.continueIndexing()
                }
                .disabled(model.isIndexing)
                .settingsRow(.continueIndexing)
            }

            Button(Row.reindexLibrary.title) {
                model.startIndexing(fullReindex: true, manual: true)
            }
            .disabled(model.isIndexing)
            .settingsRow(.reindexLibrary)
        }

        if model.isIndexing {
            indexProgressRow(model)
                .transaction { $0.animation = nil }
        }
    }

    private func indexProgressRow(_ model: LibraryModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let progress = model.indexProgress {
                    ProgressView(value: progress.fraction)
                    Text("\(progress.percent)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                    Text("Reading photo and video info…")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { model.cancelIndexing() }
            }
            if let progress = model.indexProgress, progress.total > 0 {
                Text("\(progress.processed.formatted()) of \(progress.total.formatted()) photos and videos")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let throughput = model.indexThroughput {
                Text(throughput.summaryLine)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let network = model.indexNetworkStatus {
                Text(network.displayLine)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let diagnostics = model.indexDiagnostics {
                ForEach(diagnostics.advisories, id: \.self) { advisory in
                    Label(advisory, systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(Self.explainer)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var sharingSection: some View {
        Section {
            Toggle(Row.includeLocation.title, isOn: $shareIncludesLocation).settingsRow(.includeLocation)
        } header: {
            Text("Sharing")
        } footer: {
            Text("Turning this off removes where a photo was taken before it leaves the app. Everything else — camera, lens, exposure, date — still goes with it.\n\nVideos are unaffected: their location lives in the file itself, and removing it would mean re-encoding the whole clip.")
        }
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
    private var subjectScanSection: some View {
        @Bindable var scan = dependencies.subjectScan
        Section {
            LabeledContent(Row.scanned.title, value: subjectScanCountLabel)
                .monospacedDigit()
                .settingsRow(.scanned)

            if scan.isScanning {
                subjectScanProgressRow(scan)
                    .transaction { $0.animation = nil }
            } else {
                Button(scan.isComplete ? Row.scanAgain.title : Row.findPeopleAndPets.title) {
                    scan.start()
                }
                .disabled(!photoLibrary.authorizationState.canReadLibrary)
                .settingsRow(scan.isComplete ? .scanAgain : .findPeopleAndPets)
                if scan.scannedCount > 0 {
                    // Confirmed like the other two destructive rows on this
                    // screen: the scan it throws away is the slowest thing the
                    // app does.
                    Button(Row.clearScanResults.title, role: .destructive) {
                        isClearScanConfirmationPresented = true
                    }
                    .settingsRow(.clearScanResults)
                }
            }
        } header: {
            Text("People and Pets")
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

    private var notificationsSection: some View {
        Section {
            Toggle(Row.dailyOnThisDayReminder.title, isOn: $isOnThisDayReminderEnabled)
                .settingsRow(.dailyOnThisDayReminder)
            if isOnThisDayReminderEnabled, notificationAuthorization.canNotify {
                DatePicker(
                    Row.remindMeAt.title,
                    selection: notifyTimeBinding,
                    displayedComponents: .hourAndMinute
                )
                .settingsRow(.remindMeAt)
            }
            if notificationAuthorization == .denied {
                LabeledContent(Row.notificationsDenied.title) { Text("Denied") }
                    .settingsRow(.notificationsDenied)
                Button(Row.openNotificationSettings.title) { openAppSettings() }
                    .settingsRow(.openNotificationSettings)
            }
        } header: {
            Text("Notifications")
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

    /// How many designs there are, because the row leads to a list rather
    /// than to one widget's settings.
    private var photoWidgetSummary: String {
        let count = dependencies.photoWidgetSettings.designs.count
        return count == 1
            ? dependencies.photoWidgetSettings.designs[0].name
            : "\(count) designs"
    }

    private var widgetsSection: some View {
        Section {
            NavigationLink {
                PhotoWidgetDesignsScreen()
            } label: {
                LabeledContent(Row.photoWidget.title, value: photoWidgetSummary)
            }
            .settingsRow(.photoWidget)
        } header: {
            Text("Widgets")
        } footer: {
            Text("Add widgets by touching and holding the Home Screen. A photo widget draws the time, the date, the month, today's events or the weather over a photo you choose — make a design for each one you want. On This Day needs no setting up.")
        }
    }

    // MARK: Display

    private var displaySection: some View {
        Section {
            Toggle(Row.fileTypeBadge.title, isOn: $showsFileTypeBadge).settingsRow(.fileTypeBadge)
            Toggle(Row.iso.title, isOn: $showsISO).settingsRow(.iso)
            Toggle(Row.aperture.title, isOn: $showsAperture).settingsRow(.aperture)
            Toggle(Row.shutterSpeed.title, isOn: $showsShutter).settingsRow(.shutterSpeed)
            Toggle(Row.focalLength.title, isOn: $showsFocal).settingsRow(.focalLength)
            Picker(Row.focalLengthStyle.title, selection: $showsEquivalentFocalLength) {
                Text("Actual").tag(false)
                Text("FF Equivalent").tag(true)
            }
            .settingsRow(.focalLengthStyle)
            Toggle(Row.megapixels.title, isOn: $showsMegapixels).settingsRow(.megapixels)
            Toggle(Row.fileSize.title, isOn: $showsFileSize).settingsRow(.fileSize)
        } header: {
            Text("Thumbnail Metadata")
        } footer: {
            Text("Pinch the photo grid to change how many columns it shows.")
        }
    }

    private var playbackSection: some View {
        Section {
            Toggle(Row.autoplayVideos.title, isOn: $autoplayVideos).settingsRow(.autoplayVideos)
            Toggle(Row.viewFullHDR.title, isOn: $viewFullHDR).settingsRow(.viewFullHDR)
        } header: {
            Text("Playback")
        } footer: {
            Text("When autoplay is off, a video waits for you to press play. Looping is a button on the player itself. Full HDR shows high-range photos at their real brightness, which makes everything around them look darker.")
        }
    }

    /// How much of the device the library takes up, from the indexed file
    /// sizes. Photos reports the same figure in Settings, and for a metadata
    /// app it is one of the more interesting numbers there is.
    private var storageSection: some View {
        Section {
            LabeledContent(Row.photosAndVideos.title, value: storageTotalLabel)
                .settingsRow(.photosAndVideos)
            if let storage, storage.knownCount < storage.totalCount {
                LabeledContent(
                    Row.measured.title,
                    value: "\(storage.knownCount.formatted()) of \(storage.totalCount.formatted())"
                )
                .monospacedDigit()
                .settingsRow(.measured)
            }
        } header: {
            Text("Library Size")
        } footer: {
            Text("Summed from the file sizes the index has read. Photos still stored only in iCloud are counted at their full size.")
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

    private var exportSection: some View {
        Section {
            NavigationLink {
                CompressionPresetsScreen()
            } label: {
                LabeledContent(
                    Row.resizePresets.title,
                    value: "\(dependencies.compressionPresets.customPresets.count) custom"
                )
            }
            .settingsRow(.resizePresets)
        } header: {
            Text("Export")
        } footer: {
            Text("Built-in presets keep the original proportions. Add named presets for exact dimensions.")
        }
    }

    // MARK: File Servers

    private var fileServersSection: some View {
        Section {
            NavigationLink {
                FileServerListScreen()
            } label: {
                LabeledContent(Row.fileServers.title, value: fileServerCountText)
            }
            .settingsRow(.fileServers)
        } header: {
            Text("File Servers")
        } footer: {
            Text("Upload originals to your NAS or computer over SMB or SFTP, then free up space on this device.")
        }
    }

    private var fileServerCountText: String {
        let count = (try? dependencies.fileServers.count()) ?? 0
        return count == 0
            ? String(localized: "None", comment: "Settings → File Servers: no server set up yet")
            : count.formatted()
    }

    // MARK: Camera Database

    /// The camera database, then the credit for the lens data beside it —
    /// the same pane on iPad and the same stretch of list on the phone.
    @ViewBuilder
    private var cameraDatabaseSection: some View {
        cameraDatabaseRows
        acknowledgementsSection
    }

    private var cameraDatabaseRows: some View {
        Section("Camera Database") {
            NavigationLink(Row.unknownCameras.title) {
                CameraDatabaseScreen(libraryModel: libraryModel)
            }
            .settingsRow(.unknownCameras)
            Button(Row.resetCustomMappings.title, role: .destructive) {
                isResetMappingsConfirmationPresented = true
            }
            .settingsRow(.resetCustomMappings)
        }
    }

    // MARK: Support

    private var supportSection: some View {
        Section {
            NavigationLink(Row.support.title) {
                SupportScreen(
                    service: dependencies.support,
                    metadataStore: dependencies.metadataStore
                )
            }
            .settingsRow(.support)
        } footer: {
            Text("Report a bug or ask for a feature. Replies come back here — there is no account and no email address to give.")
        }
    }

    // MARK: Privacy

    /// Credit for the data ShotDex ships with. Lensfun's licence (CC-BY-SA)
    /// asks for it; GRDB's (MIT) asks for the notice to travel with the app.
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
            Text("Acknowledgements")
        }
    }

    private var privacySection: some View {
        Section {
            Text("Photos and metadata never leave this device. The one exception is a support message you write yourself, which carries no photos.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(Row.clearLocalMetadataIndex.title, role: .destructive) {
                isClearIndexConfirmationPresented = true
            }
            .settingsRow(.clearLocalMetadataIndex)
        } header: {
            Text("Privacy")
        }
    }

    // MARK: Helpers

    private var authorizationLabel: String {
        switch photoLibrary.authorizationState {
        case .notDetermined: "Not Requested"
        case .authorized: "Full Access"
        case .limited: "Limited Access"
        case .denied: "Denied"
        case .restricted: "Restricted"
        }
    }

    /// `12,495 of 54,971` while work remains, the plain total once every asset
    /// has been read — "54,971 of 54,971" is noise.
    ///
    /// While a run is going the live progress is preferred over the stored
    /// counts: the counts refresh only at run edges, and a run that takes hours
    /// would otherwise show the same stale pair the whole time.
    private var readCountLabel: String {
        if let progress = libraryModel?.indexProgress, progress.total > 0 {
            return "\(progress.processed.formatted()) of \(progress.total.formatted())"
        }
        guard totalCount > 0 else { return "0" }
        guard readCount < totalCount else { return totalCount.formatted() }
        return "\(readCount.formatted()) of \(totalCount.formatted())"
    }

    /// Off-main: three `COUNT(*)` over a 55k-row table plus a state read, none of
    /// them indexed by `exifStatus` — run on the main actor they land right on the
    /// frame that opens the sheet or reacts to a tap, which is exactly when the UI
    /// has to feel instant.
    private func refreshIndexInfo() async {
        let store = dependencies.metadataStore
        let info = await Task.detached(priority: .userInitiated) { () -> (read: Int, total: Int, unfinished: Int, lastIndexedAt: Date?) in
            (
                read: (try? store.completedCount()) ?? 0,
                total: (try? store.rowCount()) ?? 0,
                unfinished: (try? store.unfinishedCount()) ?? 0,
                lastIndexedAt: (try? store.indexState())?.lastIndexedAt
                    .map { Date(timeIntervalSince1970: TimeInterval($0)) }
            )
        }.value
        readCount = info.read
        totalCount = info.total
        unfinishedCount = info.unfinished
        lastIndexedAt = info.lastIndexedAt
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
