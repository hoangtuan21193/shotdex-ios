import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.04 §3 — the Hide commands, by where a photo lives.
@Suite struct HideCommandPlanTests {
    /// AC-73: A is in Photos and on NAS Home, B only in Photos, C only on
    /// NAS Home. A's menu has exactly Hide in Photos and Hide in ShotDex
    /// Only; B and C one Hide each. Hide in ShotDex Only takes A out of the
    /// grid and Statistics into the Hidden section without touching Photos;
    /// Unhide brings it back; Hide in Photos hides the asset in Photos and
    /// the NAS copy in ShotDex.
    @Test func mixedPhotoOffersBothCommands() async throws {
        let database = try AppDatabase.makeEmpty()
        let nas = try SourceStore(database: database).addServer(name: "NAS Home", connectionId: "C1")
        try await database.writer.write { db in
            for (photo, copy, source, kind) in [("A", "A-photos", PhotoLibrarySource.id, "photos"), ("A", "A-nas", nas, "server"),
                                                ("B", "B-photos", PhotoLibrarySource.id, "photos"), ("C", "C-nas", nas, "server")] {
                try db.execute(sql: "INSERT OR IGNORE INTO photos (id, createdAt) VALUES (?, 1)", arguments: [photo])
                try db.execute(sql: "INSERT OR IGNORE INTO photo_metadata (assetId, mediaType, isFavorite, indexedAt, exifStatus) VALUES (?, 1, 0, 1, 'indexed')",
                               arguments: [photo])
                try db.execute(sql: "INSERT INTO photo_copies (id, photoId, sourceId, kind, photoKitId, relativePath, relativePathKey) VALUES (?, ?, ?, ?, ?, ?, ?)",
                               arguments: [copy, photo, source, kind, kind == "photos" ? photo : nil,
                                           kind == "photos" ? nil : "\(photo).ARW", kind == "photos" ? nil : "\(photo.lowercased()).arw"])
            }
        }
        let hiddenInPhotos = MixedDeletionTests.Recorder()
        let service = HideService(database: database) { hiddenInPhotos.record($0) }
        #expect(try service.commands(for: ["A"]).map(\.title) == ["Hide in Photos", "Hide in ShotDex Only"])
        #expect(try service.commands(for: ["B"]).map(\.title) == ["Hide"])
        #expect(try service.commands(for: ["C"]).map(\.title) == ["Hide"])
        #expect(try service.commands(for: ["B", "C"]) == [.hide])
        #expect(try service.commands(for: ["A", "B"]) == [.hideInPhotos, .hideInShotDexOnly])

        let grid = LibraryQueries(database: database)
        let hidden = HiddenCopyStore(database: database)
        try await service.run(.hideInShotDexOnly, photoIds: ["A"])
        #expect(hiddenInPhotos.ids.isEmpty)
        #expect(try grid.count(matching: FilterCriteria()) == 2)
        #expect(try StatisticsQueries(database: database).totalPhotos(scope: .allTime) == 2)
        #expect(try hidden.hiddenPhotoIds() == ["A"])

        try hidden.unhide(photoIds: ["A"])
        #expect(try grid.count(matching: FilterCriteria()) == 3)

        try await service.run(.hideInPhotos, photoIds: ["A"])
        #expect(hiddenInPhotos.ids == ["A"])
        let nasHidden = try await database.reader.read { db in try Bool.fetchOne(db, sql: "SELECT isHidden FROM photo_copies WHERE id = 'A-nas'") }
        #expect(nasHidden == true)
        #expect(try grid.count(matching: FilterCriteria()) == 2)
    }
}
