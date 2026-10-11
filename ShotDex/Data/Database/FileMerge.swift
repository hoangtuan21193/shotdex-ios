import Foundation
import GRDB

/// Merge in Duplicates when the kept photo is a file (FS-19.04 §4): it takes
/// only the stars, the flag and the keywords its duplicates have and it
/// lacks — into ShotDex's tables, and from there into its sidecar. Favorite,
/// location and the earliest capture date stay Photos-only (FS-06.06b §2):
/// a file's bytes are never edited.
enum FileMerge {
    static func inherit(_ db: Database, keeper: String, from others: [String], at: Int) throws {
        guard !others.isEmpty else { return }
        let marks = databaseQuestionMarks(count: others.count)
        let keeperRating = try Int.fetchOne(db, sql: "SELECT rating FROM photo_user_marks WHERE photoId = ?", arguments: [keeper]) ?? 0
        if keeperRating == 0,
           let rating = try Int.fetchOne(db, sql: "SELECT MAX(rating) FROM photo_user_marks WHERE photoId IN (\(marks)) AND rating > 0",
                                         arguments: StatementArguments(others)) {
            try db.execute(sql: """
                INSERT INTO photo_user_marks (photoId, rating, ratingAt) VALUES (?, ?, ?)
                ON CONFLICT(photoId) DO UPDATE SET rating = excluded.rating, ratingAt = excluded.ratingAt
                """, arguments: [keeper, rating, at])
        }
        // A Pick travels; a Reject on a photo being merged away does not
        // make the kept one rejected.
        let keeperFlag = try String.fetchOne(db, sql: "SELECT flag FROM photo_flag WHERE assetId = ?", arguments: [keeper])
        if keeperFlag == nil,
           try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM photo_flag WHERE assetId IN (\(marks)) AND flag = ?)",
                             arguments: StatementArguments(others + [PhotoFlag.pick.rawValue])) == true {
            try db.execute(sql: "INSERT INTO photo_flag (assetId, flag, flaggedAt) VALUES (?, ?, ?)",
                           arguments: [keeper, PhotoFlag.pick.rawValue, at])
        }
        let keywords = try String.fetchAll(db, sql: """
            SELECT keyword FROM photo_user_keyword WHERE photoId IN (\(marks))
            UNION SELECT keyword FROM photo_keyword WHERE assetId IN (\(marks))
            """, arguments: StatementArguments(others + others))
        try PhotoUserMarksStore.addKeywords(db, keywords.sorted(), photoId: keeper, at: at)
    }

    /// The Merge confirmation when the kept photos are files.
    static func confirmation(marked: Int) -> String {
        String(localized: "Keeps one copy in each group and marks \(marked) photos for deletion. The kept photo takes the stars, flag and keywords of its copies — saved in ShotDex and its sidecar. Nothing is deleted until you tap Delete.",
               comment: "Duplicates: merge confirmation when the kept photos are files")
    }
}
