import Foundation
import GRDB

/// Stars, favorite, title, caption and keywords of file photos —
/// `photo_user_marks` and `photo_user_keyword` of `v30-photoSources`
/// (FS-19.05 §3). User data: the indexer never rewrites these rows, and
/// Clear Local Metadata Index keeps them.
///
/// Every single-value field carries the time it changed, so a sidecar read
/// and a change made in ShotDex settle the same way a merge does: the later
/// change wins, field by field (FS-19.02 §6).
struct PhotoUserMarksStore: Sendable {
    let database: AppDatabase

    /// Every file photo's stars, for the in-memory index the grid reads.
    func allRatings() throws -> [String: Int] {
        try database.reader.read { db in
            var result: [String: Int] = [:]
            let rows = try Row.fetchCursor(db, sql: """
                SELECT photoId, rating FROM photo_user_marks
                WHERE rating IS NOT NULL AND photoId NOT IN (SELECT id FROM photos WHERE orphanedAt IS NOT NULL)
                """)
            while let row = try rows.next() {
                result[row["photoId"]] = row["rating"]
            }
            return result
        }
    }

    /// Takes what a sidecar written at `at` says into ShotDex: each field
    /// only when the sidecar changed after ShotDex last did; keywords are a
    /// set, so the sidecar's join the photo's. A Reject in the sidecar is the
    /// shared Reject flag (FS-19.02 §4); the photo's own stars stay as they
    /// were, because a −1 in the standard field says nothing about them.
    static func applySidecar(_ db: Database, values: SidecarValues, photoId: String, at: Int) throws {
        if let rating = values.rating {
            try setField(db, "rating", "ratingAt", value: rating, photoId: photoId, at: at)
        }
        if let title = values.title {
            try setField(db, "title", "titleAt", value: title, photoId: photoId, at: at)
        }
        if let caption = values.caption {
            try setField(db, "caption", "captionAt", value: caption, photoId: photoId, at: at)
        }
        if values.isRejected {
            try db.execute(sql: """
                INSERT INTO photo_flag (assetId, flag, flaggedAt) VALUES (?, ?, ?)
                ON CONFLICT(assetId) DO UPDATE SET flag = excluded.flag, flaggedAt = excluded.flaggedAt
                WHERE photo_flag.flaggedAt < excluded.flaggedAt
                """, arguments: [photoId, PhotoFlag.reject.rawValue, at])
        }
        try addKeywords(db, values.keywords, photoId: photoId, at: at)
    }

    /// Adds keywords to a photo, skipping any it already has in another case.
    static func addKeywords(_ db: Database, _ keywords: [String], photoId: String, at: Int) throws {
        guard !keywords.isEmpty else { return }
        var have = Set(try String.fetchAll(db, sql: "SELECT caseKey FROM photo_user_keyword WHERE photoId = ?", arguments: [photoId]))
        for keyword in keywords where have.insert(KeywordInput.caseKey(keyword)).inserted {
            try db.execute(sql: "INSERT INTO photo_user_keyword (photoId, keyword, caseKey, foldKey, addedAt) VALUES (?, ?, ?, ?, ?)",
                           arguments: [photoId, keyword, KeywordInput.caseKey(keyword), KeywordInput.foldKey(keyword), at])
        }
    }

    private static func setField(_ db: Database, _ column: String, _ stampColumn: String,
                                 value: some DatabaseValueConvertible, photoId: String, at: Int) throws {
        try db.execute(sql: """
            INSERT INTO photo_user_marks (photoId, \(column), \(stampColumn)) VALUES (?, ?, ?)
            ON CONFLICT(photoId) DO UPDATE SET \(column) = excluded.\(column), \(stampColumn) = excluded.\(stampColumn)
            WHERE photo_user_marks.\(stampColumn) IS NULL OR photo_user_marks.\(stampColumn) < excluded.\(stampColumn)
            """, arguments: [photoId, value, at])
    }
}
