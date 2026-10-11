import Foundation
import GRDB

/// Copies ShotDex hides (FS-19.04 §3). A photo is hidden when every one of
/// its copies is; the flag is user data — a re-index never clears it.
struct HiddenCopyStore: Sendable {
    let database: AppDatabase

    func hide(copyIds: [String]) throws {
        guard !copyIds.isEmpty else { return }
        try database.writer.write { db in
            try db.execute(sql: "UPDATE photo_copies SET isHidden = 1 WHERE id IN (\(databaseQuestionMarks(count: copyIds.count)))",
                           arguments: StatementArguments(copyIds))
        }
    }

    /// Hides every copy of each photo — Hide on a photo in one place, and
    /// Hide in ShotDex Only.
    func hide(photoIds: [String]) throws {
        guard !photoIds.isEmpty else { return }
        try database.writer.write { db in
            try db.execute(sql: "UPDATE photo_copies SET isHidden = 1 WHERE photoId IN (\(databaseQuestionMarks(count: photoIds.count)))",
                           arguments: StatementArguments(photoIds))
        }
    }

    /// Unhide in the Hidden section: every copy of each photo comes back.
    func unhide(photoIds: [String]) throws {
        guard !photoIds.isEmpty else { return }
        try database.writer.write { db in
            try db.execute(sql: "UPDATE photo_copies SET isHidden = 0 WHERE photoId IN (\(databaseQuestionMarks(count: photoIds.count)))",
                           arguments: StatementArguments(photoIds))
        }
    }

    /// Photos whose every present copy is hidden — the Hidden section,
    /// newest first. Empty: the section does not show.
    func hiddenPhotoIds() throws -> [String] {
        try database.reader.read { db in
            try String.fetchAll(db, sql: """
                SELECT p.id FROM photos p
                WHERE EXISTS (SELECT 1 FROM photo_copies c WHERE c.photoId = p.id AND c.missingSince IS NULL)
                  AND NOT EXISTS (SELECT 1 FROM photo_copies c WHERE c.photoId = p.id AND c.missingSince IS NULL AND c.isHidden = 0)
                ORDER BY p.createdAt DESC, p.id
                """)
        }
    }

    /// The Hidden section's grid: `hiddenPhotoIds()` as grid rows, newest
    /// first. The library's own queries leave these out (`PhotoVisibility`),
    /// so this one reads `photo_metadata` without that condition.
    func hiddenGridItems() async throws -> [LibraryGridItem] {
        try await database.reader.read { db in
            try LibraryGridItem.fetchAll(db, sql: """
                SELECT assetId, creationDate, mediaType, originalFilename,
                       iso, aperture, shutterSpeedDisplay,
                       focalLength, equivalentFocalLength, width, height, fileSize
                FROM photo_metadata WHERE \(Self.isHidden)
                ORDER BY creationDate DESC, assetId
                """)
        }
    }

    /// How many photos the Hidden section holds; its Collections row shows
    /// only above zero.
    func hiddenCount() throws -> Int {
        try database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_metadata WHERE \(Self.isHidden)") ?? 0
        }
    }

    /// A `photo_metadata` row whose every present copy is hidden.
    private static let isHidden = """
        EXISTS (SELECT 1 FROM photo_copies c WHERE c.photoId = photo_metadata.assetId AND c.missingSince IS NULL) \
        AND NOT EXISTS (SELECT 1 FROM photo_copies c WHERE c.photoId = photo_metadata.assetId \
        AND c.missingSince IS NULL AND c.isHidden = 0)
        """

    /// The names of the sources the hidden photos are on — the grid's
    /// footer ("6 Photos · NAS Home").
    func hiddenSourceNames() throws -> [String] {
        try database.reader.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT s.name FROM photo_copies c JOIN sources s ON s.id = c.sourceId
                WHERE c.isHidden = 1 AND c.missingSince IS NULL
                ORDER BY s.name
                """)
        }
    }

    /// What a source's own view shows: photos with a copy there that is
    /// not hidden. Hiding the NAS Home copy takes the photo out of NAS
    /// Home's view even while it stays in the grid through another copy.
    func photoIds(inSource sourceId: String) throws -> [String] {
        try database.reader.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT photoId FROM photo_copies
                WHERE sourceId = ? AND missingSince IS NULL AND isHidden = 0
                ORDER BY photoId
                """, arguments: [sourceId])
        }
    }
}
