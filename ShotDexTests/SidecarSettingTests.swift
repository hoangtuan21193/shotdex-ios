import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.02 §5 — Read and Write .xmp Sidecars.
@MainActor
@Suite struct SidecarSettingTests {
    /// AC-31: with the switch off, ★4 on ten file photos writes no `.xmp`
    /// (and the read before did not take the ★2 a sidecar already said);
    /// ★ ≥ 4 finds the ten, and still finds them after Clear Local Metadata
    /// Index.
    @Test func offKeepsMarksInDatabaseOnly() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SidecarsOff-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var options = MetadataFixture.Options()
        options.starRating = nil
        for n in 0..<10 {
            options.width = 64 + n
            try MetadataFixture.encode(.tiff, options: options).write(to: root.appendingPathComponent("DSC\(n).ARW"))
        }
        try SidecarReaderTests.lightroomSidecar(rating: 2).write(to: root.appendingPathComponent("DSC0.xmp"))
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: root.path))

        let defaults = try #require(UserDefaults(suiteName: "SidecarSettingTests-\(UUID().uuidString)"))
        defaults.set(false, forKey: SettingsKeys.readsAndWritesSidecars)
        #expect(!SidecarSetting.isOn(defaults))
        #expect(SidecarSetting.isOn(UserDefaults(suiteName: "SidecarSettingTests-\(UUID().uuidString)")!))

        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "T7 RAW Archive", bookmark: Data(), includesSubfolders: true,
                                                                     pairsRawAndJpeg: true, kind: "drive")
        var indexer = FolderSourceIndexer(database: database, composer: FolderSourceIndexTests.composer)
        indexer.readsSidecars = SidecarSetting.isOn(defaults)
        _ = try indexer.index(sourceId: sourceId, root: root, includesSubfolders: true, pairsRawAndJpeg: true)
        let ids = try await database.reader.read { db in try String.fetchAll(db, sql: "SELECT id FROM photos") }
        #expect(ids.count == 10)
        #expect(try await database.reader.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_user_marks") } == 0)

        let isOn = SidecarSetting.isOn(defaults)
        let writer = SidecarWriter(database: database, fileURL: { _, path in root.appendingPathComponent(path) },
                                   isEnabled: { isOn })
        let queue = SidecarWriteQueue(writer: writer)
        let marks = PhotoMarks(store: PhotoMarksStore(database: database), sidecarQueue: queue)
        await marks.setRating(4, ids: ids)
        #expect(await queue.flush() == SidecarWriter.Summary())
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)) == before)
        #expect(try await database.reader.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pending_sidecar") } == 0)

        var criteria = FilterCriteria()
        criteria.ratingFilter = .atLeast(4)
        let library = LibraryQueries(database: database)
        #expect(try library.count(matching: criteria) == 10)
        try MetadataStore(database: database).deleteAll()
        _ = try indexer.index(sourceId: sourceId, root: root, includesSubfolders: true, pairsRawAndJpeg: true)
        #expect(try library.count(matching: criteria) == 10)
    }
}
