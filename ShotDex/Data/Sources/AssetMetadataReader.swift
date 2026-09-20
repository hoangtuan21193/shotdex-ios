import AVFoundation
import CoreLocation
import CoreMedia
import Foundation
import ImageIO
import os
import Photos

/// One key/value line in the raw-metadata dump.
struct MetadataReportRow: Identifiable, Sendable {
    let key: String
    let value: String
    /// Position-scoped so duplicate keys across nested blocks stay distinct.
    let id: String
}

/// A titled group of raw-metadata rows (e.g. "{Exif}", "Video Track").
struct MetadataReportSection: Identifiable, Sendable {
    let title: String
    let rows: [MetadataReportRow]
    var id: String { title }
}

/// Camera context used to decide whether reading an original file for shutter
/// count is useful. Unsupported vendors stay visible in the UI with an honest
/// explanation instead of silently omitting the row.
struct ShutterCountContext: Sendable {
    enum Capability: Sendable {
        case readable
        case unavailable(String)
        case notApplicable
    }

    let make: String?
    let model: String?
    let capability: Capability
}

/// One metadata read produces both a photographer-focused summary and the
/// exhaustive dump behind "Show All Raw Metadata". Building both from the same
/// ImageIO property dictionary avoids downloading/parsing the asset twice.
struct AssetMetadataReport: Sendable {
    let usefulSections: [MetadataReportSection]
    let rawSections: [MetadataReportSection]
    let shutterCountContext: ShutterCountContext
    let location: AssetLocation?
}

/// Value-only location snapshot safe to pass from the metadata reader into
/// SwiftUI without retaining a PhotoKit/Core Location reference type.
struct AssetLocation: Sendable, Equatable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?

    init(latitude: Double, longitude: Double, altitude: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude = location.altitude
    }
}

private struct OriginalMetadataReadState {
    var buffer = Data()
    var finished = false
    var requestID: PHAssetResourceDataRequestID?
}

/// Reads metadata live on demand. The default sheet consumes only
/// `usefulSections`; raw ImageIO/PhotoKit values remain available separately.
enum AssetMetadataReader {
    /// Builds the first frame entirely from the indexed database row plus
    /// cheap PHAsset facts. The sheet can render this synchronously while the
    /// richer ImageIO/raw report is read in the background.
    static func indexedReport(
        for asset: PHAsset,
        metadata: PhotoMetadata?
    ) -> AssetMetadataReport? {
        guard let metadata else { return nil }
        let location = resolvedLocation(asset: asset, metadata: metadata)
        let useful = indexedUsefulSections(
            asset: asset,
            metadata: metadata,
            location: location
        )
        let context = shutterCountContext(
            mediaType: asset.mediaType,
            make: metadata.cameraManufacturer,
            model: metadata.cameraModel
        )
        return AssetMetadataReport(
            usefulSections: useful.filter { !$0.rows.isEmpty },
            rawSections: [assetSection(asset), locationSection(location)]
                .filter { !$0.rows.isEmpty },
            shutterCountContext: context,
            location: location
        )
    }

    static func load(
        for asset: PHAsset,
        indexedMetadata: PhotoMetadata? = nil
    ) async -> AssetMetadataReport {
        let location = resolvedLocation(asset: asset, metadata: indexedMetadata)
        if asset.mediaType == .video {
            let technicalSections = await videoSections(asset)
            let useful = [
                locationSection(location),
            ] + technicalSections + [
                usefulDateSection(asset),
                usefulFileSection(asset, indexedMetadata: indexedMetadata),
            ]
            let raw = [assetSection(asset)]
                + resourceSections(asset)
                + technicalSections
                + [locationSection(location)]
            return AssetMetadataReport(
                usefulSections: useful.filter { !$0.rows.isEmpty },
                rawSections: raw.filter { !$0.rows.isEmpty },
                shutterCountContext: ShutterCountContext(
                    make: nil,
                    model: nil,
                    capability: .notApplicable
                ),
                location: location
            )
        }

        let properties = await imageProperties(asset)
        let liveMakeModel = makeModel(from: properties)
        let make = liveMakeModel.0 ?? indexedMetadata?.cameraManufacturer
        let model = liveMakeModel.1 ?? indexedMetadata?.cameraModel
        let useful = usefulPhotoSections(
            asset: asset,
            properties: properties,
            indexedMetadata: indexedMetadata,
            location: location
        )
        let raw = [assetSection(asset)]
            + resourceSections(asset)
            + rawImageSections(properties ?? [:])
            + [locationSection(location)]
        return AssetMetadataReport(
            usefulSections: useful.filter { !$0.rows.isEmpty },
            rawSections: raw.filter { !$0.rows.isEmpty },
            shutterCountContext: ShutterCountContext(
                make: make,
                model: model,
                capability: shutterCountCapability(make: make)
            ),
            location: location
        )
    }

    // MARK: PHAsset facts

    private static func assetSection(_ asset: PHAsset) -> MetadataReportSection {
        var pairs: [(String, String?)] = [
            (String(localized: "Local Identifier", comment: "Info panel row label"), asset.localIdentifier),
            (String(localized: "Media Type", comment: "Info panel row label"), mediaTypeName(asset.mediaType)),
            (String(localized: "Media Subtypes", comment: "Info panel row label"), subtypeNames(asset.mediaSubtypes)),
            (String(localized: "Pixel Size", comment: "Info panel row label"), "\(asset.pixelWidth) × \(asset.pixelHeight)"),
            (String(localized: "Creation Date", comment: "Info panel row label"), asset.creationDate.map(dateString)),
            (String(localized: "Modification Date", comment: "Info panel row label"), asset.modificationDate.map(dateString)),
            (String(localized: "Favorite", comment: "Info panel row label"), asset.isFavorite ? "Yes" : nil),
            (String(localized: "Hidden", comment: "Info panel row label"), asset.isHidden ? "Yes" : nil),
        ]
        if asset.mediaType == .video {
            pairs.append(("Duration", MetadataFormatter.duration(asset.duration)))
        }
        return section(String(localized: "Photo", comment: "Info panel section title"), from: pairs)
    }

