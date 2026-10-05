import Foundation
import GRDB

/// The app's mirror of Photos' own caption and keywords (FS-02.07 §8) —
/// `photo_keyword` and `photo_caption` of `v28-captionKeywordMirror`.
///
/// A copy, not user data: Photos holds the truth, the mirror is rebuilt from
/// it. So its rows follow `photo_metadata` — gone when the photo goes
/// (`MetadataStore.deleteAssets`), cleared with Clear local metadata index —
/// but the indexer never writes them, and a full reindex leaves them as they
/// are. Every read that reaches the user joins `photo_metadata`, so a row
/// whose photo left the index (or is not shared under `.limited`) never shows.
struct PhotoKeywordStore: Sendable {
    let database: AppDatabase

    /// Where the full read of the mirror stands.
    struct PassState: Equatable, Sendable {
        /// The last asset id the full read finished; nil before it starts.
        var cursorAssetId: String?
        /// When the full read last reached the end; nil until it has.
        var completedAt: Int?

        static let initial = PassState()
    }

    // MARK: SQL

    /// Photos carrying a keyword, as SQL on `assetId` — matched on the
    /// folded key, so `sunset`, `Sunset` and `súnset` are one (FS-02.07 §7).
    static func keywordCondition(has keyword: String) -> (sql: String, arguments: StatementArguments) {
        ("assetId IN (SELECT assetId FROM (\(everyKeywordSQL)) WHERE foldKey = ?)", [KeywordInput.foldKey(keyword)])
    }

    static func keywordCondition(lacks keyword: String) -> (sql: String, arguments: StatementArguments) {
        ("assetId NOT IN (SELECT assetId FROM (\(everyKeywordSQL)) WHERE foldKey = ?)", [KeywordInput.foldKey(keyword)])
    }

    /// Every keyword of every photo: the mirror of Photos' keywords and the
    /// keywords of file photos (`photo_user_keyword`) — a keyword filter
    /// reads both (FS-19.05 §6). Columns `assetId`, `keyword`, `caseKey`,
    /// `foldKey`.
    static let everyKeywordSQL = """
        SELECT assetId, keyword, caseKey, foldKey FROM photo_keyword \
        UNION ALL SELECT photoId, keyword, caseKey, foldKey FROM photo_user_keyword
        """

    static let hasAnyKeywordSQL = "assetId IN (SELECT assetId FROM (\(everyKeywordSQL)))"
    static let hasNoKeywordsSQL = "assetId NOT IN (SELECT assetId FROM (\(everyKeywordSQL)))"

    // MARK: Writes

    /// Replaces the mirror of each given asset with what Photos holds now —
    /// one transaction, so a reader never sees half an asset.
    func replace(_ values: [String: CaptionKeywords]) throws {
        guard !values.isEmpty else { return }
        try database.writer.write { db in
            try Self.replace(db, values)
        }
    }

