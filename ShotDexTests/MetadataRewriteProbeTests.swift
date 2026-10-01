import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

/// FS-08.06 plan task 2 — a measurement, not a feature test. It writes photo A
/// as JPEG, HEIC, PNG and TIFF, rewrites each file the ways the plan weighed,
/// and prints what survived. The table it prints is what spec §8 quotes, run
/// on iOS 26.5 and 18.6. The only assertions are the facts the rest of the
/// plan stands on: a lossless copy keeps every pixel, the location levels lose
/// the coordinate, and a re-encode does not keep the pixels.
@Suite(.serialized)
struct MetadataRewriteProbeTests {

    enum Strategy: String, CaseIterable {
        /// What `PhotoShareSheet.stripLocation` did until FS-08.06.
        case reencodeNoLocation = "AddImageFromSource · No Location"
        case copyNoLocation = "CopyImageSource · No Location"
        /// New metadata of only the keepers, XMP excluded.
        case copyNoMetadataExcludeXMP = "CopyImageSource · No Metadata · keepers + ExcludeXMP"
        /// New metadata of only the keepers, XMP allowed.
        case copyNoMetadataKeepers = "CopyImageSource · No Metadata · keepers"
        /// The source's metadata with every non-keeper tag removed.
        case copyNoMetadataPruned = "CopyImageSource · No Metadata · source pruned"
        /// Pruned, but the image-structure EXIF tags kept, in case an empty
        /// EXIF block is what makes HEIC fall back to the source's.
        case copyNoMetadataPrunedKeepStructure = "CopyImageSource · No Metadata · pruned, structure kept"
        /// Decoded and written again with only the keepers — lossless only
        /// for lossless formats.
        case reencodeNoMetadata = "AddImage decoded · No Metadata"
    }

    static let keepers: Set<String> = [
        "tiff:Orientation", "tiff:Artist", "tiff:Copyright", "dc:creator", "dc:rights",
    ]

    static func isLocation(_ path: String) -> Bool {
        let name = path.split(separator: ":").last.map(String.init) ?? path
        if path.hasPrefix("exif:") && (name.hasPrefix("GPS") || name == "SubjectLocation") { return true }
        return [
            "photoshop:City", "photoshop:State", "photoshop:Country",
            "Iptc4xmpCore:Location", "Iptc4xmpCore:CountryCode",
            "Iptc4xmpExt:LocationCreated", "Iptc4xmpExt:LocationShown",
        ].contains(path)
    }

