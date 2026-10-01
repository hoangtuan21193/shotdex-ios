import Foundation
import ImageIO

/// How much of a photo's metadata goes with it when it leaves the app
/// (FS-08.06 §3). One value in Settings is the default for every way out —
/// Share, Save Copy, Paste Edits, Resize, drag — and Share can change it for
/// one share.
///
/// In the kit because the renderer's `write` takes it; nothing here touches
/// SwiftUI or GRDB.
public enum MetadataLevel: String, CaseIterable, Codable, Sendable {
    /// Everything, and the original file's bytes untouched.
    case all
    /// Everything except where the photo was taken: the GPS group, the
    /// subject's position and the IPTC/XMP place names.
    case noLocation
    /// Nothing but what the picture needs to look right — orientation and
    /// colour profile — and the author's Artist and Copyright.
    case noMetadata

    /// Whether this level removes the location.
    public var removesLocation: Bool { self != .all }
}

extension MetadataLevel {
    /// The ImageIO property dictionaries a render writes, filtered by the
    /// level (spec §3) — for files that are rendered, not copied: Save Copy,
    /// Paste Edits as copies, Resize. Orientation is not decided here; the
    /// renderer writes its own.
    public func filteredProperties(_ properties: [CFString: Any]) -> [CFString: Any] {
        switch self {
        case .all:
            return properties
        case .noLocation:
            var kept = properties
            kept[kCGImagePropertyGPSDictionary] = nil
            if var exif = kept[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                exif[kCGImagePropertyExifSubjectLocation] = nil
                kept[kCGImagePropertyExifDictionary] = exif
            }
            if var iptc = kept[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
                for key in Self.iptcPlaceKeys { iptc[key] = nil }
                kept[kCGImagePropertyIPTCDictionary] = iptc
            }
            return kept
        case .noMetadata:
            // Only the author's two fields, where they were.
            var kept: [CFString: Any] = [:]
            if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                let author = tiff.filter { $0.key == kCGImagePropertyTIFFArtist || $0.key == kCGImagePropertyTIFFCopyright }
                if !author.isEmpty { kept[kCGImagePropertyTIFFDictionary] = author }
            }
            if let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
                let author = iptc.filter {
                    $0.key == kCGImagePropertyIPTCByline || $0.key == kCGImagePropertyIPTCCopyrightNotice
                }
                if !author.isEmpty { kept[kCGImagePropertyIPTCDictionary] = author }
            }
            return kept
        }
    }

    /// IPTC fields that name a place.
    static let iptcPlaceKeys: [CFString] = [
        kCGImagePropertyIPTCCity, kCGImagePropertyIPTCProvinceState,
        kCGImagePropertyIPTCCountryPrimaryLocationName, kCGImagePropertyIPTCCountryPrimaryLocationCode,
        kCGImagePropertyIPTCSubLocation,
    ]
}
