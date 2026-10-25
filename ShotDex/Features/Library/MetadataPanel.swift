import CoreLocation
import MapKit
import Photos
import SwiftUI

/// Photographer-focused info sheet. Standard Exif/TIFF facts are curated into
/// a short default view; the exhaustive ImageIO/PhotoKit tree lives one level
/// deeper behind "Show All Raw Metadata".
struct MetadataPanel: View {
    let asset: PHAsset?
    let indexedMetadata: PhotoMetadata?
    /// Absent in previews; there the section simply never shows.
    @Environment(ServerUploadIndex.self) private var uploadIndex: ServerUploadIndex?
    @Environment(FileServerCatalog.self) private var catalog: FileServerCatalog?
    @Environment(AppDependencies.self) private var dependencies: AppDependencies?
    /// The photo's files on server sources (FS-19.07 §8).
    @State private var onServerLocations: [OnServerLocation] = []

    @State private var report: AssetMetadataReport?
    @State private var isLoading = true
    @State private var isReadingRawMetadata = false
    @State private var shutterCountState: ShutterCountState = .hidden
    @State private var isShutterNoteExpanded = false
    @State private var width: CGFloat = 0

    private enum ShutterCountState {
        case hidden
        case loading(String)
        case value(Int, String)
        case unavailable(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading, report == nil {
                    ProgressView("Reading photo info…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let report {
                    usefulMetadataList(report)
                } else {
                    ContentUnavailableView(
                        "No Metadata",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Couldn't read metadata for this item.")
                    )
                }
            }
            .navigationTitle("Photo Info")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: asset?.localIdentifier) {
            if let id = asset?.localIdentifier, let database = dependencies?.database {
                let queries = OnServerProgressQueries(database: database)
                onServerLocations = (try? await Task.detached(priority: .utility) { try queries.locations(photoId: id) }.value) ?? []
            }
            await load()
        }
    }

    /// One list on a phone. From `WideLayout.minimumWidth`
    /// up — the Duo's inner display, where the sheet is the whole screen —
    /// three columns, so everything but raw metadata fits without scrolling
    /// (board `DI_Metadata`): where and when; camera, exposure and capture
    /// settings; the file and the rest.
    private func usefulMetadataList(_ report: AssetMetadataReport) -> some View {
        Group {
            if width >= WideLayout.minimumWidth {
                HStack(alignment: .top, spacing: 0) {
                    metadataColumn(isFirst: true) {
                        captionAndLocation(report)
                        metadataSections(report, in: .whereAndWhen)
                    }
                    metadataColumn {
                        metadataSections(report, in: .camera)
                    }
                    metadataColumn(isLast: true) {
                        metadataSections(report, in: .file)
                        trailingSections(report)
                    }
                }
                .background(Color(.systemGroupedBackground))
            } else {
                List {
                    captionAndLocation(report)
                    metadataSections(report, in: nil)
                    trailingSections(report)
                }
                .listStyle(.insetGrouped)
            }
        }
        .measureWidth(into: $width)
    }

    /// Which wide-layout column a curated section goes in.
    private enum MetadataColumn {
        case whereAndWhen, camera, file

        init(sectionTitle: String) {
            switch sectionTitle {
            case "Date", "Rights & Description": self = .whereAndWhen
            case "Camera & Lens", "Exposure", "Capture Settings": self = .camera
            default: self = .file
            }
        }
    }

