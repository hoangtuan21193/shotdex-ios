import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.05 §6 — albums across sources.
@Suite struct ShotDexAlbumTests {
    /// AC-61: a folder source, 3 file photos and 2 Photos photos. New Album
    /// "Kyoto" is a ShotDex album that takes all 5 — no album appears in
    /// Photos. For a photo only on file, the Photos album "Trip" is dimmed
    /// with "Photos albums can only hold Photos Library items."
    @Test func spansSources() throws {
        let database = try AppDatabase.makeEmpty()
        let albums = ShotDexAlbumStore(database: database)
        #expect(try albums.newAlbumKind() == .photos)
        let folder = try SourceStore(database: database).addFolder(name: "2026 Japan", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        #expect(try albums.newAlbumKind() == .shotDex)
        let ids = try database.writer.write { db in
            let ids = try MixedDeletionPlanTests.addPhotos(db, count: 3, sourceId: folder, kind: "file", prefix: "F")
                + MixedDeletionPlanTests.addPhotos(db, count: 2, sourceId: PhotoLibrarySource.id, kind: "photos", prefix: "P")
            for id in ids {
                try db.execute(sql: "INSERT INTO photo_metadata (assetId, mediaType, isFavorite, indexedAt, exifStatus) VALUES (?, 1, 0, 1, 'indexed')",
                               arguments: [id])
            }
            return ids
        }

        let kyoto = try albums.create(name: "Kyoto")
        try albums.add(photoIds: ids, to: kyoto)
        #expect(try albums.photoIds(in: kyoto) == ids)
        // Nothing of this reaches Photos: the album is ShotDex's own rows.
        #expect(try database.reader.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM shotdex_albums") } == 1)

        #expect(try albums.photosOnlyOutside([ids[0]]) == [ids[0]])
        #expect(try albums.photosOnlyOutside([ids[3]]).isEmpty)
        #expect(ShotDexAlbumStore.photosAlbumLimit == "Photos albums can only hold Photos Library items.")

        // A hidden member stays in the album's rows but leaves its grid.
        try HiddenCopyStore(database: database).hide(photoIds: [ids[1]])
        #expect(try albums.photoIds(in: kyoto) == ids.filter { $0 != ids[1] })
    }
}
