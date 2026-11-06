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

    /// Which of `ids` have a file copy and which a Photos copy. A photo with
    /// a file copy keeps its stars here; one with a Photos copy also sends
    /// them to Photos (FS-19.05 §2). An id with no copy row at all is a
    /// Photos asset the copy table has not caught up with.
    func copyKinds(ids: [String]) throws -> (files: Set<String>, photos: Set<String>) {
        guard !ids.isEmpty else { return ([], []) }
        return try database.reader.read { db in
            var files = Set<String>(), photos = Set<String>()
            for chunk in stride(from: 0, to: ids.count, by: 500).map({ Array(ids[$0..<min($0 + 500, ids.count)]) }) {
                let rows = try Row.fetchAll(db, sql: "SELECT DISTINCT photoId, kind FROM photo_copies WHERE photoId IN (\(databaseQuestionMarks(count: chunk.count)))",
                                            arguments: StatementArguments(chunk))
                for row in rows {
                    let kind: String = row["kind"]
                    if kind == "photos" { photos.insert(row["photoId"]) } else { files.insert(row["photoId"]) }
                }
            }
            return (files, photos)
        }
    }

    /// Sets the stars of file photos, each as of `date`. 0 is kept as 0 — a
    /// sidecar that said ★3 has to be told the stars went.
    func setRatings(_ ratings: [String: Int], at date: Date = Date()) throws {
        guard !ratings.isEmpty else { return }
        let stamp = Int(date.timeIntervalSince1970)
        try database.writer.write { db in
            for (id, rating) in ratings {
                try db.execute(sql: """
                    INSERT INTO photo_user_marks (photoId, rating, ratingAt) VALUES (?, ?, ?)
                    ON CONFLICT(photoId) DO UPDATE SET rating = excluded.rating, ratingAt = excluded.ratingAt
                    """, arguments: [id, StarRating.clamped(rating), stamp])
            }
        }
    }

    /// Sets the favorite of file photos, as of `date`.
    func setFavorite(_ isFavorite: Bool, ids: [String], at date: Date = Date()) throws {
        guard !ids.isEmpty else { return }
        let stamp = Int(date.timeIntervalSince1970)
        try database.writer.write { db in
            for id in ids {
                try db.execute(sql: """
                    INSERT INTO photo_user_marks (photoId, isFavorite, favoriteAt) VALUES (?, ?, ?)
                    ON CONFLICT(photoId) DO UPDATE SET isFavorite = excluded.isFavorite, favoriteAt = excluded.favoriteAt
                    """, arguments: [id, isFavorite, stamp])
            }
        }
    }

    /// Takes what a sidecar written at `at` says into ShotDex: each field
    /// only when the sidecar changed after ShotDex last did; keywords are a
    /// set, so the sidecar's join the photo's. A Reject in the sidecar is the
    /// shared Reject flag (FS-19.02 §4); the photo's stars come from
    /// ShotDex's namespace then, because a −1 in the standard field says
    /// nothing about them. Pick, favorite and the recipe come from there too.
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
        if let isFavorite = values.isFavorite {
            try setField(db, "isFavorite", "favoriteAt", value: isFavorite, photoId: photoId, at: at)
        }
        if values.isRejected || values.isPicked {
            let flag = values.isRejected ? PhotoFlag.reject : PhotoFlag.pick
            try db.execute(sql: """
                INSERT INTO photo_flag (assetId, flag, flaggedAt) VALUES (?, ?, ?)
                ON CONFLICT(assetId) DO UPDATE SET flag = excluded.flag, flaggedAt = excluded.flaggedAt
                WHERE photo_flag.flaggedAt < excluded.flaggedAt
                """, arguments: [photoId, flag.rawValue, at])
        }
        if let recipe = values.recipe {
            try db.execute(sql: """
                INSERT INTO photo_recipes (photoId, recipe, updatedAt) VALUES (?, ?, ?)
                ON CONFLICT(photoId) DO UPDATE SET recipe = excluded.recipe, updatedAt = excluded.updatedAt
                WHERE photo_recipes.updatedAt < excluded.updatedAt
                """, arguments: [photoId, recipe, at])
        }
        try addKeywords(db, values.keywords, photoId: photoId, at: at)
    }

    /// Adds one keyword to every photo, in one transaction (the Mac
    /// inspector's "Add keyword to all"); a photo that has it in another case
    /// keeps its own spelling.
    func addKeyword(_ keyword: String, photoIds: [String], at date: Date = Date()) throws {
        guard !photoIds.isEmpty else { return }
        let stamp = Int(date.timeIntervalSince1970)
        let key = KeywordInput.caseKey(keyword), fold = KeywordInput.foldKey(keyword)
        try database.writer.write { db in
            // One look-up per 900 photos, not one per photo.
            for start in stride(from: 0, to: photoIds.count, by: 900) {
                let chunk = Array(photoIds[start..<min(photoIds.count, start + 900)])
                let have = Set(try String.fetchAll(db, sql: """
                    SELECT photoId FROM photo_user_keyword WHERE caseKey = ? AND photoId IN (\(databaseQuestionMarks(count: chunk.count)))
                    """, arguments: StatementArguments([key] + chunk)))
                for id in chunk where !have.contains(id) {
                    try db.execute(sql: "INSERT INTO photo_user_keyword (photoId, keyword, caseKey, foldKey, addedAt) VALUES (?, ?, ?, ?, ?)",
                                   arguments: [id, keyword, key, fold, stamp])
                }
            }
        }
    }

    /// A file photo's title or caption as typed in Get Info; empty clears it.
    /// The time stamp makes it win over an older sidecar value (FS-19.02 §6).
    func setTitle(_ title: String, photoIds: [String], at date: Date = Date()) throws {
        try setText(title, column: "title", stamp: "titleAt", photoIds: photoIds, at: date)
    }

    func setCaption(_ caption: String, photoIds: [String], at date: Date = Date()) throws {
        try setText(caption, column: "caption", stamp: "captionAt", photoIds: photoIds, at: date)
    }

    private func setText(_ text: String, column: String, stamp: String, photoIds: [String], at date: Date) throws {
        guard !photoIds.isEmpty else { return }
        let value: String? = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        let at = Int(date.timeIntervalSince1970)
        try database.writer.write { db in
            for id in photoIds {
                // Typing saves several times a second: a save in the same
                // second as the last one still wins (`<=`), unlike a sidecar
                // read, which must be strictly newer (`setField`).
                try db.execute(sql: """
                    INSERT INTO photo_user_marks (photoId, \(column), \(stamp)) VALUES (?, ?, ?)
                    ON CONFLICT(photoId) DO UPDATE SET \(column) = excluded.\(column), \(stamp) = excluded.\(stamp)
                    WHERE photo_user_marks.\(stamp) IS NULL OR photo_user_marks.\(stamp) <= excluded.\(stamp)
                    """, arguments: [id, value, at])
            }
        }
    }

    /// Takes a keyword off every photo, in any case (`caseKey`).
    func removeKeyword(_ keyword: String, photoIds: [String]) throws {
        guard !photoIds.isEmpty else { return }
        let key = KeywordInput.caseKey(keyword)
        try database.writer.write { db in
            for start in stride(from: 0, to: photoIds.count, by: 900) {
                let chunk = Array(photoIds[start..<min(photoIds.count, start + 900)])
                try db.execute(sql: "DELETE FROM photo_user_keyword WHERE caseKey = ? AND photoId IN (\(databaseQuestionMarks(count: chunk.count)))",
                               arguments: StatementArguments([key] + chunk))
            }
        }
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
