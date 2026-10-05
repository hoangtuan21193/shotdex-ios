import Foundation
import GRDB
import ShotDexKit
import Testing
@testable import ShotDex

/// FS-19.02 §4 — Import Lightroom Edits.
@Suite struct LightroomImportTests {
    /// AC-53: a RAW whose Lightroom sidecar says Exposure +1.00. Reading the
    /// source leaves the photo with no recipe; Import Lightroom Edits on it
    /// gives it a recipe with Exposure +1.00, through the FS-03.14b table.
    @Test func onlyOnCommand() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LrEdits-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var options = MetadataFixture.Options()
        options.starRating = nil
        try MetadataFixture.encode(.tiff, options: options).write(to: root.appendingPathComponent("DSC04512.ARW"))
        try SidecarReaderTests.lightroomSidecar(rating: 3).write(to: root.appendingPathComponent("DSC04512.xmp"))

        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "2026 Japan", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        let composer = MetadataComposer(sensorLookup: SensorLookup(records: [], customMappings: []))
        _ = try FolderSourceIndexer(database: database, composer: composer)
            .index(sourceId: sourceId, root: root, includesSubfolders: true, pairsRawAndJpeg: true)
        let photoId = try #require(try database.reader.read { db in try String.fetchOne(db, sql: "SELECT id FROM photos") })
        #expect(try database.reader.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_recipes") } == 0)

        let report = try LightroomEditsImport(database: database) { _, path in root.appendingPathComponent(path) }
            .run(photoIds: [photoId])
        #expect(report.imported == [photoId])
        let data = try #require(try database.reader.read { db in
            try Data.fetchOne(db, sql: "SELECT recipe FROM photo_recipes WHERE photoId = ?", arguments: [photoId])
        })
        let recipe = try JSONDecoder().decode(PhotoEditRecipe.self, from: data)
        #expect(recipe.adjustments.exposure == 1.0)
    }
}
