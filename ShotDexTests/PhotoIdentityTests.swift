import Foundation
import GRDB
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
        let first = try pass.run()
        #expect((first.hashed, first.merged, first.survivors.count) == (14, 5, 5))
        #expect(try count("SELECT COUNT(*) FROM photos", database) == 9)
        #expect(try count("SELECT COUNT(*) FROM photo_metadata", database) == 9)
        #expect(try count("SELECT COUNT(*) FROM (SELECT photoId FROM photo_copies GROUP BY photoId HAVING COUNT(*) = 2)", database) == 5)
        #expect(try pass.run() == IdentityMergePass.Summary())
    }

    private func count(_ sql: String, _ database: AppDatabase) throws -> Int {
        try database.reader.read { db in try Int.fetchOne(db, sql: sql) ?? -1 }
    }

    /// AC-20: a photo with ★4 whose file is renamed in Finder keeps its id,
    /// its copy and its star; only the renamed file is read; no new photo.
    /// A file deleted outside ShotDex leaves its photo an orphan with the copy
    /// marked missing.
    @Test func renameKeepsIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Rename-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (name, width) in [("DSC04512.JPG", 256), ("DSC04513.JPG", 264), ("DSC04514.JPG", 272)] {
            var options = MetadataFixture.Options()
            options.width = width
            try MetadataFixture.encode(.jpeg, options: options).write(to: root.appendingPathComponent(name))
        }
        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "2026 Japan", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        let indexer = FolderSourceIndexer(database: database, composer: FolderSourceIndexTests.composer)
        _ = try indexer.index(sourceId: sourceId, root: root, includesSubfolders: true, pairsRawAndJpeg: true)
        let before = try copy("DSC04512.JPG", database)
        try database.writer.write { db in
            try db.execute(sql: "INSERT INTO photo_user_marks (photoId, rating, ratingAt) VALUES (?, 4, 1)", arguments: [before.photoId])
        }

        try FileManager.default.moveItem(at: root.appendingPathComponent("DSC04512.JPG"), to: root.appendingPathComponent("Nara_001.JPG"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("DSC04514.JPG"))
        let summary = try indexer.index(sourceId: sourceId, root: root, includesSubfolders: true, pairsRawAndJpeg: true)

        #expect(summary == FolderSourceIndexer.Summary(photos: 1, unchanged: 1))
        let after = try copy("Nara_001.JPG", database)
        #expect(after.copyId == before.copyId)
        #expect(after.photoId == before.photoId)
        let state = try database.reader.read { db in
            (photos: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photos") ?? 0,
             rating: try Int.fetchOne(db, sql: "SELECT rating FROM photo_user_marks WHERE photoId = ?", arguments: [before.photoId]),
             orphans: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photos WHERE orphanedAt IS NOT NULL") ?? 0,
             missing: try String.fetchAll(db, sql: "SELECT relativePath FROM photo_copies WHERE missingSince IS NOT NULL"))
        }
        #expect(state.photos == 3)
        #expect(state.rating == 4)
        #expect(state.orphans == 1)
        #expect(state.missing == ["DSC04514.JPG"])
    }

    /// AC-21: photo A lives only in "2026 Japan" with ★4 and a recipe, its
    /// full hash already taken. Moved to T7 in Finder, it is one photo — the
    /// same id — with its copy on T7, ★4 and the recipe kept, and no orphan.
    @Test func moveAcrossSourcesKeepsData() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("Move-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let japan = base.appendingPathComponent("2026 Japan"), t7 = base.appendingPathComponent("T7")
        for folder in [japan, t7] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try MetadataFixture.encode(.jpeg, options: MetadataFixture.Options()).write(to: japan.appendingPathComponent("DSC04512.JPG"))
        let database = try AppDatabase.makeEmpty()
        let sources = SourceStore(database: database)
        let japanId = try sources.addFolder(name: "2026 Japan", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        let t7Id = try sources.addFolder(name: "T7 RAW Archive", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true, kind: "drive")
        let roots = [japanId: japan, t7Id: t7]
        let indexer = FolderSourceIndexer(database: database, composer: FolderSourceIndexTests.composer)
        let pass = IdentityMergePass(database: database) { sourceId, path in roots[sourceId]?.appendingPathComponent(path) }
        _ = try indexer.index(sourceId: japanId, root: japan, includesSubfolders: true, pairsRawAndJpeg: true)
        #expect(try pass.run().hashed == 1)
        let original = try copy("DSC04512.JPG", database).photoId
        try database.writer.write { db in
            try db.execute(sql: "INSERT INTO photo_user_marks (photoId, rating, ratingAt) VALUES (?, 4, 1)", arguments: [original])
            try db.execute(sql: "INSERT INTO photo_recipes (photoId, recipe, updatedAt) VALUES (?, x'0A0B', 1)", arguments: [original])
        }

        try FileManager.default.moveItem(at: japan.appendingPathComponent("DSC04512.JPG"), to: t7.appendingPathComponent("DSC04512.JPG"))
        _ = try indexer.index(sourceId: japanId, root: japan, includesSubfolders: true, pairsRawAndJpeg: true)
        _ = try indexer.index(sourceId: t7Id, root: t7, includesSubfolders: true, pairsRawAndJpeg: true)
        let summary = try pass.run()
        #expect((summary.hashed, summary.merged, summary.survivors.count) == (1, 1, 1))

        let state = try database.reader.read { db in
            (photos: try String.fetchAll(db, sql: "SELECT id FROM photos"),
             present: try String.fetchAll(db, sql: "SELECT sourceId FROM photo_copies WHERE missingSince IS NULL"),
             rating: try Int.fetchOne(db, sql: "SELECT rating FROM photo_user_marks WHERE photoId = ?", arguments: [original]),
             recipe: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_recipes WHERE photoId = ?", arguments: [original]),
             orphans: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photos WHERE orphanedAt IS NOT NULL"))
        }
        #expect(state.photos == [original])
        #expect(state.present == [t7Id])
        #expect(state.rating == 4)
        #expect(state.recipe == 1)
        #expect(state.orphans == 0)
    }

    /// AC-64: photo A (★4, keyword "Nara") has copies in "2026 Japan" and
    /// on T7. Another app saves a different picture over the T7 file. The T7
    /// copy becomes photo B with a new id, ★4 and "Nara" copied over; A keeps
    /// its "2026 Japan" copy and ★4; a later star on B leaves A alone.
    @Test func overwrittenCopySplits() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("Split-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let japan = base.appendingPathComponent("2026 Japan"), t7 = base.appendingPathComponent("T7")
        for folder in [japan, t7] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let picture = try MetadataFixture.encode(.jpeg, options: MetadataFixture.Options())
        try picture.write(to: japan.appendingPathComponent("DSC04512.JPG"))
        try picture.write(to: t7.appendingPathComponent("DSC04512.JPG"))
        let database = try AppDatabase.makeEmpty()
        let sources = SourceStore(database: database)
        let japanId = try sources.addFolder(name: "2026 Japan", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        let t7Id = try sources.addFolder(name: "T7 RAW Archive", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true, kind: "drive")
        let roots = [japanId: japan, t7Id: t7]
        let indexer = FolderSourceIndexer(database: database, composer: FolderSourceIndexTests.composer)
        for (id, root) in roots { _ = try indexer.index(sourceId: id, root: root, includesSubfolders: true, pairsRawAndJpeg: true) }
        _ = try IdentityMergePass(database: database) { sourceId, path in roots[sourceId]?.appendingPathComponent(path) }.run()
        let a = try database.reader.read { db in try String.fetchAll(db, sql: "SELECT id FROM photos") }
        #expect(a.count == 1)
        try database.writer.write { db in
            try db.execute(sql: "INSERT INTO photo_user_marks (photoId, rating, ratingAt) VALUES (?, 4, 1)", arguments: [a[0]])
            try db.execute(sql: "INSERT INTO photo_user_keyword (photoId, keyword, caseKey, foldKey, addedAt) VALUES (?, 'Nara', 'nara', 'nara', 1)", arguments: [a[0]])
        }

        var other = MetadataFixture.Options()
        other.width += 40
        let overwritten = t7.appendingPathComponent("DSC04512.JPG")
        try MetadataFixture.encode(.jpeg, options: other).write(to: overwritten)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(120)], ofItemAtPath: overwritten.path)
        _ = try indexer.index(sourceId: t7Id, root: t7, includesSubfolders: true, pairsRawAndJpeg: true)

        let state = try database.reader.read { db in
            (photos: try String.fetchAll(db, sql: "SELECT id FROM photos ORDER BY rowid"),
             japanPhoto: try String.fetchOne(db, sql: "SELECT photoId FROM photo_copies WHERE sourceId = ?", arguments: [japanId]),
             t7Photo: try String.fetchOne(db, sql: "SELECT photoId FROM photo_copies WHERE sourceId = ?", arguments: [t7Id]),
             ratings: try Row.fetchAll(db, sql: "SELECT photoId, rating FROM photo_user_marks").map { "\($0["photoId"] as String)=\($0["rating"] as Int)" },
             keywords: try String.fetchAll(db, sql: "SELECT photoId FROM photo_user_keyword WHERE keyword = 'Nara'"))
        }
        #expect(state.photos.count == 2)
        #expect(state.japanPhoto == a[0])
        let b = try #require(state.t7Photo)
        #expect(b != a[0])
        #expect(Set(state.ratings) == ["\(a[0])=4", "\(b)=4"])
        #expect(Set(state.keywords) == [a[0], b])

        try database.writer.write { db in try db.execute(sql: "UPDATE photo_user_marks SET rating = 1 WHERE photoId = ?", arguments: [b]) }
        let aRating = try database.reader.read { db in try Int.fetchOne(db, sql: "SELECT rating FROM photo_user_marks WHERE photoId = ?", arguments: [a[0]]) }
        #expect(aRating == 4)
    }

    private func copy(_ path: String, _ database: AppDatabase) throws -> (copyId: String, photoId: String) {
        try database.reader.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT id, photoId FROM photo_copies WHERE relativePath = ?", arguments: [path])
            return (row?["id"] ?? "", row?["photoId"] ?? "")
        }
    }
}