    private static func resolvedLocation(
        asset: PHAsset,
        metadata: PhotoMetadata?
    ) -> AssetLocation? {
        if let location = asset.location {
            return AssetLocation(location)
        }
        guard let latitude = metadata?.latitude,
              let longitude = metadata?.longitude
        else { return nil }
        return AssetLocation(latitude: latitude, longitude: longitude)
    }

    private static func locationSection(_ location: AssetLocation?) -> MetadataReportSection {
        guard let location else { return section(String(localized: "Location", comment: "Info panel section title"), from: []) }
        return section(String(localized: "Location", comment: "Info panel section title"), from: [
            (String(localized: "Coordinate", comment: "Info panel row label"), "\(decimal(location.latitude, 6)), \(decimal(location.longitude, 6))"),
            (String(localized: "Altitude", comment: "Info panel row label"), location.altitude.map { "\(decimal($0, 1)) m" }),
        ])
    }

    /// One section per file behind the asset, headed by what the file *is*.
    ///
    /// "Resource 1 / Resource 2" is PHAssetResource's vocabulary, and a
    /// photographer looking at a RAW+JPEG pair wants to read "RAW" and
    /// "JPEG", not count. The type alone is not enough either — both halves
    /// of that pair are `.photo` — so the format goes in the heading and the
    /// index only comes back when two headings would otherwise match.
    private static func resourceSections(_ asset: PHAsset) -> [MetadataReportSection] {
        let resources = PHAssetResource.assetResources(for: asset)
        let headings = resources.map(resourceHeading)
        return zip(resources, headings.indices).map { resource, index in
            let size = (resource.value(forKey: "fileSize") as? NSNumber)?.intValue
            let pairs: [(String, String?)] = [
                (String(localized: "Original Filename", comment: "Info panel row label"), resource.originalFilename),
                (String(localized: "Type", comment: "Info panel row label"), resourceTypeName(resource.type)),
                (String(localized: "UTI", comment: "Info panel row label"), resource.uniformTypeIdentifier),
                (String(localized: "File Size", comment: "Info panel row label"), size.flatMap { MetadataFormatter.fileSize($0) }),
            ]
            let heading = headings[index]
            let duplicates = headings.filter { $0 == heading }.count
            let ordinal = headings[..<index].filter { $0 == heading }.count + 1
            return section(duplicates > 1 ? "\(heading) \(ordinal)" : heading, from: pairs)
        }
    }

    /// `RAW`, `JPEG`, `Paired Video` — the format where the filename gives
    /// one, the resource's own kind where it does not.
    private static func resourceHeading(_ resource: PHAssetResource) -> String {
        let ext = URL(fileURLWithPath: resource.originalFilename).pathExtension
        return resourceHeadingText(kind: resourceTypeName(resource.type), fileExtension: ext)
    }

    /// The composition rule `resourceHeading` applies, pulled out on its own
    /// so it can be unit-tested without a live `PHAssetResource` — PhotoKit
    /// hands those out only from `assetResources(for:)`, never from an
    /// initializer a test could call.
    static func resourceHeadingText(kind: String, fileExtension: String) -> String {
        guard let format = FileTypeBadge.text(forExtension: fileExtension) else { return kind }
        // "Photo · RAW" reads as a label; "Paired Video · MOV" does not add
        // anything the kind has not already said.
        return kind == "Photo" ? format : "\(kind) · \(format)"
    }

    private static func usefulFileSection(
        _ asset: PHAsset,
        indexedMetadata: PhotoMetadata? = nil
    ) -> MetadataReportSection {
        let resource = PHAssetResource.assetResources(for: asset)
            .first { $0.type == .photo || $0.type == .video || $0.type == .fullSizePhoto || $0.type == .fullSizeVideo }
        let size = indexedMetadata?.fileSize
            ?? (resource?.value(forKey: "fileSize") as? NSNumber)?.intValue
        var pairs: [(String, String?)] = [
            (String(localized: "Filename", comment: "Info panel row label"), resource?.originalFilename ?? indexedMetadata?.originalFilename),
            (String(localized: "Format", comment: "Info panel row label"), resource?.uniformTypeIdentifier),
            (String(localized: "Dimensions", comment: "Info panel row label"), resolvedDimensions(asset: asset, metadata: indexedMetadata)
                .map { "\($0.width) × \($0.height)" }),
            (String(localized: "Megapixels", comment: "Info panel row label"), resolvedDimensions(asset: asset, metadata: indexedMetadata)
                .flatMap { MetadataFormatter.megapixels(Double($0.width * $0.height) / 1_000_000) }),
            (String(localized: "File Size", comment: "Info panel row label"), size.flatMap { MetadataFormatter.fileSize($0) }),
            (String(localized: "Type", comment: "Info panel row label"), subtypeNames(asset.mediaSubtypes)),
        ]
        if asset.mediaType == .video {
            pairs.append(("Duration", MetadataFormatter.duration(asset.duration)))
        }
        return section(String(localized: "File", comment: "Info panel section title"), from: pairs)
    }