    static func topLevelPaths(_ metadata: CGImageMetadata) -> [String] {
        var paths: [String] = []
        CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, nil) { path, _ in
            paths.append(path as String); return true
        }
        return paths
    }

    static func rewrite(_ url: URL, _ strategy: Strategy, type: UTType, folder: URL) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let output = folder.appendingPathComponent("\(strategy.hashValue)-\(url.lastPathComponent)")
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil)
        else { return nil }

        if strategy == .reencodeNoLocation {
            guard var updated = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
            updated[kCGImagePropertyGPSDictionary] = kCFNull
            if var iptc = updated[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
                for key in [kCGImagePropertyIPTCSubLocation, kCGImagePropertyIPTCCity,
                            kCGImagePropertyIPTCProvinceState, kCGImagePropertyIPTCCountryPrimaryLocationName] {
                    iptc[key] = kCFNull
                }
                updated[kCGImagePropertyIPTCDictionary] = iptc
            }
            CGImageDestinationAddImageFromSource(destination, source, 0, updated as CFDictionary)
            return CGImageDestinationFinalize(destination) ? output : nil
        }

        if strategy == .reencodeNoMetadata {
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            let keep: [CFString: Any] = [
                kCGImagePropertyOrientation: MetadataFixture.orientation,
                kCGImagePropertyTIFFDictionary: [
                    kCGImagePropertyTIFFArtist: MetadataFixture.artist,
                    kCGImagePropertyTIFFCopyright: MetadataFixture.copyright,
                    kCGImagePropertyTIFFOrientation: MetadataFixture.orientation,
                ],
            ]
            CGImageDestinationAddImage(destination, image, keep as CFDictionary)
            return CGImageDestinationFinalize(destination) ? output : nil
        }

        let existing = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
        let metadata: CGMutableImageMetadata
        var options: [CFString: Any] = [kCGImageDestinationMergeMetadata: false, kCGImageMetadataShouldExcludeGPS: true]
        switch strategy {
        case .reencodeNoLocation, .reencodeNoMetadata:
            return nil
        case .copyNoLocation, .copyNoMetadataPruned, .copyNoMetadataPrunedKeepStructure:
            guard let existing, let copy = CGImageMetadataCreateMutableCopy(existing) else { return nil }
            metadata = copy
            for path in topLevelPaths(copy) {
                let structure: Set<String> = ["exif:PixelXDimension", "exif:PixelYDimension", "exif:ColorSpace"]
                let drop = switch strategy {
                case .copyNoLocation: isLocation(path)
                case .copyNoMetadataPrunedKeepStructure: !keepers.contains(path) && !structure.contains(path)
                default: !keepers.contains(path)
                }
                if drop { CGImageMetadataRemoveTagWithPath(copy, nil, path as CFString) }
            }
        case .copyNoMetadataExcludeXMP, .copyNoMetadataKeepers:
            metadata = CGImageMetadataCreateMutable()
            if let existing {
                for path in keepers {
                    if let tag = CGImageMetadataCopyTagWithPath(existing, nil, path as CFString) {
                        CGImageMetadataSetTagWithPath(metadata, nil, path as CFString, tag)
                    }
                }
            }
            if strategy == .copyNoMetadataExcludeXMP { options[kCGImageMetadataShouldExcludeXMP] = true }
        }
        options[kCGImageDestinationMetadata] = metadata
        return CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, nil) ? output : nil
    }

    struct Reading: CustomStringConvertible {
        var bytes = 0
        var samePixels = false
        var gps = false, gpsInXMP = false, cityIPTC = false, cityXMP = false, placeXMP = false
        var date = false, make = false, iso = false, makerApple = false, rating = false
        var artist = false, copyright = false, orientation = false, profile = false
        var gainMap: Bool?, depth: Bool?

        var description: String {
            func mark(_ value: Bool) -> String { value ? "yes" : "—" }
            var cells = [
                "\(bytes)", mark(samePixels), mark(gps), mark(gpsInXMP), mark(cityIPTC), mark(cityXMP), mark(placeXMP),
                mark(date), mark(make), mark(iso), mark(makerApple), mark(rating), mark(artist), mark(copyright),
                mark(orientation), mark(profile),
            ]
            cells.append(gainMap.map(mark) ?? "n/a")
            cells.append(depth.map(mark) ?? "n/a")
            return cells.joined(separator: " | ")
        }
    }

    static func read(_ url: URL, original: URL, type: UTType) -> Reading {
        let props = MetadataFixture.properties(of: url)
        let xmp = MetadataFixture.xmpPaths(of: url)
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
        var reading = Reading()
        reading.bytes = (try? Data(contentsOf: url).count) ?? 0
        reading.samePixels = MetadataFixture.pixels(of: url) == MetadataFixture.pixels(of: original)
        reading.gps = props[kCGImagePropertyGPSDictionary] != nil
        reading.gpsInXMP = xmp.contains { $0.hasPrefix("exif:GPS") }
        reading.cityIPTC = iptc[kCGImagePropertyIPTCCity] != nil
        reading.cityXMP = xmp.contains("photoshop:City")
        reading.placeXMP = xmp.contains("Iptc4xmpCore:Location") || xmp.contains("photoshop:Country")
        reading.date = exif[kCGImagePropertyExifDateTimeOriginal] != nil || xmp.contains("exif:DateTimeOriginal")
        reading.make = tiff[kCGImagePropertyTIFFMake] != nil
        reading.iso = exif[kCGImagePropertyExifISOSpeedRatings] != nil
        reading.makerApple = props[kCGImagePropertyMakerAppleDictionary] != nil
        reading.rating = iptc[kCGImagePropertyIPTCStarRating] != nil || xmp.contains("xmp:Rating")
        reading.artist = tiff[kCGImagePropertyTIFFArtist] != nil || xmp.contains("dc:creator")
        reading.copyright = tiff[kCGImagePropertyTIFFCopyright] != nil || xmp.contains("dc:rights")
        reading.orientation = props[kCGImagePropertyOrientation] as? Int == MetadataFixture.orientation
        reading.profile = MetadataFixture.hasColorProfile(url)
        if type == .heic {
            reading.gainMap = MetadataFixture.hasAuxiliary(kCGImageAuxiliaryDataTypeHDRGainMap, in: url)
            reading.depth = MetadataFixture.hasAuxiliary(kCGImageAuxiliaryDataTypeDisparity, in: url)
        }
        return reading
    }

    static let header = "file · strategy | bytes | same pixels | GPS | GPS in XMP | IPTC City | XMP City | XMP place | "
        + "date | Make | ISO | MakerApple | Rating | Artist | Copyright | orientation 6 | P3 | gain map | depth"

    @Test(arguments: [UTType.jpeg, .heic, .png, .tiff])
    func matrix(type: UTType) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        var options = MetadataFixture.Options()
        var lines = ["\n[probe \(ProcessInfo.processInfo.operatingSystemVersionString)] \(Self.header)"]
        if type == .heic {
            // The auxiliary images go in one at a time, so a fixture ImageIO
            // refuses to write says which one it refused.
            for (gainMap, depth) in [(true, true), (true, false), (false, true)] {
                options.gainMap = gainMap
                options.depth = depth
                if (try? MetadataFixture.encode(type, options: options)) != nil { break }
                lines.append("heic · fixture with gain map \(gainMap), depth \(depth) | not available (ImageIO refused the depth map when this was measured)")
                options.gainMap = false
                options.depth = false
            }
        }
        let original = try MetadataFixture.write(type, options: options, in: folder)

        let source = Self.read(original, original: original, type: type)
        lines.append("\(type.preferredFilenameExtension ?? "?") · original | \(source)")
        #expect(source.gps && source.cityXMP && source.gpsInXMP, "fixture carries the location twice")

        for strategy in Strategy.allCases {
            // A re-encode of a HEIC runs the simulator's HEVC encoder, which
            // deadlocks when another encode overlaps it in a full parallel
            // run (see MetadataFixture.encode). Measured once on 26.5 and
            // 18.6 (spec §8): pixels change and the gain map goes.
            if type == .heic && (strategy == .reencodeNoLocation || strategy == .reencodeNoMetadata) {
                lines.append("heic · \(strategy.rawValue) | not run in the suite (spec §8: pixels change, gain map lost)")
                continue
            }
            guard let output = Self.rewrite(original, strategy, type: type, folder: folder) else {
                lines.append("\(type.preferredFilenameExtension ?? "?") · \(strategy.rawValue) | FAILED")
                continue
            }
            let reading = Self.read(output, original: original, type: type)
            lines.append("\(type.preferredFilenameExtension ?? "?") · \(strategy.rawValue) | \(reading)")
            let lossy = type == .jpeg || type == .heic
            switch strategy {
            case .reencodeNoLocation, .reencodeNoMetadata:
                // Lossy formats change; lossless ones come back pixel for pixel.
                #expect(reading.samePixels == !lossy)
                #expect(!reading.gps)
            case .copyNoLocation:
                #expect(reading.samePixels)
                if lossy {
                    #expect(!reading.gps && !reading.gpsInXMP && !reading.cityIPTC && !reading.cityXMP)
                    #expect(reading.make && reading.iso && reading.date)
                }
            default:
                #expect(reading.samePixels)
            }
        }
        print(lines.joined(separator: "\n"))
    }
}
