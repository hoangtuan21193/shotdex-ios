import CryptoKit
import Foundation
import Photos
import Testing
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
            folder: try ShareExportPipeline.makeFolder(in: shareRoot)
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
            folder: try ShareExportPipeline.makeFolder(in: shareRoot)
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
            folder: try ShareExportPipeline.makeFolder(in: shareRoot)
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
}
