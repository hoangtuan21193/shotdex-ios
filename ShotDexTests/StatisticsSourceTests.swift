import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.04 §5 — Statistics counts each photo once; the Source popup narrows.
@Suite struct StatisticsSourceTests {
    /// AC-71: photo A has copies on T7 and on NAS Home, photo B is only in
    /// Photos. All Sources counts 2, T7 counts 1, NAS Home counts 1 — the
    /// sources add up to more than All, as the footnote says.
    @Test func countsOncePerSource() throws {
        let database = try AppDatabase.makeEmpty()
        let sources = SourceStore(database: database)
        let t7 = try sources.addFolder(name: "T7", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true, kind: "drive")
        let nas = try sources.addServer(name: "NAS Home", connectionId: "C1")
        try database.writer.write { db in
            for (photo, copy, source, kind) in [("A", "A-t7", t7, "file"), ("A", "A-nas", nas, "server"), ("B", "B-photos", PhotoLibrarySource.id, "photos")] {
                try db.execute(sql: "INSERT OR IGNORE INTO photos (id, createdAt) VALUES (?, 1)", arguments: [photo])
                try db.execute(sql: "INSERT OR IGNORE INTO photo_metadata (assetId, mediaType, isFavorite, indexedAt, exifStatus, cameraModel) VALUES (?, 1, 0, 1, 'indexed', 'ILCE-7M4')",
                               arguments: [photo])
                try db.execute(sql: "INSERT INTO photo_copies (id, photoId, sourceId, kind, photoKitId, relativePath, relativePathKey) VALUES (?, ?, ?, ?, ?, ?, ?)",
                               arguments: [copy, photo, source, kind, kind == "photos" ? photo : nil, kind == "photos" ? nil : "A.ARW",
                                           kind == "photos" ? nil : "a.arw"])
            }
        }
        let all = StatisticsQueries(database: database)
        #expect(try all.totalPhotos(scope: .allTime) == 2)
        #expect(try StatisticsQueries(database: database, sourceId: t7).totalPhotos(scope: .allTime) == 1)
        #expect(try StatisticsQueries(database: database, sourceId: nas).totalPhotos(scope: .allTime) == 1)
        #expect(try StatisticsQueries(database: database, sourceId: PhotoLibrarySource.id).totalPhotos(scope: .allTime) == 1)
        let t7Cameras = try StatisticsQueries(database: database, sourceId: t7).usage(groupedBy: "cameraModel", scope: .allTime)
        #expect(t7Cameras.map(\.count) == [1])
        #expect(StatisticsQueries.sourceFootnote == "Each photo counted once across sources")
    }
}