    private static func indexedUsefulSections(
        asset: PHAsset,
        metadata: PhotoMetadata,
        location: AssetLocation?
    ) -> [MetadataReportSection] {
        let dimensions = resolvedDimensions(asset: asset, metadata: metadata)
        let camera = section(String(localized: "Camera & Lens", comment: "Info panel section title"), from: [
            (String(localized: "Make", comment: "Info panel row label"), metadata.cameraManufacturer ?? metadata.normalizedCameraManufacturer),
            (String(localized: "Model", comment: "Info panel row label"), metadata.cameraModel ?? metadata.normalizedCameraModel),
            (String(localized: "Lens", comment: "Info panel row label"), metadata.lensModel ?? metadata.normalizedLensModel),
            (String(localized: "Lens Make", comment: "Info panel row label"), metadata.lensManufacturer),
        ])
        let exposure = section(String(localized: "Exposure", comment: "Info panel section title"), from: [
            (String(localized: "Shutter Speed", comment: "Info panel row label"), metadata.shutterSpeedDisplay
                ?? metadata.shutterSpeedSeconds.flatMap(MetadataFormatter.shutterSpeed)),
            (String(localized: "Aperture", comment: "Info panel row label"), metadata.aperture.flatMap(MetadataFormatter.aperture)),
            (String(localized: "ISO", comment: "Info panel row label"), metadata.iso.flatMap(MetadataFormatter.iso)),
            (String(localized: "Focal Length", comment: "Info panel row label"), metadata.focalLength.flatMap(MetadataFormatter.focalLength)),
            (String(localized: "35mm Equivalent", comment: "Info panel row label"), metadata.equivalentFocalLength.flatMap(MetadataFormatter.focalLength)),
        ])
        let date = section(String(localized: "Date", comment: "Info panel section title"), from: [
            (String(localized: "Captured", comment: "Info panel row label"), metadata.creationDateValue.map(dateString)
                ?? asset.creationDate.map(dateString)),
            (String(localized: "Modified", comment: "Info panel row label"), metadata.modificationDate
                .map { Date(timeIntervalSince1970: TimeInterval($0)) }
                .map(dateString)
                ?? asset.modificationDate.map(dateString)),
        ])
        let file = section(String(localized: "File", comment: "Info panel section title"), from: [
            (String(localized: "Filename", comment: "Info panel row label"), metadata.originalFilename),
            (String(localized: "Dimensions", comment: "Info panel row label"), dimensions.map { "\($0.width) × \($0.height)" }),
            (String(localized: "Megapixels", comment: "Info panel row label"), dimensions.flatMap {
                MetadataFormatter.megapixels(Double($0.width * $0.height) / 1_000_000)
            }),
            (String(localized: "File Size", comment: "Info panel row label"), metadata.fileSize.flatMap(MetadataFormatter.fileSize)),
            (String(localized: "Type", comment: "Info panel row label"), subtypeNames(asset.mediaSubtypes)),
        ])

        return [
            locationSection(location),
            camera,
            exposure,
            date,
            file,
        ]
    }

    private static func resolvedDimensions(
        asset: PHAsset,
        metadata: PhotoMetadata?
    ) -> (width: Int, height: Int)? {
        let width = metadata?.width ?? (asset.pixelWidth > 0 ? asset.pixelWidth : nil)
        let height = metadata?.height ?? (asset.pixelHeight > 0 ? asset.pixelHeight : nil)
        guard let width, let height, width > 0, height > 0 else { return nil }
        return (width, height)
    }

    private static func usefulDateSection(_ asset: PHAsset) -> MetadataReportSection {
        section(String(localized: "Date", comment: "Info panel section title"), from: [
            (String(localized: "Captured", comment: "Info panel row label"), asset.creationDate.map(dateString)),
            (String(localized: "Modified", comment: "Info panel row label"), asset.modificationDate.map(dateString)),
        ])
    }

    // MARK: Image (ImageIO) — photographer-focused summary