    static func replace(_ db: Database, _ values: [String: CaptionKeywords]) throws {
        for (assetId, value) in values {
            try db.execute(sql: "DELETE FROM photo_keyword WHERE assetId = ?", arguments: [assetId])
            try db.execute(sql: "DELETE FROM photo_caption WHERE assetId = ?", arguments: [assetId])
            for keyword in value.keywords where !keyword.isEmpty {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO photo_keyword (assetId, keyword, caseKey, foldKey) VALUES (?, ?, ?, ?)",
                    arguments: [assetId, keyword, KeywordInput.caseKey(keyword), KeywordInput.foldKey(keyword)]
                )
            }
            if let caption = value.caption {
                try db.execute(
                    sql: "INSERT INTO photo_caption (assetId, caption, foldKey) VALUES (?, ?, ?)",
                    arguments: [assetId, caption, KeywordInput.foldKey(caption)]
                )
            }
        }
    }

    /// One page of the full read: every id in `ids` takes the value Photos
    /// returned, or loses its rows when Photos returned none — and the pass
    /// state moves on, all in one transaction.
    func replace(ids: [String], with values: [String: CaptionKeywords], state: PassState?) throws {
        try database.writer.write { db in
            try Self.replace(db, Dictionary(uniqueKeysWithValues: ids.map { ($0, values[$0] ?? .empty) }))
            if let state { try Self.save(db, state) }
        }
    }

    /// Drops the mirror of assets that are gone. Called inside the
    /// transaction that removes their `photo_metadata` rows.
    static func delete(_ db: Database, ids: [String]) throws {
        for assetId in ids {
            try db.execute(sql: "DELETE FROM photo_keyword WHERE assetId = ?", arguments: [assetId])
            try db.execute(sql: "DELETE FROM photo_caption WHERE assetId = ?", arguments: [assetId])
        }
    }

    /// Clear local metadata index: the mirror and where its read stood go
    /// too, and are read again from Photos.
    static func deleteAll(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM photo_keyword")
        try db.execute(sql: "DELETE FROM photo_caption")
        try db.execute(sql: "DELETE FROM extended_metadata_state")
    }

    /// Mirror rows of assets that are no longer indexed — dropped at the end
    /// of a full read.
    func deleteOrphans() throws {
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM photo_keyword WHERE assetId NOT IN (SELECT assetId FROM photo_metadata)")
            try db.execute(sql: "DELETE FROM photo_caption WHERE assetId NOT IN (SELECT assetId FROM photo_metadata)")
        }
    }

    func savePassState(_ state: PassState) throws {
        try database.writer.write { db in try Self.save(db, state) }
    }

    private static func save(_ db: Database, _ state: PassState) throws {
        try db.execute(
            sql: "INSERT OR REPLACE INTO extended_metadata_state (id, cursorAssetId, completedAt) VALUES (1, ?, ?)",
            arguments: [state.cursorAssetId, state.completedAt]
        )
    }

    // MARK: Reads

    func passState() throws -> PassState {
        try database.reader.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT cursorAssetId, completedAt FROM extended_metadata_state WHERE id = 1")
            else { return .initial }
            return PassState(cursorAssetId: row["cursorAssetId"], completedAt: row["completedAt"])
        }
    }

    /// The next page of indexed ids for the full read, in id order.
    func indexedAssetIds(after cursor: String?, limit: Int) throws -> [String] {
        try database.reader.read { db in
            if let cursor {
                return try String.fetchAll(
                    db, sql: "SELECT assetId FROM photo_metadata WHERE assetId > ? ORDER BY assetId LIMIT ?",
                    arguments: [cursor, limit]
                )
            }
            return try String.fetchAll(
                db, sql: "SELECT assetId FROM photo_metadata ORDER BY assetId LIMIT ?", arguments: [limit]
            )
        }
    }

    /// The mirror of one asset; `.empty` when it has none.
    func value(assetId: String) throws -> CaptionKeywords {
        try values(ids: [assetId])[assetId] ?? .empty
    }

    /// The mirror of the given assets, keywords in insertion order.
    func values(ids: [String]) throws -> [String: CaptionKeywords] {
        guard !ids.isEmpty else { return [:] }
        return try database.reader.read { db in
            var result: [String: CaptionKeywords] = [:]
            for chunk in stride(from: 0, to: ids.count, by: 500).map({ Array(ids[$0..<min($0 + 500, ids.count)]) }) {
                let marks = databaseQuestionMarks(count: chunk.count)
                let keywords = try Row.fetchAll(
                    db,
                    sql: "SELECT assetId, keyword FROM photo_keyword WHERE assetId IN (\(marks)) ORDER BY rowid",
                    arguments: StatementArguments(chunk)
                )
                for row in keywords {
                    result[row["assetId"], default: .empty].keywords.append(row["keyword"])
                }
                let captions = try Row.fetchAll(
                    db,
                    sql: "SELECT assetId, caption FROM photo_caption WHERE assetId IN (\(marks))",
                    arguments: StatementArguments(chunk)
                )
                for row in captions {
                    result[row["assetId"], default: .empty].caption = row["caption"]
                }
            }
            return result
        }
    }

    /// Every keyword on an indexed photo, counted over all its spellings and
    /// shown in the spelling most photos use — the suggestions and the
    /// search vocabulary (FS-02.07 §4, §8). Joins `photo_metadata`, so under
    /// `.limited` a keyword that lives only on photos not shared never shows
    /// (AC-16).
    func keywordCounts() throws -> [KeywordCount] {
        try database.reader.read { db in
            let spellings = try Row.fetchAll(
                db,
                sql: """
                    SELECT k.caseKey, k.keyword, COUNT(*) AS n
                    FROM (\(Self.everyKeywordSQL)) k JOIN photo_metadata m ON m.assetId = k.assetId
                    GROUP BY k.caseKey, k.keyword
                    """
            )
            var best: [String: (keyword: String, count: Int, total: Int)] = [:]
            for row in spellings {
                let key: String = row["caseKey"]
                let keyword: String = row["keyword"]
                let count: Int = row["n"]
                if let entry = best[key],
                   entry.count > count || (entry.count == count && entry.keyword < keyword) {
                    continue
                }
                best[key] = (keyword, count, 0)
            }
            // A photo carrying two spellings counts once.
            let totals = try Row.fetchAll(
                db,
                sql: """
                    SELECT k.caseKey, COUNT(DISTINCT k.assetId) AS n
                    FROM (\(Self.everyKeywordSQL)) k JOIN photo_metadata m ON m.assetId = k.assetId
                    GROUP BY k.caseKey
                    """
            )
            for row in totals {
                let key: String = row["caseKey"]
                best[key]?.total = row["n"]
            }
            return best.values
                .map { KeywordCount(keyword: $0.keyword, count: $0.total) }
                .sorted {
                    if $0.count != $1.count { return $0.count > $1.count }
                    return $0.keyword.localizedStandardCompare($1.keyword) == .orderedAscending
                }
        }
    }
}
