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

@MainActor
@Suite struct PhotoIdentityMergeTests {
    /// AC-18: 5 identical files in "2026 Japan" and on T7, plus 2 files only
    /// in each. Both sources read: 14 photos (fast hashes never merge). Full
    /// hashes done: 9 photos — the library grows by the 9, not 14 — each
    /// shared one with "2 copies", one metadata row each (what the grid and
    /// Statistics count).
    @Test func identicalCopiesAreOnePhoto() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("Identity-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let japan = base.appendingPathComponent("2026 Japan"), t7 = base.appendingPathComponent("T7")
        for folder in [japan, t7] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        for n in 0..<5 {
            var options = MetadataFixture.Options()
            options.width += n * 8
            let shared = try MetadataFixture.encode(.jpeg, options: options)
            try shared.write(to: japan.appendingPathComponent("DSC0450\(n).JPG"))
            try shared.write(to: t7.appendingPathComponent("DSC0450\(n).JPG"))
        }
        for (folder, prefix, offset) in [(japan, "JP", 100), (t7, "T7", 200)] {
            for n in 0..<2 {
                var options = MetadataFixture.Options()
                options.width += offset + n * 8
                try MetadataFixture.encode(.jpeg, options: options).write(to: folder.appendingPathComponent("\(prefix)_\(n).JPG"))
            }
        }
        let database = try AppDatabase.makeEmpty()
        let sources = SourceStore(database: database)
        let roots = [try sources.addFolder(name: "2026 Japan", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true): japan,
                     try sources.addFolder(name: "T7 RAW Archive", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true, kind: "drive"): t7]
        let indexer = FolderSourceIndexer(database: database, composer: FolderSourceIndexTests.composer)
        for (id, root) in roots { _ = try indexer.index(sourceId: id, root: root, includesSubfolders: true, pairsRawAndJpeg: true) }
        #expect(try count("SELECT COUNT(*) FROM photos", database) == 14)

        let pass = IdentityMergePass(database: database) { sourceId, path in roots[sourceId]?.appendingPathComponent(path) }
        #expect(try pass.run() == IdentityMergePass.Summary(hashed: 14, merged: 5))
        #expect(try count("SELECT COUNT(*) FROM photos", database) == 9)
        #expect(try count("SELECT COUNT(*) FROM photo_metadata", database) == 9)
        #expect(try count("SELECT COUNT(*) FROM (SELECT photoId FROM photo_copies GROUP BY photoId HAVING COUNT(*) = 2)", database) == 5)
        #expect(try pass.run() == IdentityMergePass.Summary(hashed: 0, merged: 0))
    }

    private func count(_ sql: String, _ database: AppDatabase) throws -> Int {
        try database.reader.read { db in try Int.fetchOne(db, sql: sql) ?? -1 }
    }
}
