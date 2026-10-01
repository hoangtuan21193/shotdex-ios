import CryptoKit
import Foundation
import ImageIO
import Photos
import Testing
import ShotDexKit
import UniformTypeIdentifiers
@testable import ShotDex

/// FS-08.06 — the share pipeline end to end, over fixture files instead of a
/// photo library: what the share sheet would receive, byte for byte.
@Suite(.serialized)
struct ShareExportPipelineTests {

    /// Hands out fixture files by id, the way `PhotoKitShareReader` hands out
    /// library resources.
    struct FakeReader: ShareAssetReader {
        var photos: [String: URL] = [:]
        var videos: [String: URL] = [:]

        func writePhoto(_ source: ShareSource, to url: URL) async throws {
            guard let file = photos[source.id] else { throw PhotoKitShareReader.ReadError.missing }
            try FileManager.default.copyItem(at: file, to: url)
        }

        func videoURL(for source: ShareSource) async throws -> URL {
            guard let file = videos[source.id] else { throw PhotoKitShareReader.ReadError.noVideoFile }
            return file
        }
    }

    static func sha256(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    let fixtures: URL
    let shareRoot: URL

    init() throws {
        fixtures = FileManager.default.temporaryDirectory.appendingPathComponent("share-fixtures-\(UUID().uuidString)")
        shareRoot = FileManager.default.temporaryDirectory.appendingPathComponent("share-root-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: shareRoot, withIntermediateDirectories: true)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: fixtures)
        try? FileManager.default.removeItem(at: shareRoot)
    }

    /// AC-3, first half: All Metadata hands over the original file untouched.
    @Test func allMetadataIsByteIdentical() async throws {
        defer { cleanUp() }
        let photoA = try MetadataFixture.write(.heic, in: fixtures)
        let pipeline = ShareExportPipeline(
            reader: FakeReader(photos: ["A": photoA]),
            folder: try ShareExportPipeline.makeFolder(in: shareRoot),
            level: .all
        )

        let result = await pipeline.export([ShareSource(id: "A", kind: .photo, filename: "IMG_0001.HEIC")])

        #expect(result.failed.isEmpty)
        let file = try #require(result.files.first)
        #expect(file.lastPathComponent == "IMG_0001.HEIC")
        #expect(try Self.sha256(file) == Self.sha256(photoA))
        #expect(MetadataFixture.dictionary(kCGImagePropertyGPSDictionary, of: file) != nil)
    }

    /// AC-8: a Live Photo is an image asset, shares its still, and the still
    /// is the photo resource — never the paired video.
    @Test func livePhotoSharesOneStill() async throws {
        defer { cleanUp() }
        #expect(ShareSource.kind(mediaType: .image) == .photo)
        #expect(ShareSource.sharedResourceType(among: [.photo, .pairedVideo]) == .photo)
        #expect(ShareSource.sharedResourceType(among: [.photo, .pairedVideo, .fullSizePhoto, .fullSizePairedVideo, .adjustmentData]) == .fullSizePhoto)
        #expect(ShareSource.sharedResourceType(among: [.pairedVideo]) == nil)

        let still = try MetadataFixture.write(.heic, in: fixtures)
        let pipeline = ShareExportPipeline(
            reader: FakeReader(photos: ["live": still]),
            folder: try ShareExportPipeline.makeFolder(in: shareRoot),
            level: .all
        )
        let result = await pipeline.export([ShareSource(id: "live", kind: .photo, filename: "IMG_0002.HEIC")])
        #expect(result.files.count == 1)
        #expect(result.files.first.map { UTType(filenameExtension: $0.pathExtension) } == .heic)
    }

    /// An edited photo keeps its own name with the rendering's extension.
    @Test func sharedFileKeepsThePhotosName() {
        #expect(ShareSource.filename(original: "IMG_1234.HEIC", shared: "FullSizeRender.jpg") == "IMG_1234.jpg")
        #expect(ShareSource.filename(original: "IMG_1234.HEIC", shared: "IMG_1234.HEIC") == "IMG_1234.HEIC")
        #expect(ShareSource.filename(original: "", shared: "FullSizeRender.jpg") == "FullSizeRender.jpg")
    }

    /// Two photos from two cameras can share a name; both arrive.
    @Test func sameNamesDoNotCollide() async throws {
        defer { cleanUp() }
        let one = try MetadataFixture.write(.jpeg, in: fixtures)
        let two = try MetadataFixture.write(.jpeg, in: fixtures)
        let pipeline = ShareExportPipeline(
            reader: FakeReader(photos: ["1": one, "2": two]),
            folder: try ShareExportPipeline.makeFolder(in: shareRoot),
            level: .all
        )
        let result = await pipeline.export([
            ShareSource(id: "1", kind: .photo, filename: "IMG_0001.JPG"),
            ShareSource(id: "2", kind: .photo, filename: "IMG_0001.JPG"),
        ])
        #expect(result.files.count == 2)
        #expect(Set(result.files).count == 2)
        pipeline.removeFolder()
        #expect(!FileManager.default.fileExists(atPath: pipeline.folder.path))
    }

    /// AC-1: No Location from the grid — the file has no GPS, keeps the camera,
    /// the exposure and the date, and decodes to the same pixels.
    @Test func noLocationFromTheGrid() async throws {
        defer { cleanUp() }
        let photoA = try MetadataFixture.write(.heic, in: fixtures)
        let pipeline = ShareExportPipeline(
            reader: FakeReader(photos: ["A": photoA]),
            folder: try ShareExportPipeline.makeFolder(in: shareRoot),
            level: .noLocation
        )
        let result = await pipeline.export([ShareSource(id: "A", kind: .photo, filename: "IMG_0001.HEIC")])

        let file = try #require(result.files.first)
        #expect(file.lastPathComponent == "IMG_0001.HEIC")
        #expect(MetadataFixture.dictionary(kCGImagePropertyGPSDictionary, of: file) == nil)
        let tiff = try #require(MetadataFixture.dictionary(kCGImagePropertyTIFFDictionary, of: file))
        #expect(tiff[kCGImagePropertyTIFFMake] as? String == "SONY")
        #expect(tiff[kCGImagePropertyTIFFModel] as? String == "ILCE-7M4")
        let exif = try #require(MetadataFixture.dictionary(kCGImagePropertyExifDictionary, of: file))
        #expect(exif[kCGImagePropertyExifISOSpeedRatings] as? [Int] == [400])
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:09:20 17:05:00")
        #expect(MetadataFixture.pixels(of: file) == MetadataFixture.pixels(of: photoA))
        // Only the shared file is left in its slot: the original copy is gone.
        let slot = file.deletingLastPathComponent()
        #expect(try FileManager.default.contentsOfDirectory(atPath: slot.path) == ["IMG_0001.HEIC"])
    }

    /// Spec §5: a photo whose location cannot be removed is left out and
    /// named; the rest of the share goes ahead.
    @Test func aPhotoThatCannotBeCleanedIsLeftOut() async throws {
        defer { cleanUp() }
        let jpeg = try MetadataFixture.write(.jpeg, in: fixtures)
        let png = try MetadataFixture.write(.png, in: fixtures)
        let pipeline = ShareExportPipeline(
            reader: FakeReader(photos: ["jpeg": jpeg, "png": png]),
            folder: try ShareExportPipeline.makeFolder(in: shareRoot),
            level: .noLocation
        )
        let result = await pipeline.export([
            ShareSource(id: "png", kind: .photo, filename: "Screenshot.PNG"),
            ShareSource(id: "jpeg", kind: .photo, filename: "IMG_0002.JPG"),
        ])
        #expect(result.failed == ["Screenshot.PNG"])
        #expect(result.files.map(\.lastPathComponent) == ["IMG_0002.JPG"])
        let slot = pipeline.folder.appendingPathComponent("0")
        #expect(try FileManager.default.contentsOfDirectory(atPath: slot.path).isEmpty)
    }

    /// AC-3, second half: Remove Location in the app, then share at All
    /// Metadata — the file's GPS goes too, and nothing else does.
    @Test func removedLocationDropsFileGPSAtAll() async throws {
        defer { cleanUp() }
        let photoA = try MetadataFixture.write(.heic, in: fixtures)
        let pipeline = ShareExportPipeline(
            reader: FakeReader(photos: ["A": photoA]),
            folder: try ShareExportPipeline.makeFolder(in: shareRoot),
            level: .all
        )
        let result = await pipeline.export([
            ShareSource(id: "A", kind: .photo, filename: "IMG_0001.HEIC", hasLocation: false),
        ])

        let file = try #require(result.files.first)
        #expect(MetadataFixture.dictionary(kCGImagePropertyGPSDictionary, of: file) == nil)
        #expect(!MetadataRewriter.carriesLocation(file))
        let tiff = try #require(MetadataFixture.dictionary(kCGImagePropertyTIFFDictionary, of: file))
        #expect(tiff[kCGImagePropertyTIFFMake] as? String == "SONY")
        let exif = try #require(MetadataFixture.dictionary(kCGImagePropertyExifDictionary, of: file))
        #expect(exif[kCGImagePropertyExifISOSpeedRatings] as? [Int] == [400])
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:09:20 17:05:00")
        #expect(MetadataFixture.pixels(of: file) == MetadataFixture.pixels(of: photoA))
    }

    /// A photo that never had a location shares byte for byte at All, even
    /// though its asset has none.
    @Test func noLocationAnywhereStaysByteIdentical() async throws {
        defer { cleanUp() }
        var options = MetadataFixture.Options()
        options.xmp = false
        let data = try MetadataFixture.encode(.jpeg, options: options)
        let plain = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let url = fixtures.appendingPathComponent("plain.jpg")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
        let strip: [CFString: Any] = [kCGImageMetadataShouldExcludeGPS: true]
        #expect(CGImageDestinationCopyImageSource(destination, plain, strip as CFDictionary, nil))
        #expect(!MetadataRewriter.carriesLocation(url))

        let pipeline = ShareExportPipeline(
            reader: FakeReader(photos: ["P": url]),
            folder: try ShareExportPipeline.makeFolder(in: shareRoot),
            level: .all
        )
        let result = await pipeline.export([ShareSource(id: "P", kind: .photo, filename: "P.jpg", hasLocation: false)])
        let file = try #require(result.files.first)
        #expect(try Self.sha256(file) == Self.sha256(url))
    }
}
