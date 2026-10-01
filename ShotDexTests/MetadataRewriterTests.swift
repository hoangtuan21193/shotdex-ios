import CoreGraphics
import Foundation
import ImageIO
import ShotDexKit
import Testing
import UniformTypeIdentifiers
@testable import ShotDex

/// FS-08.06 §3 — rewriting a photo with less metadata. The promise is narrow
/// and worth pinning down: what the level removes goes, everything else
/// stays, and the picture itself is not touched.
@Suite(.serialized)
struct MetadataRewriterTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("rewriter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: folder) }

    func output(_ name: String = "out") -> URL {
        folder.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(6))")
    }

    /// AC-1: the coordinate goes — from EXIF, from XMP and from the IPTC place
    /// names — and the camera, lens, exposure, date and author stay.
    @Test(arguments: [UTType.jpeg, .heic, .tiff, .png])
    func noLocationRemovesThePlaceOnly(type: UTType) throws {
        defer { cleanUp() }
        let original = try MetadataFixture.write(type, in: folder)
        #expect(MetadataRewriter.carriesLocation(original))

        let shared = output().appendingPathExtension(original.pathExtension)
        try MetadataRewriter.rewrite(original, to: shared, level: .noLocation)

        #expect(MetadataFixture.dictionary(kCGImagePropertyGPSDictionary, of: shared) == nil)
        #expect(!MetadataRewriter.carriesLocation(shared))
        let xmp = MetadataFixture.xmpPaths(of: shared)
        #expect(!xmp.contains { $0.hasPrefix("exif:GPS") })
        #expect(!xmp.contains("photoshop:City"))

        let tiff = try #require(MetadataFixture.dictionary(kCGImagePropertyTIFFDictionary, of: shared))
        #expect(tiff[kCGImagePropertyTIFFMake] as? String == MetadataFixture.make)
        #expect(tiff[kCGImagePropertyTIFFModel] as? String == MetadataFixture.model)
        #expect(tiff[kCGImagePropertyTIFFArtist] as? String == MetadataFixture.artist)
        #expect(tiff[kCGImagePropertyTIFFCopyright] as? String == MetadataFixture.copyright)
        let exif = try #require(MetadataFixture.dictionary(kCGImagePropertyExifDictionary, of: shared))
        #expect(exif[kCGImagePropertyExifISOSpeedRatings] as? [Int] == [MetadataFixture.iso])
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] as? String == MetadataFixture.captureDate)
        #expect(exif[kCGImagePropertyExifLensModel] as? String == MetadataFixture.lens)
        #expect(MetadataFixture.properties(of: shared)[kCGImagePropertyOrientation] as? Int == MetadataFixture.orientation)
    }

    /// AC-1: the decoded pixels are the original's. The old path re-encoded
    /// every JPEG and HEIC it touched.
    @Test(arguments: [UTType.jpeg, .heic, .tiff, .png])
    func noLocationKeepsEveryPixel(type: UTType) throws {
        defer { cleanUp() }
        let original = try MetadataFixture.write(type, in: folder)
        let shared = output().appendingPathExtension(original.pathExtension)
        try MetadataRewriter.rewrite(original, to: shared, level: .noLocation)

        let before = try #require(MetadataFixture.pixels(of: original))
        #expect(MetadataFixture.pixels(of: shared) == before)
        #expect(MetadataFixture.hasColorProfile(shared))
    }

    /// Spec §8: a HEIC keeps its HDR gain map through the rewrite.
    @Test func noLocationKeepsTheGainMap() throws {
        defer { cleanUp() }
        var options = MetadataFixture.Options()
        options.gainMap = true
        let original = try MetadataFixture.write(.heic, options: options, in: folder)
        #expect(MetadataFixture.hasAuxiliary(kCGImageAuxiliaryDataTypeHDRGainMap, in: original))

        let shared = output().appendingPathExtension("heic")
        try MetadataRewriter.rewrite(original, to: shared, level: .noLocation)
        #expect(MetadataFixture.hasAuxiliary(kCGImageAuxiliaryDataTypeHDRGainMap, in: shared))
    }

    /// Spec §5: a file that cannot be rewritten throws, and nothing is left at
    /// the destination for a caller to hand over by mistake: a corrupt file,
    /// and a RAW, which ImageIO cannot write.
    @Test func failedRewriteNeverReturnsOriginal() throws {
        defer { cleanUp() }
        let garbage = folder.appendingPathComponent("broken.jpg")
        try Data([0x00, 0x01, 0x02]).write(to: garbage)
        let first = output()
        #expect(throws: MetadataRewriter.Failure.unreadable) {
            try MetadataRewriter.rewrite(garbage, to: first, level: .noLocation)
        }
        #expect(!FileManager.default.fileExists(atPath: first.path))

        if let dng = RAWFixtures.available(RAWFixtures.dji) {
            let second = output().appendingPathExtension("dng")
            #expect(throws: MetadataRewriter.Failure.self) {
                try MetadataRewriter.rewrite(dng, to: second, level: .noLocation)
            }
            #expect(!FileManager.default.fileExists(atPath: second.path))
        }
    }

    /// FS-08.06 §3 (decided 2026-10-01): PNG and TIFF are written again —
    /// ImageIO's copy keeps a PNG's GPS — and come back pixel for pixel at
    /// No Metadata too, keeping the orientation, the profile and the author.
    @Test(arguments: [UTType.png, .tiff])
    func losslessFormatsAreWrittenAgainPixelForPixel(type: UTType) throws {
        defer { cleanUp() }
        let original = try MetadataFixture.write(type, in: folder)
        let shared = output().appendingPathExtension(original.pathExtension)
        try MetadataRewriter.rewrite(original, to: shared, level: .noMetadata)

        #expect(MetadataFixture.pixels(of: shared) == MetadataFixture.pixels(of: original))
        #expect(MetadataRewriter.leftovers(in: shared, level: .noMetadata).isEmpty)
        let props = MetadataFixture.properties(of: shared)
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        #expect(tiff[kCGImagePropertyTIFFMake] == nil)
        #expect(tiff[kCGImagePropertyTIFFArtist] as? String == MetadataFixture.artist)
        #expect(tiff[kCGImagePropertyTIFFCopyright] as? String == MetadataFixture.copyright)
        #expect(props[kCGImagePropertyOrientation] as? Int == MetadataFixture.orientation)
        #expect(MetadataFixture.hasColorProfile(shared))
    }

    /// All Metadata copies the file, byte for byte.
    @Test func allMetadataCopiesTheBytes() throws {
        defer { cleanUp() }
        let original = try MetadataFixture.write(.jpeg, in: folder)
        let shared = output().appendingPathExtension("jpg")
        try MetadataRewriter.rewrite(original, to: shared, level: .all)
        #expect(try Data(contentsOf: shared) == Data(contentsOf: original))
    }

    @Test func locationTagsAreRecognised() {
        for path in ["exif:GPSLatitude", "exif:GPSAltitudeRef", "exif:SubjectLocation", "photoshop:City",
                     "Iptc4xmpCore:Location", "Iptc4xmpExt:LocationShown"] {
            #expect(MetadataRewriter.isLocation(path), "\(path)")
        }
        for path in ["exif:ISOSpeedRatings", "tiff:Make", "xmp:Rating", "dc:creator", "exif:DateTimeOriginal"] {
            #expect(!MetadataRewriter.isLocation(path), "\(path)")
        }
    }

    /// AC-4: a Lightroom JPEG repeats the coordinate in XMP and names the
    /// place in IPTC and XMP. No Location removes all of it and keeps the
    /// rating.
    @Test func lightroomXMP() throws {
        defer { cleanUp() }
        let original = try MetadataFixture.lightroomJPEG(in: folder)
        let before = MetadataFixture.xmpPaths(of: original)
        #expect(before.contains("photoshop:City"))
        #expect(before.contains("xmp:Rating"))
        #expect(before.contains { $0.hasPrefix("Iptc4xmpExt:LocationCreated") }, "\(before.sorted())")
        #expect(MetadataFixture.dictionary(kCGImagePropertyGPSDictionary, of: original) != nil)

        let shared = output().appendingPathExtension("jpg")
        try MetadataRewriter.rewrite(original, to: shared, level: .noLocation)

        #expect(MetadataFixture.dictionary(kCGImagePropertyGPSDictionary, of: shared) == nil)
        let after = MetadataFixture.xmpPaths(of: shared)
        #expect(!after.contains { $0.hasPrefix("exif:GPS") }, "\(after.sorted())")
        for place in ["photoshop:City", "photoshop:State", "photoshop:Country", "Iptc4xmpCore:Location", "Iptc4xmpCore:CountryCode"] {
            #expect(!after.contains(place), "\(place)")
        }
        #expect(!after.contains { $0.hasPrefix("Iptc4xmpExt:Location") })
        let iptc = MetadataFixture.dictionary(kCGImagePropertyIPTCDictionary, of: shared) ?? [:]
        #expect(iptc[kCGImagePropertyIPTCCity] == nil)

        // The packet's own bytes: no coordinate or place survives anywhere in
        // the file, whatever ImageIO's reader chooses to surface.
        let text = String(decoding: try Data(contentsOf: shared), as: UTF8.self)
        #expect(!text.contains(MetadataFixture.city))
        #expect(!text.contains("46.614N"))
        #expect(!text.contains("District 1"))

        #expect(after.contains("xmp:Rating"))
        let tiff = try #require(MetadataFixture.dictionary(kCGImagePropertyTIFFDictionary, of: shared))
        #expect(tiff[kCGImagePropertyTIFFMake] as? String == MetadataFixture.make)
        #expect(MetadataFixture.pixels(of: shared) == MetadataFixture.pixels(of: original))
    }

    /// AC-2, the file: No Metadata leaves no GPS, camera, exposure, capture
    /// date or maker note, and keeps the orientation, the colour profile, the
    /// Artist and the Copyright — and every pixel.
    @Test func noMetadataJPEG() throws {
        defer { cleanUp() }
        let original = try MetadataFixture.write(.jpeg, in: folder)
        let shared = output().appendingPathExtension("jpg")
        try MetadataRewriter.rewrite(original, to: shared, level: .noMetadata)

        let props = MetadataFixture.properties(of: shared)
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
        #expect(props[kCGImagePropertyMakerAppleDictionary] == nil)
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        #expect(tiff[kCGImagePropertyTIFFMake] == nil)
        #expect(tiff[kCGImagePropertyTIFFModel] == nil)
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        #expect(exif[kCGImagePropertyExifISOSpeedRatings] == nil)
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] == nil)
        #expect(exif[kCGImagePropertyExifLensModel] == nil)
        let xmp = MetadataFixture.xmpPaths(of: shared)
        #expect(!xmp.contains("photoshop:City"))
        #expect(!xmp.contains("xmp:Rating"))
        #expect(!xmp.contains { $0.hasPrefix("exif:DateTime") })

        #expect(props[kCGImagePropertyOrientation] as? Int == MetadataFixture.orientation)
        #expect(MetadataFixture.hasColorProfile(shared))
        #expect(tiff[kCGImagePropertyTIFFArtist] as? String == MetadataFixture.artist || xmp.contains("dc:creator"))
        #expect(tiff[kCGImagePropertyTIFFCopyright] as? String == MetadataFixture.copyright || xmp.contains("dc:rights"))
        #expect(MetadataFixture.pixels(of: shared) == MetadataFixture.pixels(of: original))
        #expect(MetadataRewriter.leftovers(in: shared, level: .noMetadata).isEmpty)
    }

    /// AC-2, HEIC (decided 2026-10-01): no lossless copy clears a HEIC's
    /// capture date, City and Rating, so at No Metadata it leaves as a
    /// maximum-quality JPEG — clean, upright, in its colour profile, with
    /// the Artist and Copyright.
    @Test func noMetadataHEICBecomesJPEG() throws {
        defer { cleanUp() }
        let original = try MetadataFixture.write(.heic, in: folder)
        #expect(MetadataRewriter.convertsToJPEG(UTType.heic.identifier, at: .noMetadata))
        #expect(!MetadataRewriter.convertsToJPEG(UTType.heic.identifier, at: .noLocation))
        #expect(!MetadataRewriter.convertsToJPEG(UTType.jpeg.identifier, at: .noMetadata))

        let shared = output().appendingPathExtension("jpg")
        try MetadataRewriter.rewrite(original, to: shared, level: .noMetadata)

        let source = try #require(CGImageSourceCreateWithURL(shared as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        #expect(MetadataRewriter.leftovers(in: shared, level: .noMetadata).isEmpty)
        let props = MetadataFixture.properties(of: shared)
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] == nil)
        #expect(exif[kCGImagePropertyExifISOSpeedRatings] == nil)
        let xmp = MetadataFixture.xmpPaths(of: shared)
        #expect(!xmp.contains("photoshop:City"))
        #expect(!xmp.contains("xmp:Rating"))
        #expect(!xmp.contains { $0.hasPrefix("exif:DateTime") })
        let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
        #expect(iptc[kCGImagePropertyIPTCCity] == nil)
        #expect(iptc[kCGImagePropertyIPTCStarRating] == nil)
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        #expect(tiff[kCGImagePropertyTIFFMake] == nil)
        #expect(tiff[kCGImagePropertyTIFFArtist] as? String == MetadataFixture.artist)
        #expect(tiff[kCGImagePropertyTIFFCopyright] as? String == MetadataFixture.copyright)
        #expect(props[kCGImagePropertyOrientation] as? Int == MetadataFixture.orientation)
        #expect(MetadataFixture.hasColorProfile(shared))
        #expect(props[kCGImagePropertyPixelWidth] as? Int == MetadataFixture.Options().width)
    }
}
