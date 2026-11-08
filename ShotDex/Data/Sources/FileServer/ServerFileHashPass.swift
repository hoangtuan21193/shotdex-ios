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
    /// This device in the ledger on the NAS (FS-19.07 §12.2,
    /// `BackupDeviceIdentity`); nil leaves the ledger alone.
    var deviceId: String?
    /// Where a ledger segment sits between the server and this device.
    var workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ShotDexHashIndex", isDirectory: true)

    struct Summary: Equatable, Sendable {
        var seeded = 0
        /// Files given a hash from the ledger on the NAS (§12.2).
        var fromLedger = 0
        var hashed = 0
        var failed = 0
        /// Lines this device added to its own ledger segment.
        var published = 0
        /// The server went away, or refused the login: the pass stopped there.
        var stoppedBy: RemoteFileError?
    }

    /// `folder` is the connection's Folder the source was listed from — the
    /// source's root, where its ledger lives.
    @discardableResult
    func run(sourceId: String, connectionId: String, folder: String, limit: Int = 200, now: Date = Date()) async throws -> Summary {
        var summary = Summary()
        let unhashed = try store.unhashedServerFiles(sourceId: sourceId)
        let known = unhashed.isEmpty ? [:] : try store.backupRecords(connectionId: connectionId)
        // Find Common Photos read these files whole already: their hashes
        // are taken, not read again (user 2026-11-08).
        let common = unhashed.isEmpty ? [:] : try store.commonPhotosRecords(connectionId: connectionId)
        for file in unhashed {
            let key = FolderSourceIndexer.pathKey(ServerUploadPath.join(folder, file.relativePath))
            if let record = known[key], record.size == file.size {
                try store.saveHash(record.sha256, copyId: file.copyId, fileKey: file.fileKey, origin: .backup, at: now)
                summary.seeded += 1
            } else if let record = common[key], record.size == file.size {
                try store.saveHash(record.sha256, copyId: file.copyId, fileKey: file.fileKey, origin: .hashed, at: now)
                summary.seeded += 1
            }
        }
        // The server is woken only for a file worth reading, or for
        // hashes this device owes its ledger once it has nothing left to read.
        var candidates = try store.serverCandidates(sourceId: sourceId, triedBefore: now, limit: limit, everything: hashesEverything)
        let owesLedger = try deviceId.map { try !self.unpublished(sourceId: sourceId, device: $0).isEmpty } ?? false
        guard !candidates.isEmpty || owesLedger else { return summary }

        let result: Result<Void, Error>
        do {
            try await client.connect()
            // The ledger first: a file another device hashed is not read.
            if let deviceId, !candidates.isEmpty {
                try await readLedger(sourceId: sourceId, folder: folder, device: deviceId, into: &summary, now: now)
                candidates = try store.serverCandidates(sourceId: sourceId, triedBefore: now, limit: limit, everything: hashesEverything)
            }
            try await hash(candidates, folder: folder, into: &summary, now: now)
            // One segment when the source's reading is done, not one per
            // batch of `limit` — or once the unwritten pile is large.
            if let deviceId, summary.stoppedBy == nil {
                let pending = try unpublished(sourceId: sourceId, device: deviceId)
                if candidates.count < limit || pending.count >= Self.segmentLines {
                    try await publishLedger(pending, sourceId: sourceId, folder: folder, device: deviceId, into: &summary)
                }
            }
            result = .success(())
        } catch let error as RemoteFileError {
            // As before the ledger: any server error stops this source's pass
            // (a missing share, a refused login), and the check waits on it.
            summary.stoppedBy = error
            result = .success(())
        } catch {
            result = .failure(error)
        }
        await client.disconnect()
        try result.get()
        return summary
    }

    // MARK: Ledger (FS-19.07 §12.2)

    /// Lines past which a segment is written before the reading is done.
    static let segmentLines = 5_000

    /// What this device hashed that its own segments do not carry yet.
    private func unpublished(sourceId: String, device: String) throws -> [CopyFileStore.OwnServerHash] {
        let own = try store.ownServerHashes(sourceId: sourceId)
        guard !own.isEmpty else { return [] }
        let kept = try store.ledgerLines(sourceId: sourceId, pathKeys: own.map { FolderSourceIndexer.pathKey($0.relativePath) }, device: device)
        return own.filter { own in
            !(kept[FolderSourceIndexer.pathKey(own.relativePath)] ?? []).contains {
                $0.device == device && $0.sha256 == own.sha256 && $0.size == own.size && $0.modifiedAt == own.modifiedAt
            }
        }
    }

    private func indexFolder(_ folder: String) -> String { ServerUploadPath.join(folder, ServerHashIndex.folder) }

    /// Takes in the segments not read at their size, then gives each
    /// unhashed file the hash of a line from another device with the same
    /// path, size and write time — both write times known — unless that
    /// device was caught wrong before the line was written.
    private func readLedger(sourceId: String, folder: String, device: String, into summary: inout Summary, now: Date) async throws {
        let entries: [RemoteEntry]
        do {
            entries = try await client.entries(in: indexFolder(folder))
        } catch let error as RemoteFileError where error.stopsBatch {
            throw error
        } catch {
            entries = []
        }
        let read = try store.ledgerSegments(sourceId: sourceId)
        let unread = entries.filter { !$0.isDirectory && BackupContentIndex.parseSegment($0.name) != nil && read[$0.name] != $0.size }
        if !unread.isEmpty { try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true) }
        for entry in unread.sorted(by: { $0.name < $1.name }) {
            try Task.checkCancellation()
            let local = workDirectory.appendingPathComponent("hash-index-\(UUID().uuidString).jsonl")
            defer { try? FileManager.default.removeItem(at: local) }
            do {
                _ = try await client.download(ServerUploadPath.join(indexFolder(folder), entry.name), to: local, progress: { _ in })
            } catch let error as RemoteFileError where error.stopsBatch {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
            // A segment speaks only for the device it is named after.
            let writer = BackupContentIndex.parseSegment(entry.name)?.device
            let lines = BackupContentIndex.decode((try? Data(contentsOf: local)) ?? Data()).filter { $0.device == writer }.map {
                CopyFileStore.LedgerLine(pathKey: FolderSourceIndexer.pathKey($0.path), device: $0.device, size: $0.size,
                                         modifiedAt: $0.modified, sha256: $0.sha256.lowercased(), recordedAt: $0.recordedAt)
            }
            try store.saveLedgerLines(lines, sourceId: sourceId, segment: entry.name, size: entry.size)
        }

        let unhashed = try store.unhashedServerFiles(sourceId: sourceId)
        let lines = try store.ledgerLines(sourceId: sourceId, pathKeys: unhashed.map { FolderSourceIndexer.pathKey($0.relativePath) })
        guard !lines.isEmpty else { return }
        for file in unhashed {
            guard let modified = file.modifiedAt else { continue }
            let candidates = (lines[FolderSourceIndexer.pathKey(file.relativePath)] ?? [])
                .filter { $0.device != device && $0.size == file.size && $0.modifiedAt == modified }
                .sorted { $0.recordedAt > $1.recordedAt }
            for line in candidates {
                let made = Date(timeIntervalSince1970: TimeInterval(line.recordedAt))
                guard try store.accepts(device: line.device, hashedAt: made, now: now) else { continue }
                try store.saveHash(line.sha256, copyId: file.copyId, fileKey: file.fileKey, origin: .ledger,
                                   sharedFrom: line.device, hashedAt: made, at: now)
                summary.fromLedger += 1
                break
            }
        }
    }

    /// Writes what this device hashed and its ledger does not hold yet as a
    /// new segment of its own: a part file, read back, renamed — so another
    /// device never reads half of it. A write the server refuses is tried
    /// again next pass; the check goes on.
    private func publishLedger(_ fresh: [CopyFileStore.OwnServerHash], sourceId: String, folder: String, device: String,
                               into summary: inout Summary) async throws {
        guard !fresh.isEmpty else { return }
        // The next number needs the folder's names: a listing that fails
        // means try again next pass, never a guess that collides.
        let existing: [String]
        do {
            existing = try await client.entries(in: indexFolder(folder)).map(\.name)
        } catch RemoteFileError.folderMissing {
            existing = []
        } catch let error as RemoteFileError where !error.stopsBatch {
            return
        }
        let name = BackupContentIndex.segmentName(device: device, number: BackupContentIndex.nextNumber(device: device, existing: existing))
        // `recordedAt` is when this device hashed the file, so a later
        // distrust drops exactly what it made before (§12.4).
        let lines = fresh.map {
            BackupContentIndex.Line(path: $0.relativePath, size: $0.size, modified: $0.modifiedAt, sha256: $0.sha256, device: device,
                                    recordedAt: $0.hashedAt)
        }
        let data = BackupContentIndex.encode(lines)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let local = workDirectory.appendingPathComponent(UUID().uuidString + "-" + name)
        try data.write(to: local)
        defer { try? FileManager.default.removeItem(at: local) }
        let target = ServerUploadPath.join(indexFolder(folder), name)
        let writer = VerifiedRemoteWrite(client: client)
        do {
            try await writer.uploadPart(local, for: target, progress: { _ in })
            guard try await writer.readBackSHA256(for: target, progress: { _ in }) == FileChecksum.sha256(of: local) else {
                await writer.discardPart(for: target)
                return
            }
            try await writer.moveIntoPlace(target, replacing: false)
        } catch let error as RemoteFileError where !error.stopsBatch {
            await writer.discardPart(for: target)
            return
        } catch {
            await writer.discardPart(for: target)
            throw error
        }
        try store.saveLedgerLines(lines.map {
            CopyFileStore.LedgerLine(pathKey: FolderSourceIndexer.pathKey($0.path), device: device, size: $0.size,
                                     modifiedAt: $0.modified, sha256: $0.sha256, recordedAt: $0.recordedAt)
        }, sourceId: sourceId, segment: name, size: Int64(data.count))
        summary.published = lines.count
    }

    private func hash(_ candidates: [CopyFileStore.UnhashedServerFile], folder: String, into summary: inout Summary,
                      now: Date) async throws {
        do {
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
