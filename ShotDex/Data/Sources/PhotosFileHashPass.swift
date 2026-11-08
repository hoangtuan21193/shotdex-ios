import Foundation
import Photos

/// The Photos side of the on-server check (FS-19.07 §4): lists each asset's
/// original files with their sizes — no download — and takes the SHA-256
/// Backup already recorded for every file it copied whose stamp still
/// matches. Then only files with a same-size file on a server are
/// downloaded: one temporary file at a time, hashed in 1 MB reads, deleted
/// at once, never while less than 2 GB would stay free. Every listing and
/// hash is written as it comes, so a pass stopped anywhere goes on from the
/// next file; a file that fails is tried on a later pass, behind the rest.
struct PhotosFileHashPass: Sendable {
    let store: CopyFileStore
    /// An asset's files as PhotoKit lists them; injected so tests need no
    /// library.
    let listFiles: @Sendable (_ assetId: String) async throws -> [PhotosFile]
    /// Writes one file of the asset into the folder and returns it.
    var download: @Sendable (_ assetId: String, _ fileKey: String, _ directory: URL) async throws -> URL = Self.liveDownloader()
    var workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ShotDexOnServer", isDirectory: true)
    var freeBytes: @Sendable () -> Int64? = { DiskSpace.availableBytes() }
    /// Originals hashed at once. One on iPhone and iPad (FS-19.07 §4: one
    /// temporary file at a time on a device short of room); the Mac, whose
    /// library is usually on disk, reads several (user 2026-11-08: "use
    /// more than one thread").
    var concurrentDownloads = 1
    /// The Mac hashing for every device (FS-19.07 §12.1): every file, not
    /// only those with a file of the same size on a server.
    var hashesEverything = false
    /// Fills the just-listed copies' files from other devices' hashes
    /// (`SharedHashExchange`); returns how many. Nil while the index is
    /// not shared.
    var adoptListed: (@Sendable (_ copyIds: [String], _ now: Date) async -> Int)?

    /// Room kept for a file whose size Photos did not report.
    static let unknownSizeAllowance: Int64 = 2 << 30

    struct Summary: Equatable, Sendable {
        var listed = 0
        /// Filled from another device's hash right after listing (§12.3).
        var adopted = 0
        var seeded = 0
        var hashed = 0
        var failed = 0
        /// The next file would leave less than 2 GB free: the pass stopped
        /// before downloading it (`Waiting for space`).
        var waitingForSpace = false
    }

