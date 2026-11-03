import Foundation

/// The server side of the on-server check (FS-19.07 §5), run after the
/// source's listing. First, a file Backup wrote — or found in the
/// destination index — gets the SHA-256 Backup recorded for that path and
/// size, so a photo just backed up is on the server without one byte read
/// back. Then only files the size of an unmatched Photos file are read
/// whole and hashed, one at a time; each result is written as it comes.
struct ServerFileHashPass: Sendable {
    let store: CopyFileStore
    /// Locked per call (`LockedRemoteFileClient`), so Backup goes between files.
    let client: any RemoteFileClient
    /// The Mac hashing for every device (FS-19.07 §12.1): every file of the
    /// source, not only those the size of a Photos file.
    var hashesEverything = false

    struct Summary: Equatable, Sendable {
        var seeded = 0
        var hashed = 0
        var failed = 0
        /// The server went away, or refused the login: the pass stopped there.
        var stoppedBy: RemoteFileError?
    }

    /// `folder` is the connection's Folder the source was listed from.
    @discardableResult
    func run(sourceId: String, connectionId: String, folder: String, limit: Int = 200, now: Date = Date()) async throws -> Summary {
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

        let candidates = try store.serverCandidates(sourceId: sourceId, triedBefore: now, limit: limit, everything: hashesEverything)
        guard !candidates.isEmpty else { return summary }
        let result: Result<Void, Error>
        do {
            result = .success(try await hash(candidates, folder: folder, into: &summary, now: now))
        } catch {
            result = .failure(error)
        }
        await client.disconnect()
        try result.get()
        return summary
    }

    private func hash(_ candidates: [CopyFileStore.UnhashedServerFile], folder: String, into summary: inout Summary,
                      now: Date) async throws {
        do {
            try await client.connect()
            for file in candidates {
                try Task.checkCancellation()
                do {
                    // Each protocol streams the read through SHA-256, or a
                    // temporary file it deletes — never the file in memory.
                    let sha = try await client.sha256(of: ServerUploadPath.join(folder, file.relativePath), progress: { _ in })
                    try store.saveHash(sha, copyId: file.copyId, fileKey: file.fileKey, origin: .hashed, at: now)
                    summary.hashed += 1
                } catch let error as RemoteFileError where !error.stopsBatch {
                    // Gone since the listing, or unreadable: the next pass tries again.
                    try store.saveFailure(error.localizedDescription, copyId: file.copyId, fileKey: file.fileKey, at: now)
                    summary.failed += 1
                }
            }
        } catch let error as RemoteFileError {
            summary.stoppedBy = error
        }
    }
}
