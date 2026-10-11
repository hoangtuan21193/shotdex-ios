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