    /// Lists up to `limit` assets that were never listed or changed since,
    /// newest first, fills what Backup's ledger knows, then hashes up to
    /// `limit` candidate files.
    @discardableResult
    func run(limit: Int = 200, now: Date = Date()) async throws -> Summary {
        var summary = Summary()
        var listedIds: [String] = []
        for copy in try store.photosCopiesNeedingListing(limit: limit) {
            try Task.checkCancellation()
            // An asset gone from the library since the index: the indexer
            // removes its copy; nothing to list.
            let files: [PhotosFile]
            do {
                files = try await listFiles(copy.assetId)
            } catch PhotosFileHashPass.ListError.missingAsset {
                // PhotoKit cannot fetch it (hidden, Recently Deleted, another
                // library): listed as having no files until it changes, so
                // it does not sit at the head of the queue every round.
                files = []
            } catch {
                continue
            }
            try store.saveListing(copyId: copy.copyId, stamp: copy.stamp, files: files, at: now)
            listedIds.append(copy.copyId)
            summary.listed += 1
        }
        // What another device already hashed is taken before choosing what
        // to download here (FS-19.07 §12.3).
        if let adoptListed, !listedIds.isEmpty, !Task.isCancelled {
            summary.adopted = await adoptListed(listedIds, now)
        }
        summary.seeded = try store.seedFromBackupLedger(at: now)

        let candidates = try store.photosCandidates(triedBefore: now, limit: limit, everything: hashesEverything)
        guard !candidates.isEmpty else { return summary }
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        // Up to `concurrentDownloads` at once; the space rule counts what
        // the ones in flight will take.
        enum Outcome: Sendable { case hashed(Int64), failed(String, String, String, Int64), cancelled(Int64) }
        var queue = candidates[...]
        try await withThrowingTaskGroup(of: Outcome.self) { group in
            var inFlight = 0
            var reserved: Int64 = 0
            // Asked every 25 files, not before each: on the Mac the answer
            // (purgeable space included) takes a moment (2026-11-08 sample).
            var free: Int64? = nil
            var launched = 0
            func launchNext() -> Bool {
                guard let file = queue.first, !Task.isCancelled else { return false }
                let size = file.size ?? Self.unknownSizeAllowance
                if launched % 25 == 0 { free = freeBytes() }
                launched += 1
                // The same rule as Backup: never fill the device (FS-22.02 §2).
                if let free, free - reserved - size < BackupRunner.minimumFreeBytes {
                    summary.waitingForSpace = true
                    queue = []
                    return false
                }
                queue = queue.dropFirst()
                reserved += size
                inFlight += 1
                let (download, workDirectory, store) = (self.download, self.workDirectory, self.store)
                group.addTask {
                    do {
                        let url = try await download(file.assetId, file.fileKey, workDirectory)
                        defer { try? FileManager.default.removeItem(at: url) }
                        let sha = try FileChecksum.sha256(of: url)
                        try store.saveHash(sha, copyId: file.copyId, fileKey: file.fileKey, origin: .hashed, at: now)
                        return .hashed(size)
                    } catch {
                        if error is CancellationError || Task.isCancelled { return .cancelled(size) }
                        return .failed(error.localizedDescription, file.copyId, file.fileKey, size)
                    }
                }
                return true
            }
            while inFlight < max(1, concurrentDownloads), launchNext() {}
            var wasCancelled = false
            while inFlight > 0, let outcome = try await group.next() {
                inFlight -= 1
                switch outcome {
                case .hashed(let size):
                    reserved -= size
                    summary.hashed += 1
                case .failed(let message, let copyId, let fileKey, let size):
                    reserved -= size
                    try store.saveFailure(message, copyId: copyId, fileKey: fileKey, at: now)
                    summary.failed += 1
                case .cancelled(let size):
                    reserved -= size
                    wasCancelled = true
                }
                if !wasCancelled && !Task.isCancelled { _ = launchNext() }
            }
            if wasCancelled || Task.isCancelled { throw CancellationError() }
        }
        return summary
    }
}

extension PhotosFileHashPass {
    enum ListError: Error { case missingAsset }

    /// One file read here on its own — the random check (FS-19.07 §12.4).
    /// Nil when it would leave the device short of space, as for any
    /// candidate.
    func hashOne(assetId: String, fileKey: String, size: Int64?) async throws -> String? {
        if let free = freeBytes(), free - (size ?? Self.unknownSizeAllowance) < BackupRunner.minimumFreeBytes { return nil }
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let url = try await download(assetId, fileKey, workDirectory)
        defer { try? FileManager.default.removeItem(at: url) }
        return try FileChecksum.sha256(of: url)
    }

    /// One original out of Photos into the folder, streamed — fetched from
    /// iCloud when the device holds only the Optimize Storage proxy.
    static func liveDownloader() -> @Sendable (String, String, URL) async throws -> URL {
        { assetId, fileKey, directory in
            let file = AssetUploadFile(key: fileKey, filename: "original", isRAW: false, role: .original, estimatedBytes: 0)
            return try await PhotoKitOriginalExporter().export(assetId: assetId, file: file, into: directory)
        }
    }

    /// The asset's originals and edit renders through PhotoKit — one round
    /// trip, sizes from the resource, stamped as Backup stamps them.
    static func liveLister() -> @Sendable (String) async throws -> [PhotosFile] {
        { assetId in
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject
            else { throw ListError.missingAsset }
            let created = Int(asset.creationDate?.timeIntervalSince1970 ?? 0)
            let modified = Int(asset.modificationDate?.timeIntervalSince1970 ?? 0)
            return PhotoKitOriginalExporter.uploadFiles(for: asset).compactMap { file in
                guard let type = Int(file.key.prefix { $0 != ":" }),
                      let role = CopyFile.Role(resourceType: type, isRAW: file.isRAW) else { return nil }
                return PhotosFile(fileKey: file.key, role: role, size: file.estimatedBytes > 0 ? file.estimatedBytes : nil,
                                  stamp: PhotoKitBackupSource.stamp(for: file, created: created, modified: modified))
            }
        }
    }
}
