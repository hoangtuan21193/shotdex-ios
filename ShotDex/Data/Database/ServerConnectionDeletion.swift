import Foundation
import GRDB

/// Delete Connection (Mac Settings › Servers, FS-18.04 §3 AC-77): what goes
/// with a connection, said before, and the steps in order — its source
/// first (its photos leave ShotDex), then the row, its password, and what
/// hangs off it. Nothing on the server is touched.
struct ServerConnectionDeletion: Sendable {
    let database: AppDatabase
    let servers: FileServerStore

    /// What the dialog names: photos the source holds, backups and shortcuts that go too.
    struct Impact: Equatable, Sendable {
        var sourceId: String?
        var photoCount: Int
        var backupJobs: Int
        var shortcuts: Int
    }

    enum Failure: Error, Equatable {
        /// Its source is being read; deleting now would let the read write the photos back.
        case sourceBusy
    }

    func impact(of connectionId: String) throws -> Impact {
        let sourceId = try SourceStore(database: database).serverSourceId(connectionId: connectionId)
        let photos = try sourceId.flatMap { try SourceStore(database: database).photoCounts()[$0] } ?? 0
        let (jobs, shortcuts) = try database.reader.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM backup_jobs WHERE connectionId = ?", arguments: [connectionId]) ?? 0,
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM server_shortcuts WHERE serverId = ?", arguments: [connectionId]) ?? 0)
        }
        return Impact(sourceId: sourceId, photoCount: photos, backupJobs: jobs, shortcuts: shortcuts)
    }

    /// Stops at the first step that fails, before the next one starts.
    func delete(connectionId: String, readingSourceId: String?) throws {
        let impact = try impact(of: connectionId)
        if let sourceId = impact.sourceId {
            guard readingSourceId != sourceId else { throw Failure.sourceBusy }
            try SourceStore(database: database).remove(sourceId: sourceId)
        }
        try servers.delete(id: connectionId)
    }
}
