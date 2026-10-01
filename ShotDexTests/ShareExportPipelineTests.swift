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

    /// AC-5: the viewer shares through the grid's own gather, so a photo
    /// shared from either leaves as the same bytes. A photo that never
    /// arrived from the library is told apart from one that could not be
    /// cleaned, which is how the viewer still says "not downloaded yet".
    @Test func detailMatchesGrid() async throws {
        defer { cleanUp() }
        let photoA = try MetadataFixture.write(.heic, in: fixtures)
        var outputs: [String] = []
        for _ in 0..<2 {
            let pipeline = ShareExportPipeline(
                reader: FakeReader(photos: ["A": photoA]),
                folder: try ShareExportPipeline.makeFolder(in: shareRoot),
                level: .noLocation
            )
            let result = await pipeline.export([ShareSource(id: "A", kind: .photo, filename: "IMG_0001.HEIC")])
            outputs.append(try Self.sha256(try #require(result.files.first)))
        }
        #expect(outputs[0] == outputs[1])

        let missing = ShareExportPipeline(
            reader: FakeReader(),
            folder: try ShareExportPipeline.makeFolder(in: shareRoot),
            level: .noLocation
        )
        let result = await missing.export([ShareSource(id: "cloud", kind: .photo, filename: "IMG_0003.HEIC")])
        #expect(result.failed == ["IMG_0003.HEIC"])
        #expect(result.unread == ["IMG_0003.HEIC"])

        let viewer = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Library/PhotoDetailScreen.swift")
            .joined(separator: "\n")
        let start = try #require(viewer.range(of: "private func shareImage("))
        let body = viewer[start.lowerBound...].prefix(600)
        #expect(body.contains("PhotoShareSheet.gather("))
        #expect(!body.contains("requestImageDataAndOrientation"))
    }

    /// AC-10: twenty 48 MP photos at No Location — none keeps its GPS, all
    /// keep the camera, and the peak memory of the gather does not grow with
    /// the count: twenty cost no more than one, plus at most one file's size.
    @Test func twentyPhotosPeakIsFlat() async throws {
        defer { cleanUp() }
        var options = MetadataFixture.Options()
        options.width = 8064
        options.height = 6048
        options.xmp = false
        let big = fixtures.appendingPathComponent("A-48mp.jpg")
        try MetadataFixture.encode(.jpeg, options: options).write(to: big)
        let fileSize = UInt64(try FileManager.default.attributesOfItem(atPath: big.path)[.size] as? Int ?? 0)
        let reader = FakeReader(photos: Dictionary(uniqueKeysWithValues: (0..<20).map { ("\($0)", big) }))

        func peak(count: Int) async throws -> (UInt64, ShareExportResult, ShareExportPipeline) {
            let pipeline = ShareExportPipeline(
                reader: reader,
                folder: try ShareExportPipeline.makeFolder(in: shareRoot),
                level: .noLocation
            )
            let sources = (0..<count).map { ShareSource(id: "\($0)", kind: .photo, filename: "IMG_\($0).JPG") }
            let baseline = FootprintSampler.current()
            let sampler = FootprintSampler()
            sampler.start()
            let result = await pipeline.export(sources)
            let top = sampler.stop()
            return (top > baseline ? top - baseline : 0, result, pipeline)
        }

        _ = await FootprintSampler.waitForQuietProcess()
        let (one, _, first) = try await peak(count: 1)
        first.removeFolder()
        let (twenty, result, pipeline) = try await peak(count: 20)
        defer { pipeline.removeFolder() }

        #expect(result.files.count == 20)
        #expect(result.failed.isEmpty)
        for file in result.files {
            #expect(MetadataFixture.dictionary(kCGImagePropertyGPSDictionary, of: file) == nil)
            #expect(MetadataFixture.dictionary(kCGImagePropertyTIFFDictionary, of: file)?[kCGImagePropertyTIFFMake] as? String == "SONY")
        }
        print("FOOTPRINT share gather: 1 photo +\(one / 1_048_576) MB, 20 photos +\(twenty / 1_048_576) MB, file \(fileSize / 1_048_576) MB")
        #expect(twenty <= one + fileSize, "1: \(one) B, 20: \(twenty) B, file: \(fileSize) B")
    }

    /// AC-6: a video goes as it is at every level — the library's own file,
    /// byte for byte — next to a photo whose location is removed.
    @Test func videoGoesAsItIs() async throws {
        defer { cleanUp() }
        let movie = fixtures.appendingPathComponent("IMG_0004.MOV")
        try Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31) }).write(to: movie)
        let photoA = try MetadataFixture.write(.heic, in: fixtures)
        let pipeline = ShareExportPipeline(
            reader: FakeReader(photos: ["A": photoA], videos: ["V": movie]),
            folder: try ShareExportPipeline.makeFolder(in: shareRoot),
            level: .noLocation
        )
        let result = await pipeline.export([
            ShareSource(id: "V", kind: .video, filename: "IMG_0004.MOV"),
            ShareSource(id: "A", kind: .photo, filename: "IMG_0001.HEIC"),
        ])
        #expect(result.files.count == 2)
        #expect(result.files[0] == movie)
        #expect(try Self.sha256(result.files[0]) == Self.sha256(movie))
        #expect(MetadataFixture.dictionary(kCGImagePropertyGPSDictionary, of: result.files[1]) == nil)
    }

    /// AC-9: Skip — the share goes ahead with photo A alone, without GPS;
    /// the RAW files are left out at the user's word, not as failures.
    @Test func skipDropsRAW() async throws {
        defer { cleanUp() }
        let photoA = try MetadataFixture.write(.heic, in: fixtures)
        let raw = fixtures.appendingPathComponent("DSC00001.ARW")
        try Data(repeating: 7, count: 512).write(to: raw)
        var pipeline = ShareExportPipeline(
            reader: FakeReader(photos: ["A": photoA, "1": raw, "2": raw]),
            folder: try ShareExportPipeline.makeFolder(in: shareRoot),
            level: .noLocation
        )
        pipeline.rawChoice = .skip
        let result = await pipeline.export([
            ShareSource(id: "1", kind: .raw, filename: "DSC00001.ARW"),
            ShareSource(id: "2", kind: .raw, filename: "DSC00002.ARW"),
            ShareSource(id: "A", kind: .photo, filename: "IMG_0001.HEIC"),
        ])
        #expect(result.files.map(\.lastPathComponent) == ["IMG_0001.HEIC"])
        #expect(result.skipped == ["DSC00001.ARW", "DSC00002.ARW"])
        #expect(result.failed.isEmpty)
        #expect(MetadataFixture.dictionary(kCGImagePropertyGPSDictionary, of: result.files[0]) == nil)
    }
}
