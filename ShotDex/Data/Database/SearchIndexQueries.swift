import Foundation
import GRDB

/// Reads the search index (FS-01.03c §1–§3). Every call runs on GRDB's reader
/// pool, never on the main actor, and a cancelled task interrupts its
/// statement — what lets each keystroke replace the last one (A2).
struct SearchIndexQueries: Sendable {
    let database: AppDatabase

    /// Groups whose folded name has every typed word as a word prefix
    /// (`can r6` → `Canon EOS R6`), unranked.
    func groups(matching text: String, limit: Int = 300) async throws -> [SearchGroup] {
        guard let match = SearchFolding.ftsPrefixQuery(text) else { return [] }
        return try await database.reader.read { db in
            try Self.decode(Row.fetchAll(db, sql: """
                SELECT g.id, g.category, g.name, g.count, g.keyAssetId, g.rule
                FROM search_group_fts
                JOIN search_group g ON g.id = search_group_fts.rowid
                WHERE search_group_fts MATCH ?
                LIMIT ?
                """, arguments: [match, limit]))
        }
    }

    /// Every group of the given kinds — the empty field's highlights and the
    /// spelling check read these.
    func groups(in categories: [SearchGroupCategory]) async throws -> [SearchGroup] {
        guard !categories.isEmpty else { return [] }
        let marks = Array(repeating: "?", count: categories.count).joined(separator: ", ")
        return try await database.reader.read { db in
            try Self.decode(Row.fetchAll(db, sql: """
                SELECT id, category, name, count, keyAssetId, rule FROM search_group
                WHERE category IN (\(marks))
                """, arguments: StatementArguments(categories.map(\.rawValue))))
        }
    }

    /// Whether the index has been built at all.
    func isEmpty() async throws -> Bool {
        try await database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM search_group") == 0
        }
    }

    /// How many photos of each group are also in `scope` — the counts a
    /// suggestion shows once tokens are chosen (FS-01.03c §3). One scan of
    /// the scoped photos with a SUM per group, not one query each.
    func counts(of groups: [SearchGroup], within scope: SmartAlbumQuery) async throws -> [Int64: Int] {
        var columns: [String] = []
        var values: [DatabaseValueConvertible] = []
        var ids: [Int64] = []
        for group in groups {
            guard let clause = SmartAlbumSQLBuilder.clause(for: group.rule) else { continue }
            columns.append("SUM(CASE WHEN \(clause.sql) THEN 1 ELSE 0 END)")
            values.append(contentsOf: clause.values)
            ids.append(group.id)
        }
        guard !columns.isEmpty else { return [:] }
        let (whereSQL, whereArguments) = SmartAlbumSQLBuilder.whereClause(for: scope)
        let optionalValues: [(any DatabaseValueConvertible)?] = values
        var arguments = StatementArguments(optionalValues)
        arguments += whereArguments
        let finalArguments = arguments
        let groupIds = ids
        let sql = "SELECT \(columns.joined(separator: ", ")) FROM photo_metadata \(whereSQL)"
        return try await database.reader.read { db in
            guard let row = try Row.fetchOne(db, sql: sql, arguments: finalArguments) else { return [:] }
            var result: [Int64: Int] = [:]
            for (index, id) in groupIds.enumerated() {
                result[id] = row[index] ?? 0
            }
            return result
        }
    }

    private static func decode(_ rows: [Row]) throws -> [SearchGroup] {
        let decoder = JSONDecoder()
        return rows.compactMap { row in
            guard let category = SearchGroupCategory(rawValue: row["category"]),
                  let ruleText: String = row["rule"],
                  let rule = try? decoder.decode(SmartAlbumRule.self, from: Data(ruleText.utf8))
            else { return nil }
            return SearchGroup(id: row["id"], category: category, name: row["name"],
                               count: row["count"], keyAssetId: row["keyAssetId"], rule: rule)
        }
    }
}
