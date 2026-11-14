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

    /// AC-55: a card whose condition says Source = Photos Library keeps
    /// counting Photos Library under the popup's T7; a card with no Source
    /// condition follows the popup.
    @Test func cardConditionWinsOverPopup() throws {
        let database = try AppDatabase.makeEmpty()
        let t7 = try SourceStore(database: database).addFolder(name: "T7", bookmark: Data(), includesSubfolders: true,
                                                              pairsRawAndJpeg: true, kind: "drive")
        try database.writer.write { db in
            for (photo, source, kind) in [("A", t7, "file"), ("B", t7, "file"), ("C", PhotoLibrarySource.id, "photos")] {
                try db.execute(sql: "INSERT INTO photos (id, createdAt) VALUES (?, 1)", arguments: [photo])
                try db.execute(sql: "INSERT INTO photo_metadata (assetId, mediaType, isFavorite, indexedAt, exifStatus, cameraModel, normalizedCameraModel, creationDate) VALUES (?, 1, 0, 1, 'indexed', 'ILCE-7M4', 'Sony A7 IV', 1700000000)",
                               arguments: [photo])
                try db.execute(sql: "INSERT INTO photo_copies (id, photoId, sourceId, kind, photoKitId, relativePath, relativePathKey) VALUES (?, ?, ?, ?, ?, ?, ?)",
                               arguments: [photo + "-copy", photo, source, kind, kind == "photos" ? photo : nil,
                                           kind == "photos" ? nil : photo + ".ARW", kind == "photos" ? nil : photo.lowercased() + ".arw"])
            }
        }
        let popupT7 = StatisticsQueries(database: database, sourceId: t7)
        var pinned = ChartSpec(title: "Photos by Year", kind: .bar, dimension: .cameraBody)
        pinned.filter = SmartAlbumQuery(rules: [SmartAlbumRule(field: .source, op: .isExactly, text: PhotoLibrarySource.id)])
        let open = ChartSpec(title: "Photos by Camera", kind: .bar, dimension: .cameraBody)

        #expect(try popupT7.chartData(for: pinned, scope: .allTime).filter { !$0.isUnknown }.map(\.value) == [1])
        #expect(try popupT7.chartData(for: open, scope: .allTime).filter { !$0.isUnknown }.map(\.value) == [2])
        #expect(pinned.filter.pinnedSourceId == PhotoLibrarySource.id)
        #expect(open.filter.pinnedSourceId == nil)
    }
}

/// Board `MAC_StatisticsCamera`: one camera's header and tiles, read in one
/// pass; the Source popup narrows it like every card.
@Suite struct CameraProfileTests {
    @Test func profileOfOneCamera() throws {
        let database = try AppDatabase.makeEmpty()
        let t7 = try SourceStore(database: database).addFolder(name: "T7", bookmark: Data(), includesSubfolders: true,
                                                              pairsRawAndJpeg: true, kind: "drive")
        let rows: [(id: String, model: String, lens: String?, favorite: Int, date: Int, source: String)] = [
            ("A", "Canon EOS R6 Mark II", "RF 24-70mm", 1, 1_673_700_000, t7),
            ("B", "Canon EOS R6 Mark II", "RF 85mm", 0, 1_791_000_000, t7),
            ("C", "Canon EOS R6 Mark II", nil, 0, 1_700_000_000, PhotoLibrarySource.id),
            ("D", "ILCE-7M4", "FE 24mm", 1, 1_700_000_000, PhotoLibrarySource.id),
        ]
        try database.writer.write { db in
            for row in rows {
                let kind = row.source == t7 ? "file" : "photos"
                try db.execute(sql: "INSERT INTO photos (id, createdAt) VALUES (?, 1)", arguments: [row.id])
                try db.execute(sql: """
                    INSERT INTO photo_metadata (assetId, mediaType, isFavorite, indexedAt, exifStatus, cameraModel, normalizedCameraModel,
                        normalizedCameraManufacturer, normalizedLensModel, sensorFormat, cropFactor, creationDate)
                    VALUES (?, 1, ?, 1, 'indexed', ?, ?, 'Canon', ?, 'Full Frame', 1.0, ?)
                    """, arguments: [row.id, row.favorite, row.model, row.model, row.lens, row.date])
                try db.execute(sql: "INSERT INTO photo_copies (id, photoId, sourceId, kind, photoKitId, relativePath, relativePathKey) VALUES (?, ?, ?, ?, ?, ?, ?)",
                               arguments: [row.id + "-copy", row.id, row.source, kind, kind == "photos" ? row.id : nil,
                                           kind == "photos" ? nil : row.id + ".CR3", kind == "photos" ? nil : row.id.lowercased() + ".cr3"])
            }
        }
        let profile = try StatisticsQueries(database: database).cameraProfile(model: "Canon EOS R6 Mark II")
        #expect(profile.photos == 3)
        #expect(profile.favorites == 1)
        #expect(profile.lenses == 2)
        #expect(profile.brand == "Canon")
        #expect(profile.sensorFormat == .fullFrame)
        #expect(profile.cropFactor == 1.0)
        #expect(profile.firstPhoto == Date(timeIntervalSince1970: 1_673_700_000))
        #expect(profile.latestPhoto == Date(timeIntervalSince1970: 1_791_000_000))
        let onT7 = try StatisticsQueries(database: database, sourceId: t7).cameraProfile(model: "Canon EOS R6 Mark II")
        #expect(onT7.photos == 2)
        #expect(try StatisticsQueries(database: database).cameraProfile(model: "Nikon Z8").photos == 0)
    }
}
