import Foundation
import ImageIO
import ShotDexKit
import UniformTypeIdentifiers

/// Writes a photo file again with less metadata, without decoding it
/// (FS-08.06 §3).
///
/// `CGImageDestinationCopyImageSource` copies the compressed image data into
/// the new file and replaces only the metadata, so the decoded pixels are the
/// original's and a HEIC keeps its HDR gain map (measured, plan task 2). The
/// old `stripLocation` went through `AddImageFromSource`, which re-encodes:
/// every JPEG and HEIC shared without location came out a generation worse.
///
/// **Never hands back the original.** A file it cannot rewrite — a RAW, a
/// corrupt photo, a format whose copy keeps the coordinate anyway — throws.
/// Every rewritten file is read back and checked before it is returned, so a
/// change in ImageIO that quietly keeps the GPS shows up as a dropped photo,
/// not as a leak. Measured on iOS 26.5 and 18.6: PNG keeps its GPS through
/// the copy, so a PNG with a location does not leave at No Location.
enum MetadataRewriter {
    enum Failure: Error, Equatable {
        /// Not an image ImageIO can open.
        case unreadable
        /// ImageIO opens it but cannot write the type — every RAW and DNG.
        case unsupportedType(String)
        /// The copy itself failed.
        case cannotWrite
        /// The copy succeeded and still carries what the level removes.
        case stillCarries([String])
    }

    /// Rewrites `source` into a new file at `destination` with only what
    /// `level` keeps. At `.all` the file is copied byte for byte.
    static func rewrite(_ source: URL, to destination: URL, level: MetadataLevel) throws {
        if level == .all {
            try FileManager.default.copyItem(at: source, to: destination)
            return
        }
        guard let image = CGImageSourceCreateWithURL(source as CFURL, nil),
              let type = CGImageSourceGetType(image),
              CGImageSourceGetCount(image) > 0
        else { throw Failure.unreadable }
        let writable = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        guard writable.contains(type as String) else { throw Failure.unsupportedType(type as String) }
        guard let output = CGImageDestinationCreateWithURL(destination as CFURL, type, 1, nil)
        else { throw Failure.cannotWrite }

        let metadata = try metadata(of: image, keeping: level)
        let options: [CFString: Any] = [
            kCGImageDestinationMetadata: metadata,
            kCGImageDestinationMergeMetadata: false,
            kCGImageMetadataShouldExcludeGPS: true,
        ]
        guard CGImageDestinationCopyImageSource(output, image, options as CFDictionary, nil) else {
            try? FileManager.default.removeItem(at: destination)
            throw Failure.cannotWrite
        }
        let left = leftovers(in: destination, level: level)
        guard left.isEmpty else {
            try? FileManager.default.removeItem(at: destination)
            throw Failure.stillCarries(left)
        }
    }

    /// The metadata the new file gets. No Location: the source's, with the
    /// place taken out. No Metadata: a new set holding only the keepers —
    /// measured, a pruned copy of the source keeps the MakerNote (plan task 2).
    private static func metadata(of image: CGImageSource, keeping level: MetadataLevel) throws -> CGImageMetadata {
        let fresh = CGImageMetadataCreateMutable()
        guard let existing = CGImageSourceCopyMetadataAtIndex(image, 0, nil) else { return fresh }
        if level == .noMetadata {
            for path in keptAtNoMetadata {
                if let tag = CGImageMetadataCopyTagWithPath(existing, nil, path as CFString) {
                    CGImageMetadataSetTagWithPath(fresh, nil, path as CFString, tag)
                }
            }
            return fresh
        }
        guard let copy = CGImageMetadataCreateMutableCopy(existing) else { throw Failure.cannotWrite }
        for path in topLevelPaths(of: copy) where removes(path, at: level) {
            CGImageMetadataRemoveTagWithPath(copy, nil, path as CFString)
        }
        return copy
    }

    /// What No Metadata keeps (spec §3): the orientation, without which the
    /// photo turns sideways, and the author's Artist and Copyright wherever
    /// they sit — TIFF, and XMP's `dc:` fields that mirror IPTC By-line and
    /// Copyright Notice. The colour profile is image data, not metadata, and
    /// the copy keeps it.
    static let keptAtNoMetadata: [String] = [
        "tiff:Orientation", "tiff:Artist", "tiff:Copyright", "dc:creator", "dc:rights",
    ]

    /// Tags that describe the image's own structure, which ImageIO writes
    /// into every file whatever it was given. They say nothing about the
    /// photographer, the camera or the place.
    static let structural: Set<String> = [
        "exif:PixelXDimension", "exif:PixelYDimension", "exif:ColorSpace",
        "tiff:XResolution", "tiff:YResolution", "tiff:ResolutionUnit",
    ]

