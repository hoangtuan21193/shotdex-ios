import Foundation
import GRDB

/// A folder, drive or server source of FS-19 as a backup source (FS-22.02
/// §1). Reads the copies the FS-19 scan recorded — the backup never walks the
/// folder itself — so a rescan is what brings new files in.
struct SourceCopyBackupSource: BackupSourceReading {
    let database: AppDatabase
    let roots: FolderSourceRoots

    func items(for job: BackupJob, context: BackupSourceContext) async throws -> [BackupSourceItem] {
        // Values, not `Row`s, leave the read: a GRDB row is not Sendable.
        let kind = try await database.reader.read { db -> String? in
            try String.fetchOne(db, sql: "SELECT kind FROM sources WHERE id = ?", arguments: [job.sourceId])
        }
        guard let kind else { throw BackupSourceError.offline }
        if kind != "server", roots.root(job.sourceId) == nil { throw BackupSourceError.offline }

        let rows = try await database.reader.read { db -> [CopyRow] in
            try Row.fetchAll(db, sql: """
                SELECT c.id, c.relativePath, c.pairedPath, c.size, c.modifiedAt, m.creationDate, m.mediaType
                FROM photo_copies c LEFT JOIN photo_metadata m ON m.assetId = c.photoId
                WHERE c.sourceId = ? AND c.missingSince IS NULL AND c.isCloudPlaceholder = 0
                  AND c.relativePath IS NOT NULL
                ORDER BY m.creationDate, c.relativePath
                """, arguments: [job.sourceId]).map(CopyRow.init)
        }
        return rows.compactMap { row -> BackupSourceItem? in
            let path = row.relativePath
            let isVideo = row.mediaType == 2
            switch job.settings.content {
            case .photosOnly where isVideo, .videosOnly where !isVideo: return nil
            default: break
            }
            let size = row.size ?? 0
            let modified = row.modifiedAt ?? 0
            var files = [Self.file(path: path, size: size, modified: modified)]
            // The JPEG twin of a RAW pair rides with its RAW (FS-19.01 §3).
            if let twin = row.pairedPath {
                files.append(Self.file(path: twin, size: 0, modified: modified))
            }
            let created = row.creationDate
            let date = Date(timeIntervalSince1970: TimeInterval(created ?? modified))
            let folder = (path as NSString).deletingLastPathComponent
            return BackupSourceItem(
                itemKey: row.id, date: date, isVideo: isVideo,
                album: folder.isEmpty ? nil : (folder as NSString).lastPathComponent,
                files: files
            )
        }
    }

    /// One recorded copy, read out of its `Row` inside the database read.
    private struct CopyRow: Sendable {
        let id: String
        let relativePath: String
        let pairedPath: String?
        let size: Int64?
        let modifiedAt: Int?
        let creationDate: Int?
        let mediaType: Int?

        init(_ row: Row) {
            id = row["id"]
            relativePath = row["relativePath"]
            pairedPath = row["pairedPath"]
            size = row["size"]
            modifiedAt = row["modifiedAt"]
            creationDate = row["creationDate"]
            mediaType = row["mediaType"]
        }
    }

    /// The key carries the path so the exporter can find the file again.
    private static func file(path: String, size: Int64, modified: Int) -> BackupSourceFile {
        let name = (path as NSString).lastPathComponent
        let file = AssetUploadFile(
            key: "file:\(path)", filename: name,
            isRAW: PairingRule.isRaw(name), role: .original, estimatedBytes: size
        )
        return BackupSourceFile(file: file, sourceStamp: "\(size):\(modified)")
    }
}

/// Copies an FS-19 file into the backup's work folder: from the folder or
/// drive through its security scope, or down from the source's server.
struct SourceCopyBackupExporter: AssetFileExporting {
    let database: AppDatabase
    let roots: FolderSourceRoots
    let servers: FileServerStore
    let sourceId: String

    func export(assetId: String, file: AssetUploadFile, into directory: URL) async throws -> URL {
        guard file.key.hasPrefix("file:") else { throw RemoteFileError.other("not a source file") }
        let relativePath = String(file.key.dropFirst("file:".count))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let local = directory.appendingPathComponent("\(UUID().uuidString)-\(file.filename)")

        let source = try await database.reader.read { db -> (kind: String, connectionId: String?)? in
            try Row.fetchOne(db, sql: "SELECT kind, connectionId FROM sources WHERE id = ?", arguments: [sourceId])
                .map { (kind: $0["kind"], connectionId: $0["connectionId"]) }
        }
        guard let source else { throw BackupSourceError.offline }
        if source.kind == "server" {
            guard let connectionId = source.connectionId,
                  let server = try servers.fetch(id: connectionId) else { throw BackupSourceError.offline }
            let client = RemoteFileClientFactory.make(for: server, password: servers.password(for: connectionId) ?? "")
            try await client.connect()
            defer { Task.detached { await client.disconnect() } }
            // Paths are relative to the connection's Folder, as the FS-19 scan reads them.
            try await client.download(ServerUploadPath.join(server.folder, relativePath), to: local, progress: { _ in })
            return local
        }
        guard let url = roots.fileURL(sourceId: sourceId, relativePath: relativePath) else { throw BackupSourceError.offline }
        try FileManager.default.copyItem(at: url, to: local)
        return local
    }
}