    /// Cross-brand summary built from standard Exif/TIFF fields. MakerNotes
    /// differ by vendor and model, so proprietary internals stay in Raw
    /// Metadata rather than crowding the default screen with opaque numbers.
    private static func usefulPhotoSections(
        asset: PHAsset,
        properties: [CFString: Any]?,
        indexedMetadata: PhotoMetadata?,
        location: AssetLocation?
    ) -> [MetadataReportSection] {
        let props = properties ?? [:]
        let exif = nestedDict(props, kCGImagePropertyExifDictionary)
        let tiff = nestedDict(props, kCGImagePropertyTIFFDictionary)
        let aux = nestedDict(props, kCGImagePropertyExifAuxDictionary)
        let iptc = nestedDict(props, kCGImagePropertyIPTCDictionary)

        func string(_ dict: [String: Any], _ key: CFString) -> String? {
            dict[key as String].flatMap(stringify)
        }
        func number(_ dict: [String: Any], _ key: CFString) -> Double? {
            (dict[key as String] as? NSNumber)?.doubleValue
        }
        func integer(_ dict: [String: Any], _ key: CFString) -> Int? {
            (dict[key as String] as? NSNumber)?.intValue
        }
        func enumValue(_ dict: [String: Any], _ key: CFString, labels: [Int: String]) -> String? {
            guard let value = integer(dict, key) else { return nil }
            return labels[value] ?? "Other (\(value))"
        }

        let resource = PHAssetResource.assetResources(for: asset)
            .first { $0.type == .photo || $0.type == .fullSizePhoto || $0.type == .alternatePhoto }
        let fileSize = indexedMetadata?.fileSize
            ?? (resource?.value(forKey: "fileSize") as? NSNumber)?.intValue
        let pixelWidth = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
            ?? indexedMetadata?.width
            ?? asset.pixelWidth
        let pixelHeight = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
            ?? indexedMetadata?.height
            ?? asset.pixelHeight
        let file: [(String, String?)] = [
            (String(localized: "Filename", comment: "Info panel row label"), resource?.originalFilename ?? indexedMetadata?.originalFilename),
            (String(localized: "Format", comment: "Info panel row label"), resource?.uniformTypeIdentifier),
            (String(localized: "Dimensions", comment: "Info panel row label"), pixelWidth > 0 && pixelHeight > 0 ? "\(pixelWidth) × \(pixelHeight)" : nil),
            (String(localized: "Megapixels", comment: "Info panel row label"), pixelWidth > 0 && pixelHeight > 0
                ? MetadataFormatter.megapixels(Double(pixelWidth * pixelHeight) / 1_000_000)
                : nil),
            (String(localized: "File Size", comment: "Info panel row label"), fileSize.flatMap { MetadataFormatter.fileSize($0) }),
            (String(localized: "Color Model", comment: "Info panel row label"), props[kCGImagePropertyColorModel].flatMap(stringify)),
            (String(localized: "Bit Depth", comment: "Info panel row label"), (props[kCGImagePropertyDepth] as? NSNumber).map { "\($0.intValue)-bit" }),
            (String(localized: "Color Space", comment: "Info panel row label"), enumValue(exif, "ColorSpace" as CFString, labels: [
                1: "sRGB",
                2: "Adobe RGB",
                65_535: "Uncalibrated",
            ])),
        ]

        let lensModel = string(exif, kCGImagePropertyExifLensModel)
            ?? string(aux, kCGImagePropertyExifAuxLensModel)
        let firmware = string(aux, kCGImagePropertyExifAuxFirmware)
            ?? string(tiff, kCGImagePropertyTIFFSoftware)
        let camera: [(String, String?)] = [
            (String(localized: "Make", comment: "Info panel row label"), string(tiff, kCGImagePropertyTIFFMake)
                ?? indexedMetadata?.cameraManufacturer
                ?? indexedMetadata?.normalizedCameraManufacturer),
            (String(localized: "Model", comment: "Info panel row label"), string(tiff, kCGImagePropertyTIFFModel)
                ?? indexedMetadata?.cameraModel
                ?? indexedMetadata?.normalizedCameraModel),
            (String(localized: "Lens", comment: "Info panel row label"), lensModel
                ?? indexedMetadata?.lensModel
                ?? indexedMetadata?.normalizedLensModel),
            (String(localized: "Lens Make", comment: "Info panel row label"), string(exif, kCGImagePropertyExifLensMake)
                ?? indexedMetadata?.lensManufacturer),
            (String(localized: "Lens Range", comment: "Info panel row label"), lensSpecification(exif[kCGImagePropertyExifLensSpecification as String])),
            (String(localized: "Firmware / Software", comment: "Info panel row label"), firmware),
        ]

        let isoValue: Int? = {
            let ratings = exif[kCGImagePropertyExifISOSpeedRatings as String]
            if let array = ratings as? [NSNumber] { return array.first?.intValue }
            return (ratings as? NSNumber)?.intValue
                ?? (exif["ISOSpeed"] as? NSNumber)?.intValue
        }()
        let bias = number(exif, kCGImagePropertyExifExposureBiasValue)
            .map { "\($0 > 0 ? "+" : "")\(decimal($0, 1)) EV" }
        let exposure: [(String, String?)] = [
            (String(localized: "Shutter Speed", comment: "Info panel row label"), number(exif, kCGImagePropertyExifExposureTime)
                .flatMap(MetadataFormatter.shutterSpeed)
                ?? indexedMetadata?.shutterSpeedDisplay
                ?? indexedMetadata?.shutterSpeedSeconds.flatMap(MetadataFormatter.shutterSpeed)),
            (String(localized: "Aperture", comment: "Info panel row label"), number(exif, kCGImagePropertyExifFNumber)
                .flatMap(MetadataFormatter.aperture)
                ?? indexedMetadata?.aperture.flatMap(MetadataFormatter.aperture)),
            (String(localized: "ISO", comment: "Info panel row label"), isoValue.flatMap(MetadataFormatter.iso)
                ?? indexedMetadata?.iso.flatMap(MetadataFormatter.iso)),
            (String(localized: "Exposure Compensation", comment: "Info panel row label"), bias),
            (String(localized: "Focal Length", comment: "Info panel row label"), number(exif, kCGImagePropertyExifFocalLength)
                .flatMap(MetadataFormatter.focalLength)
                ?? indexedMetadata?.focalLength.flatMap(MetadataFormatter.focalLength)),
            (String(localized: "35mm Equivalent", comment: "Info panel row label"), number(exif, kCGImagePropertyExifFocalLenIn35mmFilm)
                .flatMap(MetadataFormatter.focalLength)
                ?? indexedMetadata?.equivalentFocalLength.flatMap(MetadataFormatter.focalLength)),
            (String(localized: "Subject Distance", comment: "Info panel row label"), number(exif, kCGImagePropertyExifSubjectDistance).flatMap(distance)),
        ]

        let capture: [(String, String?)] = [
            (String(localized: "Exposure Program", comment: "Info panel row label"), enumValue(exif, kCGImagePropertyExifExposureProgram, labels: exposurePrograms)),
            (String(localized: "Exposure Mode", comment: "Info panel row label"), enumValue(exif, kCGImagePropertyExifExposureMode, labels: [
                0: "Auto",
                1: "Manual",
                2: "Auto Bracket",
            ])),
            (String(localized: "Metering", comment: "Info panel row label"), enumValue(exif, kCGImagePropertyExifMeteringMode, labels: meteringModes)),
            (String(localized: "White Balance", comment: "Info panel row label"), enumValue(exif, kCGImagePropertyExifWhiteBalance, labels: [
                0: "Auto",
                1: "Manual",
            ])),
            (String(localized: "Light Source", comment: "Info panel row label"), enumValue(exif, kCGImagePropertyExifLightSource, labels: lightSources)),
            (String(localized: "Flash", comment: "Info panel row label"), integer(exif, kCGImagePropertyExifFlash).map(flashDescription)),
            (String(localized: "Scene", comment: "Info panel row label"), enumValue(exif, kCGImagePropertyExifSceneCaptureType, labels: [
                0: "Standard",
                1: "Landscape",
                2: "Portrait",
                3: "Night",
            ])),
            (String(localized: "Subject Range", comment: "Info panel row label"), enumValue(exif, kCGImagePropertyExifSubjectDistRange, labels: [
                0: "Unknown",
                1: "Macro",
                2: "Close",
                3: "Distant",
            ])),
            (String(localized: "Digital Zoom", comment: "Info panel row label"), number(exif, kCGImagePropertyExifDigitalZoomRatio)
                .flatMap { $0 > 1 ? "\(decimal($0, 1))×" : nil }),
        ]

        let date: [(String, String?)] = [
            (String(localized: "Captured", comment: "Info panel row label"), asset.creationDate.map(dateString)
                ?? string(exif, kCGImagePropertyExifDateTimeOriginal)),
            (String(localized: "Time Zone", comment: "Info panel row label"), string(exif, "OffsetTimeOriginal" as CFString)),
            (String(localized: "Modified", comment: "Info panel row label"), asset.modificationDate.map(dateString)),
        ]

        let rights: [(String, String?)] = [
            (String(localized: "Artist", comment: "Info panel row label"), string(tiff, kCGImagePropertyTIFFArtist)),
            (String(localized: "Copyright", comment: "Info panel row label"), string(tiff, kCGImagePropertyTIFFCopyright)
                ?? string(iptc, kCGImagePropertyIPTCCopyrightNotice)),
            (String(localized: "Headline", comment: "Info panel row label"), string(iptc, kCGImagePropertyIPTCHeadline)),
            (String(localized: "Caption", comment: "Info panel row label"), string(iptc, kCGImagePropertyIPTCCaptionAbstract)),
            (String(localized: "Keywords", comment: "Info panel row label"), string(iptc, kCGImagePropertyIPTCKeywords)),
            (String(localized: "Credit", comment: "Info panel row label"), string(iptc, kCGImagePropertyIPTCCredit)),
        ]

        return [
            locationSection(location),
            section(String(localized: "Camera & Lens", comment: "Info panel section title"), from: camera),
            section(String(localized: "Exposure", comment: "Info panel section title"), from: exposure),
            section(String(localized: "Capture Settings", comment: "Info panel section title"), from: capture),
            section(String(localized: "Date", comment: "Info panel section title"), from: date),
            section(String(localized: "File", comment: "Info panel section title"), from: file),
            section(String(localized: "Rights & Description", comment: "Info panel section title"), from: rights),
        ]
    }

