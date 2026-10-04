import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ShotDex

/// FS-19.02 §1 — a photo is its image data.
@Suite struct PhotoIdentityTests {
    /// AC-22: another app writes XMP into the file itself — the bytes change,
    /// the image data does not — and the content hash, fast and full, stays
    /// the same. Checked for JPEG, TIFF (the DNG/ARW/NEF family) and HEIC;
    /// a photo with other pixels hashes differently.
    @Test(arguments: [UTType.jpeg, .tiff, .heic])
    func embeddedMetadataKeepsHash(_ type: UTType) throws {
        let plain = try MetadataFixture.encode(type, options: MetadataFixture.Options())
        let tagged = try MetadataFixture.addXMP(to: plain, type: type)
        #expect(plain != tagged)
        #expect(ImageDataLayout.ranges(in: DataBytes(data: plain)) != nil, "layout understood")

        let before = try ContentHasher.hash(DataBytes(data: plain), full: true)
        let after = try ContentHasher.hash(DataBytes(data: tagged), full: true)
        #expect(after == before)
        #expect(before.algorithm == "sdx-image-sha256")
        #expect(before.full != nil)

        guard type != .heic else { return }
        var other = MetadataFixture.Options()
        other.width += 16
        let different = try MetadataFixture.encode(type, options: other)
        #expect(try ContentHasher.hash(DataBytes(data: different), full: true).full != before.full)
    }

    /// A Lightroom export carries its own XMP packet in place of ImageIO's;
    /// its image data is the same picture's.
    @Test func lightroomPacketKeepsHash() throws {
        var options = MetadataFixture.Options()
        options.xmp = false
        let plain = try MetadataFixture.encode(.jpeg, options: options)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let lightroom = try MetadataFixture.lightroomJPEG(in: folder)

        let fromFile = try ContentHasher.hash(FileBytes(url: lightroom), full: true)
        #expect(fromFile == (try ContentHasher.hash(DataBytes(data: plain), full: true)))
    }

    /// Files with no layout the hasher knows are hashed whole.
    @Test func unknownFormatHashesWholeFile() throws {
        let a = DataBytes(data: Data("not an image, version one".utf8))
        let b = DataBytes(data: Data("not an image, version two".utf8))
        #expect(ImageDataLayout.ranges(in: a) == nil)
        #expect(try ContentHasher.hash(a, full: true) != (try ContentHasher.hash(b, full: true)))
    }
}
