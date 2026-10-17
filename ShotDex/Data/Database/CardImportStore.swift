import Foundation
import GRDB

/// The history of card imports (FS-20 §5, §9): written one row per file as
/// soon as it is verified (AC-15), read when a card's screen opens to say
/// which of its photos are already imported.
struct CardImportStore: Sendable {
    let database: AppDatabase

    struct Row: Sendable, Equatable, Codable, FetchableRecord, PersistableRecord {
        static let databaseTableName = "card_imports"
        var id: Int64?
        var cardId: String
        var cardName: String
        var originalPath: String
        var originalName: String
        var byteCount: Int64
        var capturedAt: Int64
        var sha256: String
        var sourceId: String
        var destinationPath: String
        var photoId: String?
        var backupPath: String?
        var importedAt: Int64
    }

    func record(_ row: Row) throws {
        try database.writer.write { db in try row.insert(db) }
    }

    /// The backup copy of a file is verified too (plan K7).
    func recordBackup(originalPath: String, cardId: String, backupPath: String) throws {
        try database.writer.write { db in
            try db.execute(sql: """
                UPDATE card_imports SET backupPath = ?
                WHERE id = (SELECT MAX(id) FROM card_imports WHERE cardId = ? AND originalPath = ?)
                """, arguments: [backupPath, cardId, originalPath])
        }
    }

    /// What the history knows about these card files, by name + bytes +
    /// date (FS-20 §5): the latest import of each, with whether its copy in
    /// the destination is still there.
    /// - Parameter fileExists: whether a file is at a path in a source,
    ///   asked only when the index has no copy there (yet); nil when the
    ///   source can't be opened right now.
    func matches(for files: [CardFile],
                 fileExists: (_ sourceId: String, _ path: String) -> Bool? = { _, _ in nil }) throws -> [IngestStatus.Key: IngestStatus.Match] {
        guard !files.isEmpty else { return [:] }
        let keys = files.map(IngestStatus.Key.init)
        let names = Array(Set(keys.map(\.name)))
        return try database.reader.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM card_imports WHERE originalName IN (SELECT value FROM json_each(?)) ORDER BY id
                """, arguments: [String(decoding: try JSONEncoder().encode(names), as: UTF8.self)])
            let wanted = Set(keys)
            var out: [IngestStatus.Key: IngestStatus.Match] = [:]
            for row in rows {
                let key = IngestStatus.Key(name: row.originalName, bytes: row.byteCount, capturedAt: row.capturedAt)
                guard wanted.contains(key) else { continue }
                out[key] = IngestStatus.Match(sha256: row.sha256, isCopyGone: try Self.isCopyGone(db, row, fileExists: fileExists))
            }
            return out
        }
    }

    /// The destination copy was deleted, or its source removed (AC-21). A
    /// source that is only unplugged keeps its photos imported (plan Q2).
    /// No copy in the index: the file decides when the source opens — the
    /// read after an import may not have run yet.
    static func isCopyGone(_ db: Database, _ row: Row, fileExists: (String, String) -> Bool?) throws -> Bool {
        guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM sources WHERE id = ?)", arguments: [row.sourceId]) == true else {
            return true
        }
        let missing = try Bool.fetchOne(db, sql: """
            SELECT missingSince IS NOT NULL FROM photo_copies WHERE sourceId = ? AND relativePathKey = ?
            """, arguments: [row.sourceId, FolderSourceIndexer.pathKey(row.destinationPath)])
        if let missing { return missing }
        return fileExists(row.sourceId, row.destinationPath).map { !$0 } ?? false
    }

    func rows(cardId: String) throws -> [Row] {
        try database.reader.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM card_imports WHERE cardId = ? ORDER BY id", arguments: [cardId])
        }
    }
}
