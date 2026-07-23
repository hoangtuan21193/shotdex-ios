import AVFoundation
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

/// Reads the *complete* raw metadata of an asset on demand for the info
/// sheet — every ImageIO property for photos, every AVAsset/track fact for
/// videos, plus the PHAsset and resource facts. This is deliberately
/// exhaustive (not the curated index), so it reads live and may be slow /
/// touch iCloud; callers load it asynchronously.
enum AssetMetadataDump {
    static func load(for asset: PHAsset) async -> [MetadataDumpSection] {
        if asset.mediaType == .video {
            var sections: [MetadataDumpSection] = [assetSection(asset)]
            sections.append(contentsOf: resourceSections(asset))
            sections.append(contentsOf: await videoSections(asset))
            sections.append(locationSection(asset))
            return sections.filter { !$0.rows.isEmpty }
        }
        // Photo: curated useful sections first, then everything else in "Other".
        let properties = await imageProperties(asset)
        let (make, model) = makeModel(from: properties)
        let shutter = await shutterCount(asset, make: make, model: model)
        var sections = photoSections(asset: asset, properties: properties, shutterCount: shutter)
        sections.append(contentsOf: resourceSections(asset))
        return sections.filter { !$0.rows.isEmpty }
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

    private static func locationSection(_ asset: PHAsset) -> MetadataDumpSection {
        guard let location = asset.location else { return section("Location", from: []) }
        return section("Location", from: [
            ("Coordinate", String(format: "%.6f, %.6f", location.coordinate.latitude, location.coordinate.longitude)),
            ("Altitude", String(format: "%.1f m", location.altitude)),
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

    // MARK: Image (ImageIO) — curated sections

    /// Splits the raw ImageIO property tree into curated, human-useful sections
    /// (Resolution / Camera / Exposure / Software / Date / Shutter Count /
    /// Location) and dumps everything not surfaced into "Other" (grouped by its
    /// source block), so nothing is lost.
    private static func photoSections(
        asset: PHAsset,
        properties: [CFString: Any]?,
        shutterCount: Int?
    ) -> [MetadataDumpSection] {
        let props = properties ?? [:]
        let exif = nestedDict(props, kCGImagePropertyExifDictionary)
        let tiff = nestedDict(props, kCGImagePropertyTIFFDictionary)
        let aux = nestedDict(props, kCGImagePropertyExifAuxDictionary)

        // Tracks which (block, key) pairs a curated section consumed so "Other"
        // doesn't repeat them.
        var consumed = Set<String>()
        func take(_ block: String, _ dict: [String: Any], _ key: CFString) -> String? {
            guard let value = dict[key as String], let string = stringify(value) else { return nil }
            consumed.insert("\(block).\(key as String)")
            return string
        }
        // Top-level keys live in the "Image" block for Other purposes.
        func takeTop(_ key: CFString) -> Any? {
            guard let value = props[key] else { return nil }
            consumed.insert("Image.\(key as String)")
            return value
        }

        // Resolution.
        var resolution: [(String, String?)] = []
        let pixelWidth = (takeTop(kCGImagePropertyPixelWidth) as? NSNumber)?.intValue ?? asset.pixelWidth
        let pixelHeight = (takeTop(kCGImagePropertyPixelHeight) as? NSNumber)?.intValue ?? asset.pixelHeight
        if pixelWidth > 0, pixelHeight > 0 {
            resolution.append(("Dimensions", "\(pixelWidth) × \(pixelHeight)"))
            resolution.append(("Megapixels", FormatUtils.megapixels(Double(pixelWidth * pixelHeight) / 1_000_000)))
        }
        if let dpi = (takeTop(kCGImagePropertyDPIWidth) as? NSNumber)?.doubleValue, dpi > 0 {
            resolution.append(("DPI", String(format: "%.0f", dpi)))
        }
        if let orientation = takeTop(kCGImagePropertyOrientation).flatMap({ stringify($0) }) {
            resolution.append(("Orientation", orientation))
        }

        // Camera.
        let camera: [(String, String?)] = [
            ("Make", take("TIFF", tiff, kCGImagePropertyTIFFMake)),
            ("Model", take("TIFF", tiff, kCGImagePropertyTIFFModel)),
            ("Lens Make", take("Exif", exif, kCGImagePropertyExifLensMake)),
            ("Lens Model", take("Exif", exif, kCGImagePropertyExifLensModel)
                ?? take("ExifAux", aux, "LensModel" as CFString)),
            ("Lens", take("Exif", exif, kCGImagePropertyExifLensSpecification)),
            ("Body Serial", take("Exif", exif, kCGImagePropertyExifBodySerialNumber)),
            ("Lens Serial", take("Exif", exif, kCGImagePropertyExifLensSerialNumber)),
        ]

        // Exposure (formatted where we have a nice helper).
        func double(_ dict: [String: Any], _ block: String, _ key: CFString) -> Double? {
            guard let number = dict[key as String] as? NSNumber else { return nil }
            consumed.insert("\(block).\(key as String)")
            return number.doubleValue
        }
        let isoValue: Int? = {
            guard let value = exif[kCGImagePropertyExifISOSpeedRatings as String] else { return nil }
            consumed.insert("Exif.\(kCGImagePropertyExifISOSpeedRatings as String)")
            if let array = value as? [NSNumber] { return array.first?.intValue }
            return (value as? NSNumber)?.intValue
        }()
        let exposure: [(String, String?)] = [
            ("ISO", isoValue.flatMap { FormatUtils.iso($0) }),
            ("Aperture", double(exif, "Exif", kCGImagePropertyExifFNumber).flatMap { FormatUtils.aperture($0) }),
            ("Shutter Speed", double(exif, "Exif", kCGImagePropertyExifExposureTime).flatMap { FormatUtils.shutterSpeed($0) }),
            ("Focal Length", double(exif, "Exif", kCGImagePropertyExifFocalLength).flatMap { FormatUtils.focalLength($0) }),
            ("Focal Length (35mm)", double(exif, "Exif", kCGImagePropertyExifFocalLenIn35mmFilm).flatMap { FormatUtils.focalLength($0) }),
            ("Exposure Bias", take("Exif", exif, kCGImagePropertyExifExposureBiasValue).map { "\($0) EV" }),
            ("Exposure Program", take("Exif", exif, kCGImagePropertyExifExposureProgram)),
            ("Metering Mode", take("Exif", exif, kCGImagePropertyExifMeteringMode)),
            ("Flash", take("Exif", exif, kCGImagePropertyExifFlash)),
            ("White Balance", take("Exif", exif, kCGImagePropertyExifWhiteBalance)),
        ]

        // Software / iOS.
        let software: [(String, String?)] = [
            ("Software", take("TIFF", tiff, kCGImagePropertyTIFFSoftware)),
            ("Host", take("TIFF", tiff, kCGImagePropertyTIFFHostComputer)),
        ]

        // Date.
        let date: [(String, String?)] = [
            ("Date Taken", take("Exif", exif, kCGImagePropertyExifDateTimeOriginal)),
            ("Date Digitized", take("Exif", exif, kCGImagePropertyExifDateTimeDigitized)),
            ("File Date", take("TIFF", tiff, kCGImagePropertyTIFFDateTime)),
            ("Time Zone", take("Exif", exif, "OffsetTimeOriginal" as CFString)),
            ("Sub-second", take("Exif", exif, kCGImagePropertyExifSubsecTimeOriginal)),
        ]

        var sections: [MetadataDumpSection] = [
            section("Resolution", from: resolution),
            section("Camera", from: camera),
            section("Exposure", from: exposure),
            section("Software", from: software),
            section("Date", from: date),
        ]
        if let shutterCount {
            sections.append(section("Shutter Count", from: [("Actuations", "\(shutterCount)")]))
        }
        sections.append(locationSection(asset))
        sections.append(contentsOf: otherSections(props, consumed: consumed))
        return sections
    }

    /// Everything the curated sections didn't consume, grouped by its original
    /// ImageIO block name (top-level → "Image").
    private static func otherSections(_ props: [CFString: Any], consumed: Set<String>) -> [MetadataDumpSection] {
        var top: [(String, String?)] = []
        var nested: [MetadataDumpSection] = []
        for (key, value) in props {
            let name = key as String
            if let dict = asStringDict(value) {
                let rows = dict.compactMap { pair -> (String, String?)? in
                    consumed.contains("\(name).\(pair.key)") ? nil : (pair.key, stringify(pair.value))
                }
                nested.append(section(name, from: rows))
            } else if !consumed.contains("Image.\(name)") {
                top.append((name, stringify(value)))
            }
        }
        return [section("Other", from: top)] + nested
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
    private static func shutterCount(_ asset: PHAsset, make: String?, model: String?) async -> Int? {
        // Vendors we can't read from a file (or no camera at all) — skip the
        // original-bytes fetch entirely.
        guard let make, MakerNoteParser.isSupportedVendor(make) else { return nil }
        guard let data = await originalPhotoData(asset), !data.isEmpty else { return nil }
        return MakerNoteParser.shutterCount(from: data, make: make, model: model)
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
            // The handlers run on an arbitrary queue; guard shared state with a
            // lock and resume the continuation exactly once (matching
            // `imageProperties`). `buffer`/`finished` live inside the lock state.
            let state = OSAllocatedUnfairLock(initialState: (buffer: Data(), finished: false))
            _ = PHAssetResourceManager.default().requestData(for: resource, options: options) { chunk in
                let done = state.withLock { s -> Data? in
                    guard !s.finished else { return nil }
                    s.buffer.append(chunk)
                    guard s.buffer.count >= maxBytes else { return nil }
                    s.finished = true
                    return s.buffer
                }
                if let done { continuation.resume(returning: done) }
            } completionHandler: { _ in
                // Outer nil → already resumed (skip); inner value → resume now.
                let result: Data?? = state.withLock { s in
                    if s.finished { return Data??.none }
                    s.finished = true
                    return Data??.some(s.buffer.isEmpty ? nil : s.buffer)
                }
                if let inner = result { continuation.resume(returning: inner) }
            }
        }
    }


    /// Full ImageIO property dictionary from the on-device rendition (no
    /// network; the downscaled derivative keeps the intact metadata block).
    private static func imageProperties(_ asset: PHAsset) async -> [CFString: Any]? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
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
