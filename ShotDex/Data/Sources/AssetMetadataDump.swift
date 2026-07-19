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
        var sections: [MetadataDumpSection] = [assetSection(asset)]
        sections.append(contentsOf: resourceSections(asset))
        if asset.mediaType == .video {
            sections.append(contentsOf: await videoSections(asset))
        } else {
            sections.append(contentsOf: await imageSections(asset))
        }
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
        if let location = asset.location {
            pairs.append(("Coordinate", String(
                format: "%.6f, %.6f",
                location.coordinate.latitude, location.coordinate.longitude
            )))
            pairs.append(("Altitude", String(format: "%.1f m", location.altitude)))
        }
        return section("Asset", from: pairs)
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

    // MARK: Image (ImageIO)

    private static func imageSections(_ asset: PHAsset) async -> [MetadataDumpSection] {
        guard let properties = await imageProperties(asset) else { return [] }
        var top: [(String, String?)] = []
        var nested: [MetadataDumpSection] = []
        for (key, value) in properties {
            let name = key as String
            if let dict = value as? [CFString: Any] {
                nested.append(section(name, from: dict.map { ($0.key as String, stringify($0.value)) }))
            } else if let dict = value as? [String: Any] {
                nested.append(section(name, from: dict.map { ($0.key, stringify($0.value)) }))
            } else {
                top.append((name, stringify(value)))
            }
        }
        var result = [section("Image", from: top)]
        result.append(contentsOf: nested)
        return result
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
