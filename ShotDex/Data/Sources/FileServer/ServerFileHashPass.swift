import Foundation

/// The server side of the on-server check (FS-19.07 §5), run after the
/// source's listing: a file Backup wrote — or found in the destination
/// index — gets the SHA-256 Backup recorded for that path and size, so a
/// photo just backed up is on the server without one byte read back.
struct ServerFileHashPass: Sendable {
    let store: CopyFileStore

    struct Summary: Equatable, Sendable {
        var seeded = 0
    }

    /// `folder` is the connection's Folder the source was listed from.
    @discardableResult
    func run(sourceId: String, connectionId: String, folder: String, now: Date = Date()) async throws -> Summary {
        var summary = Summary()
        let unhashed = try store.unhashedServerFiles(sourceId: sourceId)
        guard !unhashed.isEmpty else { return summary }
        let known = try store.backupRecords(connectionId: connectionId)
        for file in unhashed {
            let key = FolderSourceIndexer.pathKey(ServerUploadPath.join(folder, file.relativePath))
            guard let record = known[key], record.size == file.size else { continue }
            try store.saveHash(record.sha256, copyId: file.copyId, fileKey: file.fileKey, origin: .backup, at: now)
            summary.seeded += 1
        }
        return summary
    }
}