    private func metadataColumn<Content: View>(
        isFirst: Bool = false,
        isLast: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        List { content() }
            .listStyle(.insetGrouped)
            .contentMargins(.leading, isFirst ? AppTheme.Spacing.xl : AppTheme.Spacing.sm, for: .scrollContent)
            .contentMargins(.trailing, isLast ? AppTheme.Spacing.xl : AppTheme.Spacing.sm, for: .scrollContent)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func captionAndLocation(_ report: AssetMetadataReport) -> some View {
        // iOS 27: Photos' own caption and keywords, first, editable
        // (FS-02.07 §4). Below 27 there is nothing to read or write, and
        // the file's keywords stay in Rights & Description.
        if ExtendedMetadataSupport.isAvailable, let service = dependencies?.captionKeywords,
           let assetId = asset?.localIdentifier {
            CaptionKeywordSection(assetId: assetId, service: service)
                .id(assetId)
        }

        if let location = report.location {
            PhotoLocationSection(location: location, assetId: asset?.localIdentifier)
        } else {
            PhotoLocationUnavailableSection()
        }
    }

    /// The curated sections, all of them (`column` nil) or one wide column's.
    private func metadataSections(_ report: AssetMetadataReport, in column: MetadataColumn?) -> some View {
        let sections = report.usefulSections.filter {
            $0.title != "Location" && (column == nil || MetadataColumn(sectionTitle: $0.title) == column)
        }
        return ForEach(sections) { section in
            Section {
                CompactMetadataGrid(rows: section.rows)
            } header: {
                Label(section.title, systemImage: icon(for: section.title))
            }
        }
    }

    @ViewBuilder
    private func trailingSections(_ report: AssetMetadataReport) -> some View {
        shutterCountSection

        onServerSection
        serverUploadsSection

        Section {
            NavigationLink {
                RawMetadataView(sections: report.rawSections)
            } label: {
                HStack {
                    Label("Show All Raw Metadata", systemImage: "list.bullet.rectangle.portrait")
                    Spacer()
                    if isReadingRawMetadata {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(isReadingRawMetadata)
        } footer: {
            if isReadingRawMetadata {
                Text("Indexed photo info is ready. Detailed raw metadata is still being read in the background.")
            } else {
                Text("Includes identifiers, serial numbers, internal Exif/TIFF values, resources, and vendor-specific binary blocks.")
            }
        }
    }

    /// Byte-identical files of this photo on a server source now
    /// (FS-19.07 §8): one line per file — the source, then the path.
    @ViewBuilder
    private var onServerSection: some View {
        if !onServerLocations.isEmpty {
            Section {
                ForEach(onServerLocations, id: \.self) { location in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(location.sourceName)
                        Text(location.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Label(String(localized: "On Server", comment: "Photo Info: section listing the photo's identical files on server sources"),
                      systemImage: "externaldrive.fill.badge.checkmark")
            }
        }
    }

    /// Where copies of this photo are (FS-15.02 §8): one line per server,
    /// newest first. A photo with files on one server twice shows it once.
    @ViewBuilder
    private var serverUploadsSection: some View {
        let lines = serverUploadLines
        if !lines.isEmpty {
            Section {
                ForEach(lines, id: \.id) { line in
                    LabeledContent {
                        Text(line.date.formatted(date: .abbreviated, time: .omitted))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.server)
                            Text(line.folder)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Label("Uploaded to Server", systemImage: "server.rack")
            }
        }
    }

    /// One line per server and folder the photo's files went to — where
    /// the copy is, not just which machine (FS-15.02 §8).
    private var serverUploadLines: [(id: String, server: String, folder: String, date: Date)] {
        guard let id = asset?.localIdentifier, let uploadIndex else { return [] }
        var seen = Set<String>()
        return uploadIndex.uploads(assetId: id).compactMap { record in
            let folder = ServerUploadPath.parent(of: record.remotePath)
            let key = "\(record.serverName)\u{1F}\(folder)"
            guard seen.insert(key).inserted else { return nil }
            return (key, record.serverName, folderText(folder, serverId: record.serverId), Date(timeIntervalSince1970: TimeInterval(record.uploadedAt)))
        }
    }

    /// The folder as the connection's own row spells it — "On My iPhone ›
    /// CloudTest" for a Files folder, "Home/Photos" for SFTP — not "/" for a
    /// copy that sits at the top of a picked folder. A connection since
    /// deleted keeps the bare path.
    private func folderText(_ folder: String, serverId: String?) -> String {
        guard let serverId, var server = catalog?.servers.first(where: { $0.id == serverId }) else {
            return folder.isEmpty ? "/" : folder
        }
        server.folder = folder
        return server.folderDescription
    }

    @ViewBuilder
    private var shutterCountSection: some View {
        switch shutterCountState {
        case .hidden:
            EmptyView()
        case .loading(let note):
            Section {
                HStack {
                    Text("Actuations")
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Text("Reading original…")
                        .foregroundStyle(.secondary)
                }
                shutterNote("About shutter count", note: note)
            } header: {
                Label("Shutter Count", systemImage: "camera.shutter.button")
            }
        case .value(let count, let note):
            Section {
                LabeledContent("Actuations") {
                    Text(count.formatted())
                        .fontWeight(.semibold)
                        .textSelection(.enabled)
                }
                shutterNote("About this value", note: note)
            } header: {
                Label("Shutter Count", systemImage: "camera.shutter.button")
            }
        case .unavailable(let message):
            Section {
                Label("Not available for this file", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                shutterNote("Why unavailable?", note: message)
            } header: {
                Label("Shutter Count", systemImage: "camera.shutter.button")
            }
        }
    }

    @ViewBuilder
    private func shutterNote(_ title: String, note: String) -> some View {
        DisclosureGroup(title, isExpanded: $isShutterNoteExpanded) {
            Text(note)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
        }
        .accessibilityHint("Shows details about shutter count availability")
    }

    private func load() async {
        let initialReport = asset.flatMap {
            AssetMetadataReader.indexedReport(for: $0, metadata: indexedMetadata)
        }
        report = initialReport
        isLoading = initialReport == nil
        isReadingRawMetadata = initialReport != nil
        shutterCountState = .hidden
        guard let asset else {
            isLoading = false
            isReadingRawMetadata = false
            return
        }

        let assetID = asset.localIdentifier
        let loaded = await AssetMetadataReader.load(
            for: asset,
            indexedMetadata: indexedMetadata
        )
        guard !Task.isCancelled, self.asset?.localIdentifier == assetID else { return }
        report = loaded
        isLoading = false
        isReadingRawMetadata = false

        switch loaded.shutterCountContext.capability {
        case .notApplicable:
            shutterCountState = .hidden
        case .unavailable(let message):
            shutterCountState = .unavailable(message)
        case .readable:
            let note = AssetMetadataReader.shutterCountNote(for: loaded.shutterCountContext)
            shutterCountState = .loading(note)
            let count = await AssetMetadataReader.loadShutterCount(
                for: asset,
                context: loaded.shutterCountContext
            )
            guard !Task.isCancelled, self.asset?.localIdentifier == assetID else { return }
            if let count {
                shutterCountState = .value(count, note)
            } else {
                shutterCountState = .unavailable(
                    "No counter was found in the original. The file may be edited/exported, stored only in iCloud, or produced by a model whose MakerNote layout differs."
                )
            }
        }
    }

    private func icon(for title: String) -> String {
        switch title {
        case "File": "doc"
        case "Camera & Lens": "camera"
        case "Exposure": "dial.medium"
        case "Capture Settings": "slider.horizontal.3"
        case "Date": "calendar"
        case "Location": "location"
        case "Rights & Description": "person.text.rectangle"
        case "Video": "video"
        case let title where title.hasPrefix("Video Track"): "film"
        case "Audio Track": "waveform"
        default: "info.circle"
        }
    }
}

/// Two fields per row keeps the photographer summary scannable without hiding
/// information. Accessibility text sizes fall back to one column so values are
/// never truncated just to preserve density.
private struct CompactMetadataGrid: View {
    let rows: [MetadataReportRow]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(
            repeating: GridItem(.flexible(), spacing: 8, alignment: .topLeading),
            count: count
        )
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.key)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(row.value)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(row.key)
                .accessibilityValue(row.value)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct PhotoLocationUnavailableSection: View {
    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "location.slash")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("No location data")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("This item doesn't contain a saved capture location.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "No location data. This item doesn't contain a saved capture location."
            )
        } header: {
            Label("Location", systemImage: "map")
        }
    }
}

private struct PhotoLocationSection: View {
    let location: AssetLocation
    /// Used to read the address the indexing pass already stored, if any.
    let assetId: String?

    @State private var place: ResolvedPlace?
    @State private var isResolving = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AppDependencies.self) private var dependencies

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: location.latitude,
            longitude: location.longitude
        )
    }

    private var mapPosition: MapCameraPosition {
        .region(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
            )
        )
    }

    var body: some View {
        Section {
            Map(initialPosition: mapPosition, interactionModes: []) {
                Marker(place?.displayTitle ?? "Photo Location", coordinate: coordinate)
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 128)
            .listRowInsets(EdgeInsets())
            .accessibilityLabel("Map showing where this item was captured")

            VStack(alignment: .leading, spacing: 8) {
                if let place, let title = place.displayTitle {
                    Text(title)
                        .font(.headline)
                    if let address = place.address, address != title {
                        Text(address)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if isResolving {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Finding place name…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            coordinateFact
                            altitudeFact
                        }
                    } else {
                        HStack(alignment: .top, spacing: 24) {
                            coordinateFact
                            altitudeFact
                        }
                    }
                }
            }
            .textSelection(.enabled)
        } header: {
            Label("Location", systemImage: "map")
        } footer: {
            if place == nil, !isResolving {
                Text("Place name needs a network connection. The saved coordinate remains available offline.")
            }
        }
        .task(id: cacheKey) {
            place = nil
            // The indexing pass has usually been here already, and its answer is
            // on disk: showing that first means no spinner, no request, and a
            // place name even with no network.
            if let assetId,
               let stored = try? dependencies.placeStore.place(assetId: assetId) {
                place = stored
                return
            }
            isResolving = true
            place = await dependencies.placeGeocoding.place(
                latitude: location.latitude,
                longitude: location.longitude
            )
            isResolving = false
        }
    }

    private var coordinateText: String {
        String(format: "%.6f, %.6f", location.latitude, location.longitude)
    }

    private var coordinateFact: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Coordinates")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(coordinateText)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var altitudeFact: some View {
        if let altitude = location.altitude, abs(altitude) >= 0.5 {
            VStack(alignment: .leading, spacing: 2) {
                Text("Altitude")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(altitude, format: .number.precision(.fractionLength(0)))
                    .font(.subheadline)
                    .fontWeight(.medium)
                + Text(" m")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var cacheKey: String {
        "\(location.latitude),\(location.longitude)"
    }
}


private struct RawMetadataView: View {
    let sections: [MetadataReportSection]

    var body: some View {
        List {
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.rows) { row in
                        LabeledContent {
                            Text(row.value)
                                .font(.caption.monospaced())
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        } label: {
                            Text(row.key)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Raw Metadata")
        .navigationBarTitleDisplayMode(.inline)
    }
}
