import AVFoundation
import CoreLocation
import CoreMedia
import Foundation
import ImageIO
import os
import Photos

/// One key/value line in the raw-metadata dump.
struct MetadataDumpRow: Identifiable, Sendable {
    let key: String
    let value: String
    /// Position-scoped so duplicate keys across nested blocks stay distinct.
    let id: String
}

/// A titled group of raw-metadata rows (e.g. "{Exif}", "Video Track").
struct MetadataDumpSection: Identifiable, Sendable {
    let title: String
    let rows: [MetadataDumpRow]
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
    let usefulSections: [MetadataDumpSection]
    let rawSections: [MetadataDumpSection]
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
enum AssetMetadataDump {
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

    private static func assetSection(_ asset: PHAsset) -> MetadataDumpSection {
        var pairs: [(String, String?)] = [
            ("Local Identifier", asset.localIdentifier),
            ("Media Type", mediaTypeName(asset.mediaType)),
            ("Media Subtypes", subtypeNames(asset.mediaSubtypes)),
            ("Pixel Size", "\(asset.pixelWidth) × \(asset.pixelHeight)"),
            ("Creation Date", asset.creationDate.map(dateString)),
            ("Modification Date", asset.modificationDate.map(dateString)),
            ("Favorite", asset.isFavorite ? "Yes" : nil),
            ("Hidden", asset.isHidden ? "Yes" : nil),
        ]
        if asset.mediaType == .video {
            pairs.append(("Duration", FormatUtils.duration(asset.duration)))
        }
        return section("Asset", from: pairs)
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

    private static func locationSection(_ location: AssetLocation?) -> MetadataDumpSection {
        guard let location else { return section("Location", from: []) }
        return section("Location", from: [
            ("Coordinate", String(format: "%.6f, %.6f", location.latitude, location.longitude)),
            ("Altitude", location.altitude.map { String(format: "%.1f m", $0) }),
        ])
    }

    private static func resourceSections(_ asset: PHAsset) -> [MetadataDumpSection] {
        PHAssetResource.assetResources(for: asset).enumerated().map { index, resource in
            let size = (resource.value(forKey: "fileSize") as? NSNumber)?.intValue
            let pairs: [(String, String?)] = [
                ("Original Filename", resource.originalFilename),
                ("Type", resourceTypeName(resource.type)),
                ("UTI", resource.uniformTypeIdentifier),
                ("File Size", size.flatMap { FormatUtils.fileSize($0) }),
            ]
            return section("Resource \(index + 1)", from: pairs)
        }
    }

    private static func usefulFileSection(
        _ asset: PHAsset,
        indexedMetadata: PhotoMetadata? = nil
    ) -> MetadataDumpSection {
        let resource = PHAssetResource.assetResources(for: asset)
            .first { $0.type == .photo || $0.type == .video || $0.type == .fullSizePhoto || $0.type == .fullSizeVideo }
        let size = indexedMetadata?.fileSize
            ?? (resource?.value(forKey: "fileSize") as? NSNumber)?.intValue
        var pairs: [(String, String?)] = [
            ("Filename", resource?.originalFilename ?? indexedMetadata?.originalFilename),
            ("Format", resource?.uniformTypeIdentifier),
            ("Dimensions", resolvedDimensions(asset: asset, metadata: indexedMetadata)
                .map { "\($0.width) × \($0.height)" }),
            ("Megapixels", resolvedDimensions(asset: asset, metadata: indexedMetadata)
                .flatMap { FormatUtils.megapixels(Double($0.width * $0.height) / 1_000_000) }),
            ("File Size", size.flatMap { FormatUtils.fileSize($0) }),
            ("Type", subtypeNames(asset.mediaSubtypes)),
        ]
        if asset.mediaType == .video {
            pairs.append(("Duration", FormatUtils.duration(asset.duration)))
        }
        return section("File", from: pairs)
    }

    private static func indexedUsefulSections(
        asset: PHAsset,
        metadata: PhotoMetadata,
        location: AssetLocation?
    ) -> [MetadataDumpSection] {
        let dimensions = resolvedDimensions(asset: asset, metadata: metadata)
        let camera = section("Camera & Lens", from: [
            ("Make", metadata.cameraManufacturer ?? metadata.normalizedCameraManufacturer),
            ("Model", metadata.cameraModel ?? metadata.normalizedCameraModel),
            ("Lens", metadata.lensModel ?? metadata.normalizedLensModel),
            ("Lens Make", metadata.lensManufacturer),
        ])
        let exposure = section("Exposure", from: [
            ("Shutter Speed", metadata.shutterSpeedDisplay
                ?? metadata.shutterSpeedSeconds.flatMap(FormatUtils.shutterSpeed)),
            ("Aperture", metadata.aperture.flatMap(FormatUtils.aperture)),
            ("ISO", metadata.iso.flatMap(FormatUtils.iso)),
            ("Focal Length", metadata.focalLength.flatMap(FormatUtils.focalLength)),
            ("35mm Equivalent", metadata.equivalentFocalLength.flatMap(FormatUtils.focalLength)),
        ])
        let date = section("Date", from: [
            ("Captured", metadata.creationDateValue.map(dateString)
                ?? asset.creationDate.map(dateString)),
            ("Modified", metadata.modificationDate
                .map { Date(timeIntervalSince1970: TimeInterval($0)) }
                .map(dateString)
                ?? asset.modificationDate.map(dateString)),
        ])
        let file = section("File", from: [
            ("Filename", metadata.originalFilename),
            ("Dimensions", dimensions.map { "\($0.width) × \($0.height)" }),
            ("Megapixels", dimensions.flatMap {
                FormatUtils.megapixels(Double($0.width * $0.height) / 1_000_000)
            }),
            ("File Size", metadata.fileSize.flatMap(FormatUtils.fileSize)),
            ("Type", subtypeNames(asset.mediaSubtypes)),
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

    private static func usefulDateSection(_ asset: PHAsset) -> MetadataDumpSection {
        section("Date", from: [
            ("Captured", asset.creationDate.map(dateString)),
            ("Modified", asset.modificationDate.map(dateString)),
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
    ) -> [MetadataDumpSection] {
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
            ("Filename", resource?.originalFilename ?? indexedMetadata?.originalFilename),
            ("Format", resource?.uniformTypeIdentifier),
            ("Dimensions", pixelWidth > 0 && pixelHeight > 0 ? "\(pixelWidth) × \(pixelHeight)" : nil),
            ("Megapixels", pixelWidth > 0 && pixelHeight > 0
                ? FormatUtils.megapixels(Double(pixelWidth * pixelHeight) / 1_000_000)
                : nil),
            ("File Size", fileSize.flatMap { FormatUtils.fileSize($0) }),
            ("Color Model", props[kCGImagePropertyColorModel].flatMap(stringify)),
            ("Bit Depth", (props[kCGImagePropertyDepth] as? NSNumber).map { "\($0.intValue)-bit" }),
            ("Color Space", enumValue(exif, "ColorSpace" as CFString, labels: [
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
            ("Make", string(tiff, kCGImagePropertyTIFFMake)
                ?? indexedMetadata?.cameraManufacturer
                ?? indexedMetadata?.normalizedCameraManufacturer),
            ("Model", string(tiff, kCGImagePropertyTIFFModel)
                ?? indexedMetadata?.cameraModel
                ?? indexedMetadata?.normalizedCameraModel),
            ("Lens", lensModel
                ?? indexedMetadata?.lensModel
                ?? indexedMetadata?.normalizedLensModel),
            ("Lens Make", string(exif, kCGImagePropertyExifLensMake)
                ?? indexedMetadata?.lensManufacturer),
            ("Lens Range", lensSpecification(exif[kCGImagePropertyExifLensSpecification as String])),
            ("Firmware / Software", firmware),
        ]

        let isoValue: Int? = {
            let ratings = exif[kCGImagePropertyExifISOSpeedRatings as String]
            if let array = ratings as? [NSNumber] { return array.first?.intValue }
            return (ratings as? NSNumber)?.intValue
                ?? (exif["ISOSpeed"] as? NSNumber)?.intValue
        }()
        let bias = number(exif, kCGImagePropertyExifExposureBiasValue)
            .map { String(format: "%+.1f EV", $0) }
        let exposure: [(String, String?)] = [
            ("Shutter Speed", number(exif, kCGImagePropertyExifExposureTime)
                .flatMap(FormatUtils.shutterSpeed)
                ?? indexedMetadata?.shutterSpeedDisplay
                ?? indexedMetadata?.shutterSpeedSeconds.flatMap(FormatUtils.shutterSpeed)),
            ("Aperture", number(exif, kCGImagePropertyExifFNumber)
                .flatMap(FormatUtils.aperture)
                ?? indexedMetadata?.aperture.flatMap(FormatUtils.aperture)),
            ("ISO", isoValue.flatMap(FormatUtils.iso)
                ?? indexedMetadata?.iso.flatMap(FormatUtils.iso)),
            ("Exposure Compensation", bias),
            ("Focal Length", number(exif, kCGImagePropertyExifFocalLength)
                .flatMap(FormatUtils.focalLength)
                ?? indexedMetadata?.focalLength.flatMap(FormatUtils.focalLength)),
            ("35mm Equivalent", number(exif, kCGImagePropertyExifFocalLenIn35mmFilm)
                .flatMap(FormatUtils.focalLength)
                ?? indexedMetadata?.equivalentFocalLength.flatMap(FormatUtils.focalLength)),
            ("Subject Distance", number(exif, kCGImagePropertyExifSubjectDistance).flatMap(distance)),
        ]

        let capture: [(String, String?)] = [
            ("Exposure Program", enumValue(exif, kCGImagePropertyExifExposureProgram, labels: exposurePrograms)),
            ("Exposure Mode", enumValue(exif, kCGImagePropertyExifExposureMode, labels: [
                0: "Auto",
                1: "Manual",
                2: "Auto Bracket",
            ])),
            ("Metering", enumValue(exif, kCGImagePropertyExifMeteringMode, labels: meteringModes)),
            ("White Balance", enumValue(exif, kCGImagePropertyExifWhiteBalance, labels: [
                0: "Auto",
                1: "Manual",
            ])),
            ("Light Source", enumValue(exif, kCGImagePropertyExifLightSource, labels: lightSources)),
            ("Flash", integer(exif, kCGImagePropertyExifFlash).map(flashDescription)),
            ("Scene", enumValue(exif, kCGImagePropertyExifSceneCaptureType, labels: [
                0: "Standard",
                1: "Landscape",
                2: "Portrait",
                3: "Night",
            ])),
            ("Subject Range", enumValue(exif, kCGImagePropertyExifSubjectDistRange, labels: [
                0: "Unknown",
                1: "Macro",
                2: "Close",
                3: "Distant",
            ])),
            ("Digital Zoom", number(exif, kCGImagePropertyExifDigitalZoomRatio)
                .flatMap { $0 > 1 ? String(format: "%.1f×", $0) : nil }),
        ]

        let date: [(String, String?)] = [
            ("Captured", asset.creationDate.map(dateString)
                ?? string(exif, kCGImagePropertyExifDateTimeOriginal)),
            ("Time Zone", string(exif, "OffsetTimeOriginal" as CFString)),
            ("Modified", asset.modificationDate.map(dateString)),
        ]

        let rights: [(String, String?)] = [
            ("Artist", string(tiff, kCGImagePropertyTIFFArtist)),
            ("Copyright", string(tiff, kCGImagePropertyTIFFCopyright)
                ?? string(iptc, kCGImagePropertyIPTCCopyrightNotice)),
            ("Headline", string(iptc, kCGImagePropertyIPTCHeadline)),
            ("Caption", string(iptc, kCGImagePropertyIPTCCaptionAbstract)),
            ("Keywords", string(iptc, kCGImagePropertyIPTCKeywords)),
            ("Credit", string(iptc, kCGImagePropertyIPTCCredit)),
        ]

        return [
            locationSection(location),
            section("Camera & Lens", from: camera),
            section("Exposure", from: exposure),
            section("Capture Settings", from: capture),
            section("Date", from: date),
            section("File", from: file),
            section("Rights & Description", from: rights),
        ]
    }

    // MARK: ImageIO raw tree

    /// Exhaustive ImageIO tree, grouped by source dictionary. Nested
    /// dictionaries are flattened into dotted key paths; binary MakerNotes are
    /// represented by byte count so the list stays usable.
    private static func rawImageSections(_ props: [CFString: Any]) -> [MetadataDumpSection] {
        var topRows: [(String, String?)] = []
        var nestedSections: [MetadataDumpSection] = []

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
        return [section("Raw · Image", from: topRows)] + nestedSections
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
        guard let resource = ExifService.photoResource(among: resources) else { return nil }
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

    private static func videoSections(_ phAsset: PHAsset) async -> [MetadataDumpSection] {
        guard let avAsset = await avAsset(for: phAsset) else { return [] }
        var sections: [MetadataDumpSection] = []

        var video: [(String, String?)] = []
        if let duration = try? await avAsset.load(.duration) {
            video.append(("Duration", FormatUtils.duration(CMTimeGetSeconds(duration))))
        }
        sections.append(section("Video", from: video))

        if let tracks = try? await avAsset.loadTracks(withMediaType: .video) {
            for (index, track) in tracks.enumerated() {
                var rows: [(String, String?)] = []
                if let size = try? await track.load(.naturalSize) {
                    rows.append(("Dimensions", "\(Int(size.width)) × \(Int(size.height))"))
                }
                if let fps = try? await track.load(.nominalFrameRate) {
                    rows.append(("Frame Rate", String(format: "%.2f fps", fps)))
                }
                if let bitrate = try? await track.load(.estimatedDataRate) {
                    rows.append(("Data Rate", String(format: "%.1f Mbps", bitrate / 1_000_000)))
                }
                if let formats = try? await track.load(.formatDescriptions), let codec = formats.first {
                    rows.append(("Codec", fourCC(CMFormatDescriptionGetMediaSubType(codec))))
                }
                sections.append(section("Video Track \(index + 1)", from: rows))
            }
        }

        if let audio = try? await avAsset.loadTracks(withMediaType: .audio), let track = audio.first {
            var rows: [(String, String?)] = []
            if let bitrate = try? await track.load(.estimatedDataRate) {
                rows.append(("Data Rate", String(format: "%.0f kbps", bitrate / 1000)))
            }
            if let formats = try? await track.load(.formatDescriptions), let codec = formats.first {
                rows.append(("Codec", fourCC(CMFormatDescriptionGetMediaSubType(codec))))
            }
            sections.append(section("Audio Track", from: rows))
        }

        if let items = try? await avAsset.load(.commonMetadata), !items.isEmpty {
            var rows: [(String, String?)] = []
            for item in items {
                let key = item.commonKey?.rawValue ?? item.identifier?.rawValue ?? "item"
                let value = (try? await item.load(.stringValue)) ?? nil
                rows.append((key, value))
            }
            sections.append(section("Metadata", from: rows))
        }

        return sections
    }

    private static func avAsset(for phAsset: PHAsset) async -> AVAsset? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { asset, _, _ in
                continuation.resume(returning: asset)
            }
        }
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
        guard numbers.count >= 4 else { return numbers.first.flatMap(FormatUtils.focalLength) }
        let focal = numbers[0] == numbers[1]
            ? FormatUtils.focalLength(numbers[0])
            : "\(cleanNumber(numbers[0]))–\(cleanNumber(numbers[1]))mm"
        let aperture = numbers[2] == numbers[3]
            ? FormatUtils.aperture(numbers[2])
            : "f/\(cleanNumber(numbers[2]))–\(cleanNumber(numbers[3]))"
        return FormatUtils.metadataLine([focal, aperture])
    }

    private static func cleanNumber(_ value: Double) -> String {
        value == value.rounded()
            ? "\(Int(value))"
            : String(format: "%.1f", value)
    }

    private static func distance(_ meters: Double) -> String? {
        guard meters > 0, meters.isFinite, meters < 1_000_000 else { return nil }
        if meters < 1 {
            return String(format: "%.0f cm", meters * 100)
        }
        return meters < 10
            ? String(format: "%.2f m", meters)
            : String(format: "%.1f m", meters)
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

    private static func section(_ title: String, from pairs: [(String, String?)]) -> MetadataDumpSection {
        let rows = pairs.enumerated().compactMap { index, pair -> MetadataDumpRow? in
            guard let value = pair.1, !value.isEmpty else { return nil }
            return MetadataDumpRow(key: pair.0, value: value, id: "\(title).\(index).\(pair.0)")
        }
        return MetadataDumpSection(title: title, rows: rows)
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

    private static func resourceTypeName(_ type: PHAssetResourceType) -> String {
        switch type {
        case .photo: "Photo"
        case .video: "Video"
        case .audio: "Audio"
        case .alternatePhoto: "Alternate Photo"
        case .fullSizePhoto: "Full-size Photo"
        case .fullSizeVideo: "Full-size Video"
        case .adjustmentData: "Adjustment Data"
        case .adjustmentBasePhoto: "Adjustment Base Photo"
        case .pairedVideo: "Paired Video"
        case .fullSizePairedVideo: "Full-size Paired Video"
        case .adjustmentBasePairedVideo: "Adjustment Base Paired Video"
        case .adjustmentBaseVideo: "Adjustment Base Video"
        case .photoProxy: "Photo Proxy"
        @unknown default: "Other (\(type.rawValue))"
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
