import Foundation
import GRDB

/// A file on a server that the library already has a copy of — from an
/// upload (FS-15) or a download (FS-17).
struct KnownRemoteFile: Hashable, Sendable {
    let remotePath: String
    let byteCount: Int64
    let assetId: String
    let sha256: String
}

/// The download history (FS-17 §4), and the lookup that marks server photos
/// "In Library" from both histories.
struct ServerDownloadStore: Sendable {
    let database: AppDatabase

    func record(_ download: ServerDownloadRecord) throws {
        try database.writer.write { db in
            var row = download
            try row.insert(db)
        }
    }

    /// Every upload or download row for these paths on this server.
    func knownFiles(serverId: String, paths: [String]) throws -> [KnownRemoteFile] {
        guard !paths.isEmpty else { return [] }
        return try database.reader.read { db in
            var result: [KnownRemoteFile] = []
            for chunk in stride(from: 0, to: paths.count, by: 400) {
                let slice = Array(paths[chunk..<min(chunk + 400, paths.count)])
                let marks = databaseQuestionMarks(count: slice.count)
                let rows = try Row.fetchAll(db, sql: """
                    SELECT remotePath, byteCount, assetId, sha256 FROM server_uploads
                    WHERE serverId = ? AND remotePath IN (\(marks))
                    UNION ALL
                    SELECT remotePath, byteCount, assetId, sha256 FROM server_downloads
                    WHERE serverId = ? AND remotePath IN (\(marks))
                    """, arguments: StatementArguments([serverId] + slice + [serverId] + slice))
                result += rows.map {
                    KnownRemoteFile(remotePath: $0["remotePath"], byteCount: $0["byteCount"], assetId: $0["assetId"], sha256: $0["sha256"])
                }
            }
            return result
        }
    }

    func count() throws -> Int {
        try database.reader.read { db in try ServerDownloadRecord.fetchCount(db) }
    }
}
