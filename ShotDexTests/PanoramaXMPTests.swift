import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ShotDex
@testable import ShotDexKit

/// FS-14 §7 — a stitched panorama stays a panorama after it leaves the app.
/// The fact travels in the file, in XMP, and the indexer reads it back.
struct PanoramaXMPTests {

    /// A small JPEG with EXIF, optionally carrying ShotDex's panorama tag.
    private func makeFile(taggedAsPanorama: Bool) throws -> URL {
        let width = 32, height = 16
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("panorama-xmp-\(UUID().uuidString).jpg")
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ))
        // EXIF as well as the tag: the reader only accepts a parse once an
        // EXIF or TIFF section is present, so a tag-only file would never
        // reach the panorama check.
        let properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Canon",
                kCGImagePropertyTIFFModel: "EOS R6",
            ] as CFDictionary,
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifFocalLength: 24,
            ] as CFDictionary,
        ]
        if taggedAsPanorama {
            let metadata = try #require(PanoramaXMP.makeMetadata(projection: "spherical", frameCount: 6))
            CGImageDestinationAddImageAndMetadata(destination, image, metadata, properties as CFDictionary)
        } else {
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    @Test func aStitchedFileIsRecognisedByItsTag() throws {
        let url = try makeFile(taggedAsPanorama: true)
        defer { try? FileManager.default.removeItem(at: url) }

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(PanoramaXMP.isStitchedPanorama(source))

        guard case .success(let exif) = ExifReader.readExif(fromImageAt: url) else {
            Issue.record("the file should read as EXIF")
            return
        }
        #expect(exif.hasPanoramaTag)
        // The ordinary EXIF still comes through — the tag is an addition, not
        // a replacement.
        #expect(exif.model == "EOS R6")
    }

    @Test func anOrdinaryPhotoCarriesNoTag() throws {
        let url = try makeFile(taggedAsPanorama: false)
        defer { try? FileManager.default.removeItem(at: url) }

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(!PanoramaXMP.isStitchedPanorama(source))

        guard case .success(let exif) = ExifReader.readExif(fromImageAt: url) else {
            Issue.record("the file should read as EXIF")
            return
        }
        #expect(!exif.hasPanoramaTag)
    }
}
