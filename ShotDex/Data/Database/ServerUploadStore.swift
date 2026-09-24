import Foundation
import GRDB

/// The upload history: which files of which photos are verified on a server
/// (FS-15.02 §8). Written only after the checksum read back from the server
/// matched.
struct ServerUploadStore: Sendable {
    let database: AppDatabase

    func record(_ upload: ServerUploadRecord) throws {
        try database.writer.write { db in
            var row = upload
            try row.insert(db)
        }
    }

    /// Every asset with at least one verified file on any server — the grid
    /// badge reads this once and keeps it as a set.
    func uploadedAssetIds() throws -> Set<String> {
        try database.reader.read { db in
            Set(try String.fetchAll(db, sql: "SELECT DISTINCT assetId FROM server_uploads"))
        }
    }

    /// The same assets, most recently uploaded first — the order of the
    /// Uploaded to Server list.
    func uploadedAssetIdsNewestFirst() throws -> [String] {
        try database.reader.read { db in
            try String.fetchAll(db, sql: """
                SELECT assetId FROM server_uploads
                GROUP BY assetId
                ORDER BY MAX(uploadedAt) DESC, MAX(id) DESC
                """)
        }
    }

    /// For each asset asked about, the file keys that are on some server.
    func uploadedFileKeys(assetIds: [String]) throws -> [String: Set<String>] {
        guard !assetIds.isEmpty else { return [:] }
        return try database.reader.read { db in
            var result: [String: Set<String>] = [:]
            // SQLite's default variable limit is far above a selection, but
            // chunk anyway: a 55k Select All is a real selection.
            for chunk in stride(from: 0, to: assetIds.count, by: 500) {
                let ids = Array(assetIds[chunk..<min(chunk + 500, assetIds.count)])
                let rows = try Row.fetchAll(
                    db,
                    sql: "SELECT assetId, fileKey FROM server_uploads WHERE assetId IN (\(databaseQuestionMarks(count: ids.count)))",
                    arguments: StatementArguments(ids)
                )
                for row in rows {
                    result[row["assetId"], default: []].insert(row["fileKey"])
                }
            }
            return result
        }
    }

    /// One asset's history, newest first — the Photo Info line.
    func uploads(assetId: String) throws -> [ServerUploadRecord] {
        try database.reader.read { db in
            try ServerUploadRecord
                .filter(Column("assetId") == assetId)
                .order(Column("uploadedAt").desc, Column("id").desc)
                .fetchAll(db)
        }
    }

    func count() throws -> Int {
        try database.reader.read { db in try ServerUploadRecord.fetchCount(db) }
    }
}
