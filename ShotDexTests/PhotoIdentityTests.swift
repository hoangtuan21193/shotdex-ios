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

extension PhotoIdentityTests {
    /// AC-48: two RAWs of the same size whose first, middle and last 64 KB
    /// match but which differ in one byte between them share a fast hash and
    /// stay two photos; two identical RAWs become one only once both full
    /// hashes are in. Fast-colliding copies are full-hashed first.
    @Test func fastHashNeverMergesAlone() throws {
        var bytes = Data((0..<400_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let first = bytes
        bytes[100_000] ^= 0xFF
        let nearTwin = bytes

        let a = try ContentHasher.hash(DataBytes(data: first), full: false)
        let b = try ContentHasher.hash(DataBytes(data: nearTwin), full: false)
        #expect(a.fast == b.fast)
        #expect(!a.isSameContent(as: b), "fast hashes alone never merge")

        let fullA = try ContentHasher.hash(DataBytes(data: first), full: true)
        let fullB = try ContentHasher.hash(DataBytes(data: nearTwin), full: true)
        #expect(!fullA.isSameContent(as: fullB))
        let twin = try ContentHasher.hash(DataBytes(data: first), full: true)
        #expect(fullA.isSameContent(as: twin))

        let order = ContentHash.fullHashOrder([(id: "x", fast: "f1"), (id: "a", fast: a.fast), (id: "y", fast: "f2"), (id: "b", fast: b.fast)])
        #expect(order == ["a", "b", "x", "y"])
    }
}