    // MARK: ImageIO raw tree

    /// Exhaustive ImageIO tree, grouped by source dictionary. Nested
    /// dictionaries are flattened into dotted key paths; binary MakerNotes are
    /// represented by byte count so the list stays usable.
    private static func rawImageSections(_ props: [CFString: Any]) -> [MetadataReportSection] {
        var topRows: [(String, String?)] = []
        var nestedSections: [MetadataReportSection] = []

        for (key, value) in props.sorted(by: { ($0.key as String) < ($1.key as String) }) {
            let name = key as String
            if let dictionary = asStringDict(value) {
                var pairs: [(String, String?)] = []
                flatten(dictionary, prefix: nil, into: &pairs)
                nestedSections.append(section("Raw · \(name)", from: pairs))
            } else {
                topRows.append((name, stringify(value)))
            }
        }
        return [section(String(localized: "Raw · Image", comment: "Info panel section title"), from: topRows)] + nestedSections
    }

    private static func flatten(
        _ dictionary: [String: Any],
        prefix: String?,
        into pairs: inout [(String, String?)]
    ) {
        for key in dictionary.keys.sorted() {
            guard let value = dictionary[key] else { continue }
            let path = prefix.map { "\($0).\(key)" } ?? key
            if let child = asStringDict(value) {
                flatten(child, prefix: path, into: &pairs)
            } else {
                pairs.append((path, stringify(value)))
            }
        }
    }

    private static func nestedDict(_ props: [CFString: Any], _ key: CFString) -> [String: Any] {
        asStringDict(props[key]) ?? [:]
    }

    private static func asStringDict(_ value: Any?) -> [String: Any]? {
        if let dict = value as? [CFString: Any] {
            return Dictionary(uniqueKeysWithValues: dict.map { ($0.key as String, $0.value) })
        }
        return value as? [String: Any]
    }

