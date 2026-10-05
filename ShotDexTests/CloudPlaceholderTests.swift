import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.01b §4 — files only in the cloud.
@MainActor
@Suite struct CloudPlaceholderTests {
    /// AC-15: an iCloud Drive folder of 100 files, 40 of them placeholders
    /// (`.Name.ext.icloud` on iOS). The read opens none of the 40: 60 photos
    /// get EXIF and a metadata row — what filters and Statistics count — and
    /// 40 copies are recorded as cloud placeholders for the grid's cloud
    /// glyph. Once one downloads, the next read turns it into a full photo.
    @Test func neverDownloadsNeverCounts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("iCloud-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let jpeg = try MetadataFixture.encode(.jpeg, options: MetadataFixture.Options())
        for n in 0..<60 { try jpeg.write(to: root.appendingPathComponent("IMG_\(n).JPG")) }
        // A placeholder holds a small plist, never the picture.
        for n in 60..<100 { try Data("bplist00".utf8).write(to: root.appendingPathComponent(".IMG_\(n).JPG.icloud")) }

        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "iCloud Photos", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        let indexer = FolderSourceIndexer(database: database, composer: FolderSourceIndexTests.composer)
        let summary = try indexer.index(sourceId: sourceId, root: root, includesSubfolders: true, pairsRawAndJpeg: true)
        #expect(summary.photos == 60)
        #expect(summary.placeholders == 40)
        #expect(try count("SELECT COUNT(*) FROM photo_metadata", database) == 60)
        #expect(try count("SELECT COUNT(*) FROM photo_copies WHERE isCloudPlaceholder = 1", database) == 40)
        #expect(try count("SELECT COUNT(*) FROM content_hashes", database) == 60)
        #expect(try count("SELECT COUNT(*) FROM photo_copies WHERE relativePath LIKE '.%'", database) == 0)

        // IMG_60 downloads: the placeholder is replaced by the file.
        try FileManager.default.removeItem(at: root.appendingPathComponent(".IMG_60.JPG.icloud"))
        try jpeg.write(to: root.appendingPathComponent("IMG_60.JPG"))
        let again = try indexer.index(sourceId: sourceId, root: root, includesSubfolders: true, pairsRawAndJpeg: true)
        #expect(again.photos == 1)
        #expect(try count("SELECT COUNT(*) FROM photo_metadata", database) == 61)
        #expect(try count("SELECT COUNT(*) FROM photo_copies WHERE isCloudPlaceholder = 1", database) == 39)
        #expect(try count("SELECT COUNT(*) FROM photos", database) == 100)
    }

    private func count(_ sql: String, _ database: AppDatabase) throws -> Int {
        try database.reader.read { db in try Int.fetchOne(db, sql: sql) ?? -1 }
    }
}
