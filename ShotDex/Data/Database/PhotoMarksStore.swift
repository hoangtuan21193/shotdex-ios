import Foundation
import GRDB

/// Pick/Reject flags and the star ratings still waiting to go to Photos
/// (FS-01.12 §4) — the two tables of `v27-ratingsAndFlags`.
///
/// Both are user data: nothing here is ever rewritten by the indexer, and
/// Clear local metadata index does not touch them. Rows go only when the
/// user clears the mark, or the photo is deleted (`UserMarkRemovalPolicy`).
struct PhotoMarksStore: Sendable {
    let database: AppDatabase

    // MARK: SQL

    /// The current star rating of a `photo_metadata` row, as SQL: the pending
    /// row when there is one, else what Photos holds, else 0. Written with
    /// `IN (SELECT …)` rather than a correlated subquery so it needs no table
    /// alias — the grid, smart album and statistics queries name the table
    /// differently.
    static func ratingCondition(_ filter: RatingFilter) -> String {
        let pendingTest: String
        let photosTest: String
        switch filter {
        case .atLeast(let stars):
            let stars = StarRating.clamped(stars)
            pendingTest = "rating >= \(stars)"
            photosTest = "COALESCE(rating, 0) >= \(stars)"
        case .unrated:
            pendingTest = "rating = 0"
            photosTest = "COALESCE(rating, 0) = 0"
        }
        return ratingSQL(pendingTest: pendingTest, photosTest: photosTest)
    }

    /// `is`/`atLeast`/`atMost` on the current rating, for smart albums.
    static func ratingSQL(comparison: String, stars: Int) -> String {
        let stars = StarRating.clamped(stars)
        return ratingSQL(
            pendingTest: "rating \(comparison) \(stars)",
            photosTest: "COALESCE(rating, 0) \(comparison) \(stars)"
        )
    }

    private static func ratingSQL(pendingTest: String, photosTest: String) -> String {
        """
        (assetId IN (SELECT assetId FROM pending_photo_rating WHERE \(pendingTest)) \
        OR (assetId NOT IN (SELECT assetId FROM pending_photo_rating) AND \(photosTest)))
        """
    }

    /// Any of the given flag filters, as SQL on `assetId`.
    static func flagCondition(_ filters: Set<PhotoFlagFilter>) -> String? {
        guard !filters.isEmpty, filters.count < PhotoFlagFilter.allCases.count else { return nil }
        let tests = filters.sorted { $0.rawValue < $1.rawValue }.map { filter -> String in
            switch filter {
            case .picks: "assetId IN (SELECT assetId FROM photo_flag WHERE flag = '\(PhotoFlag.pick.rawValue)')"
            case .rejected: "assetId IN (SELECT assetId FROM photo_flag WHERE flag = '\(PhotoFlag.reject.rawValue)')"
            case .unflagged: "assetId NOT IN (SELECT assetId FROM photo_flag)"
            }
        }
        return "(" + tests.joined(separator: " OR ") + ")"
    }

    // MARK: Reads

    /// Every flag, for the in-memory index the grid reads.
    func allFlags() throws -> [String: PhotoFlag] {
        try database.reader.read { db in
            var result: [String: PhotoFlag] = [:]
            let rows = try Row.fetchCursor(db, sql: "SELECT assetId, flag FROM photo_flag")
            while let row = try rows.next() {
                if let flag = PhotoFlag(rawValue: row["flag"]) { result[row["assetId"]] = flag }
            }
            return result
        }
    }

    /// Every pending rating, for the in-memory index.
    func allPendingRatings() throws -> [String: Int] {
        try database.reader.read { db in
            var result: [String: Int] = [:]
            let rows = try Row.fetchCursor(db, sql: "SELECT assetId, rating FROM pending_photo_rating")
            while let row = try rows.next() {
                result[row["assetId"]] = row["rating"]
            }
            return result
        }
    }

    /// Pending ratings with when they were set — the star migration reads
    /// these so it only deletes rows it actually wrote (FS-01.12 §5).
    func pendingRatingRows() throws -> [PendingRating] {
        try database.reader.read { db in
            try Row.fetchAll(db, sql: "SELECT assetId, rating, ratedAt FROM pending_photo_rating").map {
                PendingRating(assetId: $0["assetId"], rating: $0["rating"], ratedAt: $0["ratedAt"])
            }
        }
    }