    /// Reads the total shutter-actuation count from the asset's **original**
    /// file bytes (edits strip MakerNotes, so a derivative won't do). Best-effort
    /// per vendor — see `MakerNoteParser`.
    static func loadShutterCount(
        for asset: PHAsset,
        context: ShutterCountContext
    ) async -> Int? {
        guard case .readable = context.capability,
              let make = context.make
        else { return nil }
        guard let data = await originalPhotoData(asset), !data.isEmpty else { return nil }
        return MakerNoteParser.shutterCount(
            from: data,
            make: make,
            model: context.model
        )
    }

    static func shutterCountNote(for context: ShutterCountContext) -> String {
        let vendor = (context.make ?? "").uppercased()
        if vendor.contains("FUJI") {
            return "Fujifilm stores an image counter; it may reset after a firmware update and is not a guaranteed mechanical-shutter total."
        }
        if vendor.contains("SONY") {
            return "Sony reports total image exposures for supported models; electronic and mechanical shutter behavior varies by body."
        }
        return "Read from the original camera MakerNote. Edited or exported copies may not contain this value."
    }

    private static func shutterCountCapability(make: String?) -> ShutterCountContext.Capability {
        guard let make, !make.isEmpty else {
            return .unavailable("Camera manufacturer is missing from this file.")
        }
        if MakerNoteParser.isSupportedVendor(make) {
            return .readable
        }

        let vendor = make.uppercased()
        if vendor.contains("CANON") {
            return .unavailable(
                "Canon does not provide one reliable cross-model shutter-count field in image files; some newer CR3 bodies use undocumented model-specific data."
            )
        }
        if vendor.contains("OLYMPUS") || vendor.contains("OM DIGITAL") || vendor.contains("OM SYSTEM") {
            return .unavailable(
                "Olympus/OM bodies generally expose the reliable mechanical count through the camera service menu, not a consistent image-file tag."
            )
        }
        if vendor.contains("PANASONIC") || vendor.contains("LEICA") {
            return .unavailable(
                "This camera does not expose a reliable total shutter count in its standard image metadata."
            )
        }
        if vendor.contains("PENTAX") || vendor.contains("RICOH") {
            return .unavailable(
                "Pentax/Ricoh stores a proprietary encrypted counter that this build does not decode yet."
            )
        }
        return .unavailable(
            "No reliable file-based shutter-count decoder is available for \(make)."
        )
    }

    private static func shutterCountContext(
        mediaType: PHAssetMediaType,
        make: String?,
        model: String?
    ) -> ShutterCountContext {
        guard mediaType == .image else {
            return ShutterCountContext(
                make: nil,
                model: nil,
                capability: .notApplicable
            )
        }
        return ShutterCountContext(
            make: make,
            model: model,
            capability: shutterCountCapability(make: make)
        )
    }

    /// Camera make/model from the TIFF block of the already-read properties.
    private static func makeModel(from properties: [CFString: Any]?) -> (String?, String?) {
        let tiff = nestedDict(properties ?? [:], kCGImagePropertyTIFFDictionary)
        return (tiff[kCGImagePropertyTIFFMake as String] as? String,
                tiff[kCGImagePropertyTIFFModel as String] as? String)
    }

