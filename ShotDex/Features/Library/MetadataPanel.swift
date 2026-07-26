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

    @State private var report: AssetMetadataReport?
    @State private var isLoading = true
    @State private var isReadingRawMetadata = false
    @State private var shutterCountState: ShutterCountState = .hidden
    @State private var isShutterNoteExpanded = false

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
            await load()
        }
    }

    private func usefulMetadataList(_ report: AssetMetadataReport) -> some View {
        List {
            if let location = report.location {
                PhotoLocationSection(location: location)
            } else {
                PhotoLocationUnavailableSection()
            }

            ForEach(report.usefulSections.filter { $0.title != "Location" }) { section in
                Section {
                    CompactMetadataGrid(rows: section.rows)
                } header: {
                    Label(section.title, systemImage: icon(for: section.title))
                }
            }

            shutterCountSection

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
        .listStyle(.insetGrouped)
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
            repeating: GridItem(.flexible(), spacing: 10, alignment: .topLeading),
            count: count
        )
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
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

    @State private var place: ResolvedPhotoPlace?
    @State private var isResolving = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                Marker(place?.title ?? "Photo Location", coordinate: coordinate)
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 128)
            .listRowInsets(EdgeInsets())
            .accessibilityLabel("Map showing where this item was captured")

            VStack(alignment: .leading, spacing: 8) {
                if let place {
                    Text(place.title)
                        .font(.headline)
                    if let address = place.address, address != place.title {
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
            isResolving = true
            place = await PhotoLocationResolver.shared.resolve(location)
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

private struct ResolvedPhotoPlace: Sendable {
    let title: String
    let address: String?
}

/// Reverse geocoding is rate-limited and network-backed, so results are shared
/// for the app session. Coordinates are rounded to roughly 10 m to reuse a
/// result for bursts shot at the same place.
@MainActor
private final class PhotoLocationResolver {
    static let shared = PhotoLocationResolver()

    private struct CacheKey: Hashable {
        let latitude: Int
        let longitude: Int
        let localeIdentifier: String
    }

    private var cache: [CacheKey: ResolvedPhotoPlace] = [:]
    private var inFlight: [CacheKey: Task<ResolvedPhotoPlace?, Never>] = [:]

    func resolve(_ location: AssetLocation) async -> ResolvedPhotoPlace? {
        let key = CacheKey(
            latitude: Int((location.latitude * 10_000).rounded()),
            longitude: Int((location.longitude * 10_000).rounded()),
            localeIdentifier: Locale.current.identifier
        )
        if let cached = cache[key] {
            return cached
        }
        if let task = inFlight[key] {
            return await task.value
        }

        let task = Task {
            await Self.reverseGeocode(
                latitude: location.latitude,
                longitude: location.longitude,
                locale: Locale.current
            )
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil

        if let result {
            if cache.count >= 256 {
                cache.removeAll(keepingCapacity: true)
            }
            cache[key] = result
        }
        return result
    }

    private static func reverseGeocode(
        latitude: Double,
        longitude: Double,
        locale: Locale
    ) async -> ResolvedPhotoPlace? {
        let location = CLLocation(latitude: latitude, longitude: longitude)

        if #available(iOS 26.0, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else {
                return nil
            }
            request.preferredLocale = locale
            guard let item = try? await request.mapItems.first else {
                return nil
            }

            let title = firstNonempty(
                item.addressRepresentations?.cityWithContext,
                item.name,
                item.address?.shortAddress,
                item.addressRepresentations?.regionName
            )
            guard let title else { return nil }
            let address = item.addressRepresentations?
                .fullAddress(includingRegion: true, singleLine: true)
                ?? item.address?.fullAddress.replacingOccurrences(of: "\n", with: ", ")
            return ResolvedPhotoPlace(title: title, address: address)
        } else {
            let geocoder = CLGeocoder()
            guard let placemark = try? await geocoder.reverseGeocodeLocation(
                location,
                preferredLocale: locale
            ).first else {
                return nil
            }

            let title = firstNonempty(
                placemark.name,
                placemark.locality,
                placemark.subAdministrativeArea,
                placemark.administrativeArea,
                placemark.country
            )
            guard let title else { return nil }
            let address = uniqueNonempty([
                placemark.subLocality,
                placemark.locality,
                placemark.administrativeArea,
                placemark.country,
            ], excluding: title)
                .joined(separator: ", ")
            return ResolvedPhotoPlace(
                title: title,
                address: address.isEmpty ? nil : address
            )
        }
    }

    private static func firstNonempty(_ values: String?...) -> String? {
        values.lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func uniqueNonempty(
        _ values: [String?],
        excluding excluded: String
    ) -> [String] {
        var seen = Set([excluded])
        return values.compactMap { value in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  seen.insert(value).inserted
            else { return nil }
            return value
        }
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