    func pendingRatingCount() throws -> Int {
        try database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pending_photo_rating") ?? 0
        }
    }

    // MARK: Writes

    /// Sets (or, with `nil`, clears) the flag of every id in one transaction.
    func setFlag(_ flag: PhotoFlag?, ids: [String], at date: Date = Date()) throws {
        guard !ids.isEmpty else { return }
        let stamp = Int(date.timeIntervalSince1970)
        try database.writer.write { db in
            for id in ids {
                if let flag {
                    try db.execute(
                        sql: "INSERT OR REPLACE INTO photo_flag (assetId, flag, flaggedAt) VALUES (?, ?, ?)",
                        arguments: [id, flag.rawValue, stamp]
                    )
                } else {
                    try db.execute(sql: "DELETE FROM photo_flag WHERE assetId = ?", arguments: [id])
                }
            }
        }
    }

    /// Restores flags exactly as they were — an undo of `setFlag`.
    func restoreFlags(_ flags: [String: PhotoFlag?]) throws {
        guard !flags.isEmpty else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        try database.writer.write { db in
            for (id, flag) in flags {
                if let flag {
                    try db.execute(
                        sql: "INSERT OR REPLACE INTO photo_flag (assetId, flag, flaggedAt) VALUES (?, ?, ?)",
                        arguments: [id, flag.rawValue, stamp]
                    )
                } else {
                    try db.execute(sql: "DELETE FROM photo_flag WHERE assetId = ?", arguments: [id])
                }
            }
        }
    }

    /// Writes a pending rating for every id. A 0 is stored too: "the user
    /// cleared the stars" has to win over whatever Photos holds until it is
    /// written there.
    func setPendingRating(_ rating: Int, ids: [String], at date: Date = Date()) throws {
        guard !ids.isEmpty else { return }
        let stamp = Int(date.timeIntervalSince1970)
        let rating = StarRating.clamped(rating)
        try database.writer.write { db in
            for id in ids {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO pending_photo_rating (assetId, rating, ratedAt) VALUES (?, ?, ?)",
                    arguments: [id, rating, stamp]
                )
            }
        }
    }

    /// Puts pending rows back as they were (`nil` = no row) — an undo.
    func restorePendingRatings(_ ratings: [String: Int?]) throws {
        guard !ratings.isEmpty else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        try database.writer.write { db in
            for (id, rating) in ratings {
                if let rating {
                    try db.execute(
                        sql: "INSERT OR REPLACE INTO pending_photo_rating (assetId, rating, ratedAt) VALUES (?, ?, ?)",
                        arguments: [id, rating, stamp]
                    )
                } else {
                    try db.execute(sql: "DELETE FROM pending_photo_rating WHERE assetId = ?", arguments: [id])
                }
            }
        }
    }

    /// Drops pending rows — once Photos holds the rating, or the photo is gone.
    func deletePendingRatings(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try database.writer.write { db in
            for chunk in stride(from: 0, to: ids.count, by: 500) {
                let slice = Array(ids[chunk..<min(chunk + 500, ids.count)])
                try db.execute(
                    sql: "DELETE FROM pending_photo_rating WHERE assetId IN (\(databaseQuestionMarks(count: slice.count)))",
                    arguments: StatementArguments(slice)
                )
            }
        }
    }

    /// Drops every mark of photos that no longer exist.
    func deleteMarks(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try database.writer.write { db in
            for chunk in stride(from: 0, to: ids.count, by: 500) {
                let slice = Array(ids[chunk..<min(chunk + 500, ids.count)])
                let marks = databaseQuestionMarks(count: slice.count)
                try db.execute(sql: "DELETE FROM photo_flag WHERE assetId IN (\(marks))", arguments: StatementArguments(slice))
                try db.execute(sql: "DELETE FROM pending_photo_rating WHERE assetId IN (\(marks))", arguments: StatementArguments(slice))
            }
        }
    }
}

/// One row of `pending_photo_rating`.
struct PendingRating: Equatable, Sendable {
    let assetId: String
    let rating: Int
    let ratedAt: Int
}
