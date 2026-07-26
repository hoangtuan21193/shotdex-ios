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

    @State private var indexedCount = 0
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
            refreshIndexInfo()
        }
        .confirmationDialog(
            "Clear the local metadata index? Your photos are not affected.",
            isPresented: $isClearIndexConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Clear Index", role: .destructive) {
                try? dependencies.metadataStore.deleteAll()
                libraryModel?.reload()
                refreshIndexInfo()
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

            LabeledContent("Indexed Photos", value: "\(indexedCount)")
            if let lastIndexedAt {
                LabeledContent(
                    "Last Indexed",
                    value: lastIndexedAt.formatted(date: .abbreviated, time: .shortened)
                )
            }

            if let model = libraryModel {
                if model.isIndexing {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            if let progress = model.indexProgress {
                                ProgressView(value: progress.fraction)
                                Text("\(progress.processed)/\(progress.total) (\(progress.percent)%)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            } else {
                                ProgressView()
                                Text("Indexing…")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Cancel") { model.cancelIndexing() }
                        }
                        if let network = model.indexNetworkStatus {
                            Text(network.displayLine)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text("Only metadata is read — full photos are never downloaded, so memory use stays low. The app may feel slow until indexing finishes.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if photoLibrary.authorizationState.canReadLibrary {
                    Button("Re-index Library") {
                        model.startIndexing(fullReindex: true, manual: true)
                    }
                    if incompleteCount > 0 {
                        Button("Re-index Incomplete Photos (\(incompleteCount))") {
                            model.reindexIncompleteAssets(manual: true)
                        }
                    }
                }
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
            Text("When originals live in iCloud, ShotDex streams only the first few hundred kilobytes of each photo to read its camera metadata — nothing is stored on this device. Wi-Fi is always allowed.\n\nKeep Screen Awake stops the display from sleeping while indexing runs; after 1 minute without a touch the screen dims to save battery, and tapping the screen brings it back.\n\nIn Low Power Mode, automatic indexing pauses and the screen is left to sleep; you can still start indexing by hand, and it resumes automatically when you plug in a charger.")
        }
    }

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

    private func refreshIndexInfo() {
        indexedCount = (try? dependencies.metadataStore.indexedCount()) ?? 0
        incompleteCount = (try? dependencies.metadataStore.retryableAssetIds().count) ?? 0
        let state = try? dependencies.metadataStore.indexState()
        lastIndexedAt = state?.lastIndexedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
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
