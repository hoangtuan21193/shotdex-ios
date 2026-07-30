import SwiftUI

/// Settings content, hosted in a bottom sheet: photo library /
/// index controls, display options, camera database, statistics options,
/// privacy.
struct SettingsScreen: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(AppDependencies.self) private var dependencies

    let libraryModel: LibraryModel?

    @AppStorage("display.showISO") private var showsISO = true
    @AppStorage("display.showAperture") private var showsAperture = true
    @AppStorage("display.showShutter") private var showsShutter = false
    @AppStorage("display.showFocal") private var showsFocal = true
    @AppStorage("display.showMegapixels") private var showsMegapixels = false
    @AppStorage("display.showFileSize") private var showsFileSize = false
    @AppStorage(SettingsKeys.showFileTypeBadge) private var showsFileTypeBadge = true
    @AppStorage("display.focalStyleEquivalent") private var showsEquivalentFocalLength = false
    @AppStorage(SettingsKeys.accentTheme) private var accentThemeRawValue =
        AppAccentTheme.default.rawValue
    @AppStorage(SettingsKeys.allowCellularIndexing) private var allowCellularIndexing = false
    @AppStorage(SettingsKeys.keepScreenAwake) private var keepScreenAwake = false
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
    @State private var isImportPresented = false
    @State private var notificationAuthorization: NotificationAuthorizationState = .notDetermined
    /// Debounces the reminder-time picker: `.hourAndMinute` publishes on every
    /// detent, and each refresh is seven queries plus seven scheduling calls, so
    /// one scroll would otherwise trigger dozens of full reschedules.
    @State private var notifyTimeRefreshTask: Task<Void, Never>?

    var body: some View {
        List {
            photoLibrarySection
            notificationsSection
            appearanceSection
            displaySection
            exportSection
            cameraDatabaseSection
            privacySection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isImportPresented) {
            ImportScreen(service: dependencies.importService)
        }
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
        .confirmationDialog(
            "Clear the local metadata index? Your photos are not affected.",
            isPresented: $isClearIndexConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Clear Index", role: .destructive) {
                try? dependencies.metadataStore.deleteAll()
                libraryModel?.reload()
                Task { await refreshIndexInfo() }
            }
        }
        .confirmationDialog(
            "Reset all custom camera mappings?",
            isPresented: $isResetMappingsConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Reset Mappings", role: .destructive) {
                try? dependencies.metadataStore.deleteAllCustomMappings()
            }
        }
    }

    // MARK: Photo Library

    private var photoLibrarySection: some View {
        Section {
            LabeledContent("Access", value: authorizationLabel)
            if photoLibrary.authorizationState == .limited {
                Button("Manage Selected Photos") {
                    photoLibrary.presentLimitedLibraryPicker()
                }
            }
            if photoLibrary.authorizationState == .denied {
                Button("Open Settings") { openAppSettings() }
            }

            // The pair, not a single number: the fast pass writes a row for every
            // asset within seconds, so a plain row count sat at the library total
            // from the first run and read as 100 % done forever.
            LabeledContent("Indexed Photos and Videos", value: readCountLabel)
            if let lastIndexedAt {
                LabeledContent(
                    "Last Indexed",
                    value: lastIndexedAt.formatted(date: .abbreviated, time: .shortened)
                )
            }

            if let model = libraryModel {
                indexControls(model)
            }

            if photoLibrary.authorizationState.canReadLibrary {
                Button {
                    isImportPresented = true
                } label: {
                    Label("Import Photos", systemImage: "square.and.arrow.down")
                }
            }

            Toggle("Use Cellular Data for Indexing", isOn: $allowCellularIndexing)
            Toggle("Keep Screen Awake While Indexing", isOn: $keepScreenAwake)
        } header: {
            Text("Photo Library")
        } footer: {
            Text("Indexing is how ShotDex learns what camera, lens and settings each photo was shot with. Videos are indexed too, so they show up in the library and in counts. For items kept in iCloud it downloads only the small part of the file holding that info — nothing is saved to this iPhone. Wi-Fi is always allowed.\n\nKeep Screen Awake stops the display from sleeping while indexing runs; after 1 minute without a touch the screen dims to save battery, and tapping the screen brings it back.\n\nIn Low Power Mode, automatic indexing pauses and the screen is left to sleep; you can still start indexing by hand, and it resumes automatically when you plug in a charger.")
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
                Button("Continue Indexing (\(unfinishedCount.formatted()))") {
                    model.continueIndexing()
                }
                .disabled(model.isIndexing)
            }

            Button("Re-index Library") {
                model.startIndexing(fullReindex: true, manual: true)
            }
            .disabled(model.isIndexing)
        }

        if model.isIndexing {
            indexProgressRow(model)
                .transaction { $0.animation = nil }
        }
    }

    private func indexProgressRow(_ model: LibraryModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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

    /// Shared by the live row and the empty/dim states elsewhere: what indexing
    /// is doing, in words a photographer can act on.
    private static let explainer = "ShotDex is reading the camera, lens and exposure info from each photo and video. For items kept in iCloud it downloads only the small part of the file holding that info — nothing is saved to this iPhone. The app may feel slow until this finishes."

    // MARK: Notifications

    private var notificationsSection: some View {
        Section {
            Toggle("Daily On This Day Reminder", isOn: $isOnThisDayReminderEnabled)
            if isOnThisDayReminderEnabled, notificationAuthorization.canNotify {
                DatePicker(
                    "Remind Me At",
                    selection: notifyTimeBinding,
                    displayedComponents: .hourAndMinute
                )
            }
            if notificationAuthorization == .denied {
                LabeledContent("Notifications") { Text("Denied") }
                Button("Open Settings") { openAppSettings() }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Once a day ShotDex tells you how many photos and videos you shot on that date in previous years, and how much space they take, so you can go clear out what you no longer want. Days with nothing to show are skipped.\n\nSizes come from the local index: while indexing is still running the total is reported as a minimum and grows as more files are read.\n\nReminders are scheduled a week at a time and refilled whenever you open ShotDex.")
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

    // MARK: Appearance

    /// The accent applies the moment it is picked: the root view holds the same
    /// `@AppStorage` key, so writing it re-tints the app under the open sheet.
    ///
    /// The choices are a row of tappable swatches, not a `Picker` — for a colour,
    /// the colour itself is the whole answer, and a menu would hide all of them
    /// behind a tap. `.borderless` keeps `List` from treating the row as one
    /// button and firing every swatch at once.
    private var appearanceSection: some View {
        let selected = AppAccentTheme.resolved(accentThemeRawValue)
        return Section {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Accent Color", value: selected.displayName)
                HStack(spacing: 18) {
                    ForEach(AppAccentTheme.allCases) { theme in
                        accentSwatch(theme, isSelected: theme == selected)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("Appearance")
        } footer: {
            Text("The accent color tints buttons, selections and highlights throughout ShotDex, including the photo editor. Amber and Sand are the colors of the app icon; iOS Default is the system blue.")
        }
    }

    private func accentSwatch(_ theme: AppAccentTheme, isSelected: Bool) -> some View {
        Button {
            accentThemeRawValue = theme.rawValue
        } label: {
            Circle()
                .fill(theme.color)
                .frame(width: 32, height: 32)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            // Keeps the check legible on the pale Sand swatch.
                            .shadow(color: .black.opacity(0.55), radius: 1)
                    }
                }
                .overlay {
                    // Hairline so the pale swatches (Sand in dark mode) keep an
                    // edge against the row background.
                    Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(theme.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Display

    private var displaySection: some View {
        Section {
            Toggle("File Type", isOn: $showsFileTypeBadge)
            Toggle("ISO", isOn: $showsISO)
            Toggle("Aperture", isOn: $showsAperture)
            Toggle("Shutter Speed", isOn: $showsShutter)
            Toggle("Focal Length", isOn: $showsFocal)
            Picker("Focal Length Style", selection: $showsEquivalentFocalLength) {
                Text("Actual").tag(false)
                Text("FF Equivalent").tag(true)
            }
            Toggle("Megapixels", isOn: $showsMegapixels)
            Toggle("File Size", isOn: $showsFileSize)
        } header: {
            Text("Thumbnail Metadata")
        } footer: {
            Text("File Type Badge shows RAW, JPG, HEIC or the video format in the top-left corner of each thumbnail.\n\nPinch the photo grid to change how many columns are shown.\n\nFile Size is recorded while indexing — photos indexed before this option existed fill it in automatically the next time indexing runs.")
        }
    }

    // MARK: Export

    private var exportSection: some View {
        Section {
            NavigationLink {
                CompressionPresetsScreen()
            } label: {
                LabeledContent(
                    "Compression Presets",
                    value: "\(dependencies.compressionPresets.customPresets.count) custom"
                )
            }
        } header: {
            Text("Export")
        } footer: {
            Text("Built-in presets keep the original proportions at Original, 4K, 2048 px or 1080 px. Add named presets for apps that require exact dimensions.")
        }
    }

    // MARK: Camera Database

    private var cameraDatabaseSection: some View {
        Section("Camera Database") {
            NavigationLink("Unknown Cameras") {
                CameraDatabaseScreen(libraryModel: libraryModel)
            }
            Button("Reset Custom Mappings", role: .destructive) {
                isResetMappingsConfirmationPresented = true
            }
        }
    }

    // MARK: Privacy

    private var privacySection: some View {
        Section {
            Text("ShotDex reads photo metadata entirely on your device. Your photos and metadata never leave your device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Clear Local Metadata Index", role: .destructive) {
                isClearIndexConfirmationPresented = true
            }
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
    return NavigationStack {
        SettingsScreen(libraryModel: nil)
    }
    .environment(dependencies)
    .environment(dependencies.photoLibrary)
}