    /// Whether `level` removes the tag at `path` (`prefix:Name`).
    static func removes(_ path: String, at level: MetadataLevel) -> Bool {
        switch level {
        case .all: false
        case .noLocation: isLocation(path)
        case .noMetadata:
            !keptAtNoMetadata.contains(path) && !structural.contains(path) && !path.hasPrefix("iio:")
        }
    }

    /// The tags that say where a photo was taken: the EXIF GPS group as XMP
    /// mirrors it, the subject's position, and the IPTC place fields (which
    /// ImageIO exposes under their XMP names).
    static func isLocation(_ path: String) -> Bool {
        guard let colon = path.firstIndex(of: ":") else { return false }
        let prefix = path[..<colon]
        let name = path[path.index(after: colon)...]
        if prefix == "exif" || prefix == "exifEX" {
            return name.hasPrefix("GPS") || name == "SubjectLocation"
        }
        return locationPaths.contains(path)
    }

    static let locationPaths: Set<String> = [
        "photoshop:City", "photoshop:State", "photoshop:Country",
        "Iptc4xmpCore:Location", "Iptc4xmpCore:CountryCode",
        "Iptc4xmpExt:LocationCreated", "Iptc4xmpExt:LocationShown",
    ]

    /// IPTC dictionary keys that name a place.
    private static let iptcLocationKeys: [CFString] = [
        kCGImagePropertyIPTCCity, kCGImagePropertyIPTCProvinceState,
        kCGImagePropertyIPTCCountryPrimaryLocationName, kCGImagePropertyIPTCCountryPrimaryLocationCode,
        kCGImagePropertyIPTCSubLocation,
    ]

    /// What the file at `url` still carries that `level` removes, by name.
    /// Empty means the file is clean.
    static func leftovers(in url: URL, level: MetadataLevel) -> [String] {
        guard level.removesLocation else { return [] }
        guard let image = CGImageSourceCreateWithURL(url as CFURL, nil) else { return ["unreadable"] }
        let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any] ?? [:]
        var found: [String] = []
        if properties[kCGImagePropertyGPSDictionary] != nil { found.append("GPS") }
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           exif[kCGImagePropertyExifSubjectLocation] != nil {
            found.append("SubjectLocation")
        }
        if let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
            found += iptcLocationKeys.filter { iptc[$0] != nil }.map { "IPTC \($0)" }
        }
        if let metadata = CGImageSourceCopyMetadataAtIndex(image, 0, nil) {
            found += topLevelPaths(of: metadata).filter { path in
                removes(path, at: level) && (level == .noMetadata || isLocation(path))
            }
        }
        if level == .noMetadata {
            // The property dictionaries too: a maker note has no XMP mirror.
            let dictionaries = properties.keys.filter { key in
                (properties[key] as? [CFString: Any])?.isEmpty == false
                    && !Self.keptDictionaries.contains(key as String)
            }
            found += dictionaries.map { "\($0)" }
            if let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
                let author: Set<String> = [
                    kCGImagePropertyIPTCByline as String, kCGImagePropertyIPTCCopyrightNotice as String,
                ]
                found += iptc.keys.map { $0 as String }.filter { !author.contains($0) }.map { "IPTC \($0)" }
            }
            if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                let kept: Set<String> = [
                    kCGImagePropertyTIFFOrientation as String, kCGImagePropertyTIFFArtist as String,
                    kCGImagePropertyTIFFCopyright as String, kCGImagePropertyTIFFXResolution as String,
                    kCGImagePropertyTIFFYResolution as String, kCGImagePropertyTIFFResolutionUnit as String,
                ]
                found += tiff.keys.map { $0 as String }.filter { !kept.contains($0) }.map { "TIFF \($0)" }
            }
            if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                let kept: Set<String> = [
                    kCGImagePropertyExifPixelXDimension as String, kCGImagePropertyExifPixelYDimension as String,
                    kCGImagePropertyExifColorSpace as String,
                ]
                found += exif.keys.map { $0 as String }.filter { !kept.contains($0) }.map { "EXIF \($0)" }
            }
        }
        return Array(Set(found)).sorted()
    }

    /// Property dictionaries No Metadata may leave in place: the ones it
    /// checks key by key below, and JFIF/format headers that carry no tags.
    private static let keptDictionaries: Set<String> = [
        kCGImagePropertyTIFFDictionary as String, kCGImagePropertyExifDictionary as String,
        kCGImagePropertyIPTCDictionary as String, kCGImagePropertyJFIFDictionary as String,
        kCGImagePropertyPNGDictionary as String, kCGImagePropertyHEIFDictionary as String,
    ]

    /// Whether the file carries a location anywhere the rewriter would remove
    /// one from.
    static func carriesLocation(_ url: URL) -> Bool {
        !leftovers(in: url, level: .noLocation).isEmpty
    }

    static func topLevelPaths(of metadata: CGImageMetadata) -> [String] {
        var paths: [String] = []
        CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, nil) { path, _ in
            paths.append(path as String)
            return true
        }
        return paths
    }
}
