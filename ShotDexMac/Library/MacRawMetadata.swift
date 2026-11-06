import Foundation
import ImageIO
import Photos

/// A photo file's own metadata, as ImageIO reads it — Get Info's Metering
/// and White Balance, and Show All Raw Metadata (FS-18.02 §8). Reads the
/// header only, never decodes the picture, and always off the main actor.
enum MacRawMetadata {
    struct Entry: Hashable, Sendable {
        let key: String
        let value: String
    }

    /// The file of a folder or drive copy.
    static func properties(of url: URL) async -> [String: Any]? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
            else { return nil }
            return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        }.value
    }

    /// A Photos asset's original, when it is on this Mac — never downloaded
    /// just to be read.
    static func properties(ofAsset id: String) async -> [String: Any]? {
        guard let asset = await Task.detached(priority: .userInitiated, operation: { PhotoLibraryService.fetchAssets(ids: [id]).first }).value
        else { return nil }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.version = .original
        let data: Data? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data else { return nil }
        return await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
            else { return nil }
            return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        }.value
    }

    /// Every value as "{Exif}.MeteringMode = 5", sorted by key.
    static func entries(_ properties: [String: Any]) -> [Entry] {
        var out: [Entry] = []
        func walk(_ value: Any, _ path: String) {
            if let dictionary = value as? [String: Any] {
                for (key, child) in dictionary { walk(child, path.isEmpty ? key : "\(path).\(key)") }
            } else if let array = value as? [Any] {
                out.append(Entry(key: path, value: array.map { "\($0)" }.joined(separator: ", ")))
            } else {
                out.append(Entry(key: path, value: "\(value)"))
            }
        }
        walk(properties, "")
        return out.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }

    /// EXIF MeteringMode in words (EXIF 2.3 table).
    static func metering(_ properties: [String: Any]) -> String? {
        guard let mode = (properties[kCGImagePropertyExifDictionary as String] as? [String: Any])?[kCGImagePropertyExifMeteringMode as String] as? Int
        else { return nil }
        return switch mode {
        case 1: String(localized: "Average", comment: "EXIF metering mode")
        case 2: String(localized: "Center-weighted", comment: "EXIF metering mode")
        case 3: String(localized: "Spot", comment: "EXIF metering mode")
        case 4: String(localized: "Multi-spot", comment: "EXIF metering mode")
        case 5: String(localized: "Multi-segment", comment: "EXIF metering mode (pattern)")
        case 6: String(localized: "Partial", comment: "EXIF metering mode")
        default: nil
        }
    }

    static func whiteBalance(_ properties: [String: Any]) -> String? {
        guard let mode = (properties[kCGImagePropertyExifDictionary as String] as? [String: Any])?[kCGImagePropertyExifWhiteBalance as String] as? Int
        else { return nil }
        return mode == 0 ? String(localized: "Auto", comment: "EXIF white balance") : String(localized: "Manual", comment: "EXIF white balance")
    }
}
