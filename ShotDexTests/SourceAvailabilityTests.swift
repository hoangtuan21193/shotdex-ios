import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.01 §1, 01b §1 — drives that come and go.
@MainActor
@Suite struct SourceAvailabilityTests {
    /// AC-46: T7 holds 10 photos, 3 of them also in "2026 Japan". With
    /// When a Drive Is Disconnected = Hide Its Photos, unplugging T7 takes 7
    /// photos out of the grid and Statistics; the 3 stay with their "2026
    /// Japan" copy. Plugging it back brings all 10 back, stars kept. With the
    /// default (keep), unplugging hides nothing and orphans nothing.
    @Test func hideOnDisconnect() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("Unplug-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let japan = base.appendingPathComponent("2026 Japan"), t7 = base.appendingPathComponent("T7")
        for folder in [japan, t7] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        for n in 0..<10 {
            var options = MetadataFixture.Options()
            options.width += n * 8
            options.starRating = nil
            let data = try MetadataFixture.encode(.jpeg, options: options)
            try data.write(to: t7.appendingPathComponent("DSC\(n).JPG"))
            if n < 3 { try data.write(to: japan.appendingPathComponent("DSC\(n).JPG")) }
        }
        let database = try AppDatabase.makeEmpty()
        let sources = SourceStore(database: database)
        let japanId = try sources.addFolder(name: "2026 Japan", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        let t7Id = try sources.addFolder(name: "T7 RAW Archive", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true, kind: "drive")
        let roots = [japanId: japan, t7Id: t7]
        let indexer = FolderSourceIndexer(database: database, composer: FolderSourceIndexTests.composer)
        for (id, root) in roots { _ = try indexer.index(sourceId: id, root: root, includesSubfolders: true, pairsRawAndJpeg: true) }
        _ = try IdentityMergePass(database: database) { sourceId, path in roots[sourceId]?.appendingPathComponent(path) }.run()
        let library = LibraryQueries(database: database)
        let statistics = StatisticsQueries(database: database)
        #expect(try library.count(matching: FilterCriteria()) == 10)
        try database.writer.write { db in
            try db.execute(sql: "INSERT INTO photo_user_marks (photoId, rating, ratingAt) SELECT photoId, 4, 1 FROM photo_copies WHERE sourceId = ?", arguments: [t7Id])
        }

        try sources.setOnline(false, sourceId: t7Id)
        #expect(try library.count(matching: FilterCriteria()) == 10, "keep: offline photos stay")

        try sources.setWhenUnplugged(.hidePhotos, sourceId: t7Id)
        #expect(try library.count(matching: FilterCriteria()) == 3)
        #expect(try statistics.totalPhotos(scope: .allTime) == 3)
        let orphans = try database.reader.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photos WHERE orphanedAt IS NOT NULL") }
        #expect(orphans == 0)

        try sources.setOnline(true, sourceId: t7Id)
        #expect(try library.count(matching: FilterCriteria()) == 10)
        #expect(try statistics.totalPhotos(scope: .allTime) == 10)
        let starred = try database.reader.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_user_marks WHERE rating = 4") }
        #expect(starred == 10)
    }
}

extension SourceAvailabilityTests {
    /// AC-10, AC-11: T7 is unplugged after 12 of 38 files are read. No error
    /// stops the app: the read reports a disconnect, the 12 photos stay (now
    /// offline), nothing is marked missing, nothing is orphaned. Plugged back,
    /// the read goes on from file 13 — 38 photos, no duplicate.
    @Test func unplugMidIndexKeepsReadThenResumes() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("Drive-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let t7 = base.appendingPathComponent("T7"), shelf = base.appendingPathComponent("unplugged")
        try FileManager.default.createDirectory(at: t7, withIntermediateDirectories: true)
        let jpeg = try MetadataFixture.encode(.jpeg, options: MetadataFixture.Options())
        for n in 0..<38 { try jpeg.write(to: t7.appendingPathComponent(String(format: "DSC%05d.JPG", n))) }
        let database = try AppDatabase.makeEmpty()
        let t7Id = try SourceStore(database: database).addFolder(name: "T7 RAW Archive", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true, kind: "drive")
        let indexer = FolderSourceIndexer(database: database, composer: FolderSourceIndexTests.composer)

        var asked = 0
        let first = try indexer.index(sourceId: t7Id, root: t7, includesSubfolders: true, pairsRawAndJpeg: true, shouldContinue: {
            asked += 1
            if asked == 13 { try? FileManager.default.moveItem(at: t7, to: shelf) }
            return true
        })
        #expect(first.disconnected)
        #expect(first.photos == 12)
        let offline = try database.reader.read { db in
            (copies: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_copies WHERE isOnline = 0") ?? 0,
             missing: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_copies WHERE missingSince IS NOT NULL") ?? 0,
             orphans: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photos WHERE orphanedAt IS NOT NULL") ?? 0,
             status: try String.fetchOne(db, sql: "SELECT status FROM sources WHERE id = ?", arguments: [t7Id]))
        }
        #expect(offline.copies == 12)
        #expect(offline.missing == 0)
        #expect(offline.orphans == 0)
        #expect(offline.status == "offline")

        try FileManager.default.moveItem(at: shelf, to: t7)
        try SourceStore(database: database).setOnline(true, sourceId: t7Id)
        let resumed = try indexer.index(sourceId: t7Id, root: t7, includesSubfolders: true, pairsRawAndJpeg: true)
        #expect(resumed == FolderSourceIndexer.Summary(photos: 26, unchanged: 12))
        let total = try database.reader.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photos") }
        #expect(total == 38)
    }
}