    /// Streams the original photo resource bytes (network allowed), capped so a
    /// large RAW doesn't pull megabytes just to reach the front-loaded metadata.
    private static func originalPhotoData(_ asset: PHAsset, maxBytes: Int = 16 * 1024 * 1024) async -> Data? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = ExifReader.photoResource(among: resources) else { return nil }
        return await withCheckedContinuation { continuation in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            let manager = PHAssetResourceManager.default()
            let state = OSAllocatedUnfairLock(initialState: OriginalMetadataReadState())
            let requestID = manager.requestData(for: resource, options: options) { chunk in
                let outcome = state.withLock { s -> (Data, PHAssetResourceDataRequestID?)? in
                    guard !s.finished else { return nil }
                    s.buffer.append(chunk)
                    guard s.buffer.count >= maxBytes else { return nil }
                    s.finished = true
                    return (s.buffer, s.requestID)
                }
                if let (data, requestID) = outcome {
                    if let requestID {
                        manager.cancelDataRequest(requestID)
                    }
                    continuation.resume(returning: data)
                }
            } completionHandler: { _ in
                // Outer nil → already resumed (skip); inner value → resume now.
                let result: Data?? = state.withLock { s in
                    if s.finished { return Data??.none }
                    s.finished = true
                    return Data??.some(s.buffer.isEmpty ? nil : s.buffer)
                }
                if let inner = result { continuation.resume(returning: inner) }
            }
            let shouldCancel = state.withLock { s -> Bool in
                s.requestID = requestID
                return s.finished
            }
            if shouldCancel {
                manager.cancelDataRequest(requestID)
            }
        }
    }


    /// ImageIO property dictionary, local-first. An optimized on-device
    /// derivative normally retains standard Exif/TIFF and makes the sheet
    /// appear immediately. Only fall back to an iCloud-enabled high-quality
    /// request when PhotoKit has no local image data at all.
    private static func imageProperties(_ asset: PHAsset) async -> [CFString: Any]? {
        if let local = await requestImageProperties(
            asset,
            allowNetwork: false,
            deliveryMode: .fastFormat
        ) {
            return local
        }
        return await requestImageProperties(
            asset,
            allowNetwork: true,
            deliveryMode: .highQualityFormat
        )
    }

    private static func requestImageProperties(
        _ asset: PHAsset,
        allowNetwork: Bool,
        deliveryMode: PHImageRequestOptionsDeliveryMode
    ) async -> [CFString: Any]? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = allowNetwork
            options.deliveryMode = deliveryMode
            options.isSynchronous = false
            let resumed = OSAllocatedUnfairLock(initialState: false)
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                guard resumed.withLock({ done -> Bool in
                    if done { return false }
                    done = true
                    return true
                }) else { return }
                let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                if let data,
                   let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
                   let props = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [CFString: Any] {
                    continuation.resume(returning: props)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: Video (AVFoundation)

    private static func videoSections(_ phAsset: PHAsset) async -> [MetadataReportSection] {
        guard let avAsset = await avAsset(for: phAsset) else { return [] }
        var sections: [MetadataReportSection] = []

        var video: [(String, String?)] = []
        if let duration = try? await avAsset.load(.duration) {
            video.append(("Duration", MetadataFormatter.duration(CMTimeGetSeconds(duration))))
        }
        sections.append(section(String(localized: "Video", comment: "Info panel section title"), from: video))

        if let tracks = try? await avAsset.loadTracks(withMediaType: .video) {
            for (index, track) in tracks.enumerated() {
                var rows: [(String, String?)] = []
                if let size = try? await track.load(.naturalSize) {
                    rows.append((String(localized: "Dimensions", comment: "Info panel row label"), "\(Int(size.width)) × \(Int(size.height))"))
                }
                if let fps = try? await track.load(.nominalFrameRate) {
                    rows.append((String(localized: "Frame Rate", comment: "Info panel row label"), "\(decimal(Double(fps), 2)) fps"))
                }
                if let bitrate = try? await track.load(.estimatedDataRate) {
                    rows.append((String(localized: "Data Rate", comment: "Info panel row label"), "\(decimal(Double(bitrate) / 1_000_000, 1)) Mbps"))
                }
                if let formats = try? await track.load(.formatDescriptions), let codec = formats.first {
                    rows.append((String(localized: "Codec", comment: "Info panel row label"), fourCC(CMFormatDescriptionGetMediaSubType(codec))))
                }
                sections.append(section(String(localized: "Video Track \(index + 1)", comment: "Info panel section title for one video track"), from: rows))
            }
        }

        if let audio = try? await avAsset.loadTracks(withMediaType: .audio), let track = audio.first {
            var rows: [(String, String?)] = []
            if let bitrate = try? await track.load(.estimatedDataRate) {
                rows.append((String(localized: "Data Rate", comment: "Info panel row label"), "\(decimal(Double(bitrate) / 1000, 0)) kbps"))
            }
            if let formats = try? await track.load(.formatDescriptions), let codec = formats.first {
                rows.append((String(localized: "Codec", comment: "Info panel row label"), fourCC(CMFormatDescriptionGetMediaSubType(codec))))
            }
            sections.append(section(String(localized: "Audio Track", comment: "Info panel section title"), from: rows))
        }

        if let items = try? await avAsset.load(.commonMetadata), !items.isEmpty {
            var rows: [(String, String?)] = []
            for item in items {
                let key = item.commonKey?.rawValue ?? item.identifier?.rawValue ?? "item"
                let value = (try? await item.load(.stringValue)) ?? nil
                rows.append((key, value))
            }
            sections.append(section(String(localized: "Metadata", comment: "Info panel section title"), from: rows))
        }

        return sections
    }

    private static func avAsset(for phAsset: PHAsset) async -> AVAsset? {
        await PhotoLibraryService.requestAVAsset(for: phAsset)
    }

    // MARK: Formatting

    private static let exposurePrograms: [Int: String] = [
        0: "Not Defined",
        1: "Manual",
        2: "Program AE",
        3: "Aperture Priority",
        4: "Shutter Priority",
        5: "Creative Program",
        6: "Action Program",
        7: "Portrait",
        8: "Landscape",
        9: "Bulb",
    ]

    private static let meteringModes: [Int: String] = [
        0: "Unknown",
        1: "Average",
        2: "Center-weighted",
        3: "Spot",
        4: "Multi-spot",
        5: "Multi-segment",
        6: "Partial",
        255: "Other",
    ]

    private static let lightSources: [Int: String] = [
        0: "Unknown",
        1: "Daylight",
        2: "Fluorescent",
        3: "Tungsten",
        4: "Flash",
        9: "Fine Weather",
        10: "Cloudy",
        11: "Shade",
        12: "Daylight Fluorescent",
        13: "Day White Fluorescent",
        14: "Cool White Fluorescent",
        15: "White Fluorescent",
        17: "Standard Light A",
        18: "Standard Light B",
        19: "Standard Light C",
        20: "D55",
        21: "D65",
        22: "D75",
        23: "D50",
        24: "ISO Studio Tungsten",
        255: "Other",
    ]

    private static func lensSpecification(_ value: Any?) -> String? {
        let numbers: [Double]
        if let values = value as? [NSNumber] {
            numbers = values.map(\.doubleValue)
        } else if let values = value as? [Any] {
            numbers = values.compactMap { ($0 as? NSNumber)?.doubleValue }
        } else {
            return value.flatMap(stringify)
        }
        guard numbers.count >= 4 else { return numbers.first.flatMap(MetadataFormatter.focalLength) }
        let focal = numbers[0] == numbers[1]
            ? MetadataFormatter.focalLength(numbers[0])
            : "\(cleanNumber(numbers[0]))–\(cleanNumber(numbers[1]))mm"
        let aperture = numbers[2] == numbers[3]
            ? MetadataFormatter.aperture(numbers[2])
            : "f/\(cleanNumber(numbers[2]))–\(cleanNumber(numbers[3]))"
        return MetadataFormatter.metadataLine([focal, aperture])
    }

    /// A number for the Info panel, in the reader's own notation.
    ///
    /// `String(format:)` has no locale: its decimal separator is always a
    /// dot, where half of Europe writes a comma. Now that the panel's labels
    /// are translated, its numbers cannot stay half-English.
    private static func decimal(_ value: Double, _ digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    private static func cleanNumber(_ value: Double) -> String {
        value == value.rounded()
            ? Int(value).formatted()
            : decimal(value, 1)
    }

    private static func distance(_ meters: Double) -> String? {
        guard meters > 0, meters.isFinite, meters < 1_000_000 else { return nil }
        if meters < 1 {
            return "\(decimal(meters * 100, 0)) cm"
        }
        return meters < 10
            ? "\(decimal(meters, 2)) m"
            : "\(decimal(meters, 1)) m"
    }

    private static func flashDescription(_ value: Int) -> String {
        let fired = value & 0x1 != 0
        let mode = (value >> 3) & 0x3
        let redEye = value & 0x40 != 0
        var parts = [fired ? "Fired" : "Did Not Fire"]
        switch mode {
        case 1: parts.append("Forced")
        case 2: parts.append("Suppressed")
        case 3: parts.append("Auto")
        default: break
        }
        if redEye { parts.append("Red-eye Reduction") }
        return parts.joined(separator: " · ")
    }

    private static func section(_ title: String, from pairs: [(String, String?)]) -> MetadataReportSection {
        let rows = pairs.enumerated().compactMap { index, pair -> MetadataReportRow? in
            guard let value = pair.1, !value.isEmpty else { return nil }
            return MetadataReportRow(key: pair.0, value: value, id: "\(title).\(index).\(pair.0)")
        }
        return MetadataReportSection(title: title, rows: rows)
    }

    private static func stringify(_ value: Any) -> String? {
        switch value {
        case let array as [Any]:
            return array.map { stringifyScalar($0) }.joined(separator: ", ")
        default:
            return stringifyScalar(value)
        }
    }

    private static func stringifyScalar(_ value: Any) -> String {
        if let data = value as? Data { return "\(data.count) bytes" }
        if let number = value as? NSNumber { return number.stringValue }
        return String(describing: value)
    }

    private static func dateString(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }

    private static func mediaTypeName(_ type: PHAssetMediaType) -> String {
        switch type {
        case .image: "Image"
        case .video: "Video"
        case .audio: "Audio"
        case .unknown: "Unknown"
        @unknown default: "Unknown"
        }
    }

    private static func subtypeNames(_ subtypes: PHAssetMediaSubtype) -> String? {
        var names: [String] = []
        if subtypes.contains(.photoPanorama) { names.append("Panorama") }
        if subtypes.contains(.photoHDR) { names.append("HDR") }
        if subtypes.contains(.photoScreenshot) { names.append("Screenshot") }
        if subtypes.contains(.photoLive) { names.append("Live") }
        if subtypes.contains(.photoDepthEffect) { names.append("Portrait") }
        if subtypes.contains(.videoStreamed) { names.append("Streamed") }
        if subtypes.contains(.videoHighFrameRate) { names.append("Slo-mo") }
        if subtypes.contains(.videoTimelapse) { names.append("Timelapse") }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    /// These are section headings in the Info panel, so they are read, not
    /// matched — every one is localized. The format acronym beside them
    /// (RAW, JPG, MOV) is not: those are the same word everywhere.
    private static func resourceTypeName(_ type: PHAssetResourceType) -> String {
        switch type {
        case .photo: return String(localized: "Photo", comment: "Name of one file behind a photo, as an Info panel heading")
        case .video: return String(localized: "Video", comment: "Name of one file behind a photo, as an Info panel heading")
        case .audio: return String(localized: "Audio", comment: "Name of one file behind a photo, as an Info panel heading")
        case .alternatePhoto: return String(localized: "Alternate Photo", comment: "Name of one file behind a photo, as an Info panel heading")
        case .fullSizePhoto: return String(localized: "Full-size Photo", comment: "Name of one file behind a photo, as an Info panel heading")
        case .fullSizeVideo: return String(localized: "Full-size Video", comment: "Name of one file behind a photo, as an Info panel heading")
        case .adjustmentData: return String(localized: "Adjustment Data", comment: "Name of one file behind a photo, as an Info panel heading")
        case .adjustmentBasePhoto: return String(localized: "Adjustment Base Photo", comment: "Name of one file behind a photo, as an Info panel heading")
        case .pairedVideo: return String(localized: "Paired Video", comment: "Name of one file behind a photo, as an Info panel heading")
        case .fullSizePairedVideo: return String(localized: "Full-size Paired Video", comment: "Name of one file behind a photo, as an Info panel heading")
        case .adjustmentBasePairedVideo: return String(localized: "Adjustment Base Paired Video", comment: "Name of one file behind a photo, as an Info panel heading")
        case .adjustmentBaseVideo: return String(localized: "Adjustment Base Video", comment: "Name of one file behind a photo, as an Info panel heading")
        case .photoProxy: return String(localized: "Photo Proxy", comment: "Name of one file behind a photo, as an Info panel heading")
        @unknown default: return "Other (\(type.rawValue))"
        }
    }

    private static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF),
        ]
        let string = String(bytes: bytes, encoding: .macOSRoman)?
            .trimmingCharacters(in: .whitespaces)
        return string?.isEmpty == false ? string! : "\(code)"
    }
}
