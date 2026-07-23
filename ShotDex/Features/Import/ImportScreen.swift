import SwiftUI
import UniformTypeIdentifiers

/// Import photos from an external volume (SD card / USB / folder) into the
/// photo library, filtering out RAW. The user picks a folder (iOS exposes
/// mounted cards through the document picker — there is no API to auto-detect
/// them), the grid shows every image with RAW hidden by default, a smart-album-
/// style filter narrows further, and the selected files are copied into Photos
/// (where the normal index pipeline then picks them up).
struct ImportScreen: View {
    @Environment(\.dismiss) private var dismiss

    @State private var controller: ImportController
    @State private var isFolderPickerPresented = false
    @State private var isFilterPresented = false
    @AppStorage(SettingsKeys.gridColumns) private var storedColumns = 3

    let service: ImportService

    init(service: ImportService) {
        self.service = service
        _controller = State(initialValue: ImportController(service: service))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Import")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .fileImporter(
                    isPresented: $isFolderPickerPresented,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        controller.startFolder(url)
                    }
                }
                .sheet(isPresented: $isFilterPresented) {
                    ImportFilterSheet(controller: controller)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
        }
        .interactiveDismissDisabled(controller.phase == .importing)
        .onDisappear { controller.teardown() }
    }

    // MARK: Phases

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .pickFolder: pickFolderState
        case .scanning: scanningState
        case .browsing: browsingState
        case .importing: importingState
        case .done: doneState
        }
    }

    private var pickFolderState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sdcard")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("Import from a Card or Drive")
                .font(.title2.weight(.semibold))
            Text("Plug in your camera's SD card or a USB drive, then pick its folder (usually DCIM). RAW is skipped by default; JPEG, HEIC and videos import.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let scanError = controller.scanError {
                Text(scanError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button {
                isFolderPickerPresented = true
            } label: {
                Label("Choose Folder", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanningState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Scanning \(controller.folderName ?? "folder")…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var browsingState: some View {
        VStack(spacing: 0) {
            statusBar
            grid
            importBar
        }
    }

    private var importingState: some View {
        VStack(spacing: 16) {
            ProgressView(value: Double(controller.importDone), total: Double(max(controller.importTotal, 1)))
                .progressViewStyle(.linear)
                .frame(maxWidth: 260)
            Text("Importing \(controller.importDone) of \(controller.importTotal)…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var doneState: some View {
        VStack(spacing: 16) {
            Image(systemName: controller.importFailures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(controller.importFailures.isEmpty ? .green : .orange)
            Text("Imported ^[\(controller.importedCount) item](inflect: true)")
                .font(.title3.weight(.semibold))
            if !controller.importFailures.isEmpty {
                Text("^[\(controller.importFailures.count) file](inflect: true) couldn't be imported.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("New photos appear in your library and are indexed automatically.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Browsing pieces

    private var statusBar: some View {
        HStack(spacing: 12) {
            Text("^[\(controller.visibleCandidates.count) item](inflect: true)")
                .font(.footnote.weight(.medium))
            if controller.hideRaw && controller.rawCount > 0 {
                Text("\(controller.rawCount) RAW hidden")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !controller.isExifScanComplete {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("reading metadata \(controller.exifScanned)/\(controller.candidates.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(controller.importableCount == controller.visibleCandidates.count && !controller.visibleCandidates.isEmpty
                   ? "Deselect All" : "Select All") {
                if controller.importableCount == controller.visibleCandidates.count {
                    controller.clearSelection()
                } else {
                    controller.selectAllVisible()
                }
            }
            .font(.footnote.weight(.medium))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private var grid: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 2
            let columns = max(2, storedColumns)
            let cellWidth = (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns),
                    spacing: spacing
                ) {
                    ForEach(controller.visibleCandidates) { candidate in
                        ImportGridTile(
                            candidate: candidate,
                            service: service,
                            cellWidth: cellWidth,
                            isSelected: controller.isSelected(candidate.id)
                        )
                        .onTapGesture { controller.toggle(candidate.id) }
                    }
                }
            }
            .overlay {
                if controller.visibleCandidates.isEmpty {
                    ContentUnavailableView(
                        "No Photos Match",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Adjust the filter or turn off Hide RAW.")
                    )
                }
            }
        }
    }

    private var importBar: some View {
        HStack {
            Button {
                controller.startImport()
            } label: {
                Text(controller.importableCount > 0
                     ? "Import ^[\(controller.importableCount) item](inflect: true)"
                     : "Select items to import")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(controller.importableCount == 0)
        }
        .padding()
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        if controller.phase == .browsing {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isFilterPresented = true
                } label: {
                    Image(systemName: controller.query.isEmpty && controller.hideRaw
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel("Filter")
            }
        }
    }
}

/// One square cell in the import grid: a file-URL thumbnail (ImageIO) with a
/// selection check and a RAW badge. Unlike `PhotoGridTile` these images come
/// from files on the card, not PHAssets, so thumbnails are decoded directly.
private struct ImportGridTile: View {
    let candidate: ImportCandidate
    let service: ImportService
    let cellWidth: CGFloat
    let isSelected: Bool

    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { thumbnail }
            .overlay(alignment: .topTrailing) { selectionBadge }
            .overlay(alignment: .bottomLeading) { typeBadge }
            .clipped()
            .task(id: cellWidth) { await loadThumbnail() }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .opacity(isSelected ? 0.7 : 1)
        } else {
            Rectangle()
                .fill(Color(.secondarySystemBackground))
                .overlay {
                    if candidate.kind == .video {
                        Image(systemName: "film")
                            .foregroundStyle(.tertiary)
                    } else if candidate.isRaw {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    }
                }
        }
    }

    private var selectionBadge: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20))
            .foregroundStyle(isSelected ? Color.accentColor : .white.opacity(0.9))
            .background(Circle().fill(.black.opacity(isSelected ? 0 : 0.15)))
            .shadow(radius: 1)
            .padding(5)
    }

    @ViewBuilder
    private var typeBadge: some View {
        if candidate.kind == .video {
            Image(systemName: "play.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(5)
                .background(.black.opacity(0.45), in: Circle())
                .padding(4)
        } else if let type = candidate.fileType, type.isRawFormat {
            Text(type.displayName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.orange.opacity(0.9), in: Capsule())
                .padding(4)
        }
    }

    private func loadThumbnail() async {
        guard cellWidth > 0, image == nil else { return }
        let maxPixel = cellWidth * min(UIScreen.main.scale, 2)
        let candidate = self.candidate
        let service = self.service
        let result = await Task.detached(priority: .utility) {
            service.thumbnail(for: candidate, maxPixel: maxPixel)
        }.value
        if let result { image = result }
    }
}

/// The import filter: a RAW toggle plus the shared smart-album rule builder,
/// evaluated in-memory against the scanned candidates. Camera/lens/ISO rules
/// only resolve once the background EXIF scan finishes.
private struct ImportFilterSheet: View {
    @Bindable var controller: ImportController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Hide RAW files", isOn: $controller.hideRaw)
                } footer: {
                    Text("RAW and DNG are hidden by default; JPEG, HEIC and videos import.")
                }

                if !controller.isExifScanComplete {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Reading metadata \(controller.exifScanned)/\(controller.candidates.count)")
                                .foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("Camera, lens and exposure filters become accurate once metadata finishes loading.")
                    }
                }

                RuleBuilderSections(
                    query: $controller.query,
                    brands: controller.availableBrands,
                    bodies: controller.availableBodies,
                    lenses: controller.availableLenses,
                    matchCount: controller.visibleCandidates.count
                )
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
