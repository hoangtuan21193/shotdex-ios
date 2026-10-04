import Foundation
import GRDB

/// Photos, their copies, and merging two photos into one (FS-19.05 §4).
struct PhotoIdentityStore: Sendable {
    let database: AppDatabase

    /// Merges the photos `a` and `b`, found to be one picture, in one
    /// transaction: copies move to the older id, user data merges by
    /// `PhotoMergePlan`, pending sidecar writes follow, the loser's scan
    /// results go, and an alias keeps the loser's id findable.
    @discardableResult
    func merge(_ a: String, _ b: String, at now: Date = Date()) throws -> PhotoMergePlan.Result {
        try database.writer.write { db in
            try Self.merge(db, a, b, now: Int(now.timeIntervalSince1970))
        }
    }

    static func merge(_ db: Database, _ a: String, _ b: String, now: Int) throws -> PhotoMergePlan.Result {
        let sides = try [a, b].map { id in
            PhotoMergePlan.Side(id: id, createdAt: try Int.fetchOne(db, sql: "SELECT createdAt FROM photos WHERE id = ?", arguments: [id]) ?? now,
                                data: try userData(db, id))
        }
        let result = PhotoMergePlan.merge(sides[0], sides[1])
        let winner = result.winnerId, loser = result.loserId
        let both: StatementArguments = [winner, loser]

        try db.execute(sql: "UPDATE photo_copies SET photoId = ? WHERE photoId = ?", arguments: both)
        try db.execute(sql: "UPDATE pending_sidecar SET photoId = ? WHERE photoId = ?", arguments: both)
        try db.execute(sql: "UPDATE photo_aliases SET winnerId = ? WHERE winnerId = ?", arguments: both)
        try db.execute(sql: "INSERT OR REPLACE INTO photo_aliases (loserId, winnerId, mergedAt) VALUES (?, ?, ?)",
                       arguments: [loser, winner, now])

        for (table, column) in [("photo_user_marks", "photoId"), ("photo_user_keyword", "photoId"), ("photo_flag", "assetId"),
                                ("photo_recipes", "photoId"), ("pending_photo_rating", "assetId")] {
            try db.execute(sql: "DELETE FROM \(table) WHERE \(column) IN (?, ?)", arguments: both)
        }
        try write(db, result.data, for: winner, now: now)

        // Album places: join, then drop the loser's.
        try db.execute(sql: """
            INSERT OR IGNORE INTO shotdex_album_members (albumId, photoId, addedAt)
            SELECT albumId, ?, addedAt FROM shotdex_album_members WHERE photoId = ?
            """, arguments: both)
        try db.execute(sql: "DELETE FROM shotdex_album_members WHERE photoId = ?", arguments: [loser])

        // The loser's scan results and its Photos mirror are rebuilt from
        // the winner's copies.
        for (table, column) in [("photo_metadata", "assetId"), ("photo_keyword", "assetId"), ("photo_caption", "assetId"),
                                ("perceptual_hash", "assetId"), ("subject_scan", "assetId"), ("raw_pair_assets", "assetId"),
                                ("duplicate_groups", "assetId")] {
            try db.execute(sql: "DELETE FROM \(table) WHERE \(column) = ?", arguments: [loser])
        }
        try db.execute(sql: "DELETE FROM photos WHERE id = ?", arguments: [loser])
        try db.execute(sql: "UPDATE photos SET orphanedAt = NULL WHERE id = ?", arguments: [winner])
        return result
    }

    /// What the user typed about `id`, from every table it may live in.
    static func userData(_ db: Database, _ id: String) throws -> PhotoUserData {
        var data = PhotoUserData()
        if let row = try Row.fetchOne(db, sql: "SELECT * FROM photo_user_marks WHERE photoId = ?", arguments: [id]) {
            if let value: Int = row["rating"] { data.rating = Stamped(value: value, at: row["ratingAt"] ?? 0) }
            if let value: Bool = row["isFavorite"] { data.isFavorite = Stamped(value: value, at: row["favoriteAt"] ?? 0) }
            if let value: String = row["title"] { data.title = Stamped(value: value, at: row["titleAt"] ?? 0) }
            if let value: String = row["caption"] { data.caption = Stamped(value: value, at: row["captionAt"] ?? 0) }
        }
        // A star waiting to reach Photos is the Photos copy's rating.
        if let row = try Row.fetchOne(db, sql: "SELECT rating, ratedAt FROM pending_photo_rating WHERE assetId = ?", arguments: [id]) {
            data.rating = PhotoMergePlan.latest(data.rating, Stamped(value: row["rating"], at: row["ratedAt"]))
        }
        if let row = try Row.fetchOne(db, sql: "SELECT flag, flaggedAt FROM photo_flag WHERE assetId = ?", arguments: [id]) {
            data.flag = Stamped(value: row["flag"], at: row["flaggedAt"])
        }
        if let row = try Row.fetchOne(db, sql: "SELECT recipe, updatedAt FROM photo_recipes WHERE photoId = ?", arguments: [id]) {
            data.recipe = Stamped(value: row["recipe"], at: row["updatedAt"])
        }
        // Keywords the user typed on a file, and those Photos holds for the
        // asset (FS-02.07 mirror): after a merge ShotDex owns both.
        data.keywords = Set(try String.fetchAll(db, sql: """
            SELECT keyword FROM photo_user_keyword WHERE photoId = ?
            UNION SELECT keyword FROM photo_keyword WHERE assetId = ?
            """, arguments: [id, id]))
        data.albumIds = Set(try String.fetchAll(db, sql: "SELECT albumId FROM shotdex_album_members WHERE photoId = ?", arguments: [id]))
        return data
    }

    private static func write(_ db: Database, _ data: PhotoUserData, for id: String, now: Int) throws {
        if data.rating != nil || data.isFavorite != nil || data.title != nil || data.caption != nil {
            try db.execute(sql: """
                INSERT INTO photo_user_marks (photoId, rating, ratingAt, isFavorite, favoriteAt, title, titleAt, caption, captionAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [id, data.rating?.value, data.rating?.at, data.isFavorite?.value, data.isFavorite?.at,
                                 data.title?.value, data.title?.at, data.caption?.value, data.caption?.at])
        }
        var seen = Set<String>()
        for keyword in data.keywords.sorted() where seen.insert(KeywordInput.caseKey(keyword)).inserted {
            try db.execute(sql: "INSERT INTO photo_user_keyword (photoId, keyword, caseKey, foldKey, addedAt) VALUES (?, ?, ?, ?, ?)",
                           arguments: [id, keyword, KeywordInput.caseKey(keyword), KeywordInput.foldKey(keyword), now])
        }
        if let flag = data.flag {
            try db.execute(sql: "INSERT INTO photo_flag (assetId, flag, flaggedAt) VALUES (?, ?, ?)", arguments: [id, flag.value, flag.at])
        }
        if let recipe = data.recipe {
            try db.execute(sql: "INSERT INTO photo_recipes (photoId, recipe, updatedAt) VALUES (?, ?, ?)", arguments: [id, recipe.value, recipe.at])
        }
        // The winner's Photos copy still has to hear about the merged star.
        // Keyed by the asset, which may not be the surviving id.
        if let rating = data.rating,
           let assetId = try String.fetchOne(db, sql: "SELECT photoKitId FROM photo_copies WHERE photoId = ? AND kind = 'photos'", arguments: [id]) {
            try db.execute(sql: "INSERT OR REPLACE INTO pending_photo_rating (assetId, rating, ratedAt) VALUES (?, ?, ?)",
                           arguments: [assetId, rating.value, rating.at])
        }
    }
}
