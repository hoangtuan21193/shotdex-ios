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
    @AppStorage("display.focalStyleEquivalent") private var showsEquivalentFocalLength = false
    @AppStorage(SettingsKeys.allowCellularIndexing) private var allowCellularIndexing = false
    @AppStorage(SettingsKeys.keepScreenAwake) private var keepScreenAwake = false

    /// Rows whose EXIF read has finished — the numerator of "how far along is
    /// indexing", never the row count (see `MetadataStore.rowCount`).
    @State private var readCount = 0
    /// Every asset the index knows about, read or not: the denominator.
    @State private var totalCount = 0
    @State private var incompleteCount = 0
    @State private var lastIndexedAt: Date?
    @State private var isClearIndexConfirmationPresented = false
    @State private var isResetMappingsConfirmationPresented = false
    @State private var isImportPresented = false

    var body: some View {
        List {
            photoLibrarySection
            displaySection
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

    /// The re-index actions — **one row each**, always present, disabled while a
    /// run is going — plus the live progress readout as a single row below them.
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
            Button("Re-index Library") {
                model.startIndexing(fullReindex: true, manual: true)
            }
            .disabled(model.isIndexing)

            if incompleteCount > 0 {
                Button("Re-index Incomplete Photos and Videos (\(incompleteCount))") {
                    model.reindexIncompleteAssets(manual: true)
                }
                .disabled(model.isIndexing)
            }
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

    // MARK: Display

    private var displaySection: some View {
        Section {
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
            Text("Pinch the photo grid to change how many columns are shown.\n\nFile Size is recorded while indexing — photos indexed before this option existed fill it in automatically the next time indexing runs.")
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
        let info = await Task.detached(priority: .userInitiated) { () -> (read: Int, total: Int, incomplete: Int, lastIndexedAt: Date?) in
            (
                read: (try? store.completedCount()) ?? 0,
                total: (try? store.rowCount()) ?? 0,
                incomplete: (try? store.retryableCount()) ?? 0,
                lastIndexedAt: (try? store.indexState())?.lastIndexedAt
                    .map { Date(timeIntervalSince1970: TimeInterval($0)) }
            )
        }.value
        readCount = info.read
        totalCount = info.total
        incompleteCount = info.incomplete
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
