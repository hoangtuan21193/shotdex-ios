import Foundation

/// One item of a backup source — a Photos asset or an FS-19 copy — with the
/// files a job may copy from it.
struct BackupSourceItem: Sendable {
    /// Photos asset id, or FS-19 copy id; what the exporter is handed.
    let itemKey: String
    let date: Date
    let isVideo: Bool
    /// Album (Photos) or subfolder (FS-19) for the Album level.
    let album: String?
    let files: [BackupSourceFile]
}

struct BackupSourceFile: Sendable {
    let file: AssetUploadFile
    /// Size and modification time at the source (`"<bytes>:<epoch>"`): a
    /// changed file is a new ledger entry, not a match (FS-22.02 §1).
    let sourceStamp: String
}

/// What the runner already knows, so a source can skip reading files of
/// items that cannot have changed — a PhotoKit resource lookup per asset is
/// the slow part of listing 55k photos.
struct BackupSourceContext: Sendable {
    /// Items with at least one file uploaded or found.
    var handledItemKeys: Set<String> = []
    /// The last time a run listed this source; nil = never.
    var lastCheckedAt: Date?
}

/// Lists what a job's source holds right now (FS-22.02 §1).
protocol BackupSourceReading: Sendable {
    func items(for job: BackupJob, context: BackupSourceContext) async throws -> [BackupSourceItem]
}

/// A run stopped by the device rather than by a file.
enum BackupRunError: Error, Equatable, Sendable {
    /// Downloading the next original would leave less than the minimum free.
    case noRoom
}

/// Why a source could not be listed — each has its own status line.
enum BackupSourceError: Error, Equatable, Sendable {
    case noPhotosAccess
    case offline
}

/// The connection the files go to, as the history row names it.
struct BackupDestination: Sendable {
    let connectionId: String
    let connectionName: String
}

/// What the screens see while a run goes (FS-22.02 §5).
struct BackupProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// Listing the destination tree before copying (FS-22.05 §3).
        case checkingDestination
        case downloading, uploading, verifying
    }

    var done = 0
    var total = 0
    var bytesDone: Int64 = 0
    var bytesTotal: Int64 = 0
    /// True when the ledger was empty as the run began — "Backing Up · 34%"
    /// rather than "3 New · Uploading".
    var isFirstRun = false
    var currentFile: String?
    var phase: Phase?
    var failed = 0
    /// Files found so far while `checkingDestination`.
    var listedCount = 0
}

struct BackupRunResult: Equatable, Sendable {
    enum Stop: Equatable, Sendable {
        /// Every pending file was dealt with.
        case finished
        /// Cancelled — Pause, or iOS ending the background time.
        case cancelled
        /// A condition or a server failure that every later file would hit.
        case blocked(BackupJobState.Status)
        /// The source could not be listed.
        case sourceUnavailable
    }

    var stop: Stop
    var progress: BackupProgress
    /// When the source was listed — the next run's "changed since" mark, so an
    /// edit made during this run is not missed.
    var listedAt = Date()
    /// When this run listed the destination tree; nil = it did not.
    var treeListedAt: Int?
}

/// Runs one pass of one job: lists the source, subtracts the ledger, and
/// copies what is left, one file at a time (FS-22.02 §1–§2).
///
/// Every file goes through `VerifiedRemoteWrite`; the ledger row is written
/// only after the real name is in place, so a run killed at any point resumes
/// by re-copying at most the one file it was on.
actor BackupRunner {
    /// A file that failed this many times waits for Retry (FS-22.02 §2).
    static let maxAttempts = 3

    private let job: BackupJob
    private let destination: BackupDestination
    private let client: any RemoteFileClient
    private let store: BackupStore
    private let source: any BackupSourceReading
    private let exporter: any AssetFileExporting
    private let planner: BackupPathPlanner
    private let workDirectory: URL
    /// This device's name in the shared index (FS-22.05 §2).
    private let deviceId: String
    /// Checked before every file: Wi‑Fi, charging, free space. Non-nil stops
    /// the run with that status (FS-22.02 §4).
    private let gate: @Sendable () async -> BackupJobState.Status?
    private let onProgress: @Sendable (BackupProgress) -> Void
    /// Retry: files past `maxAttempts` are tried once more.
    private let retriesExhausted: Bool
    /// Free bytes on the device; nil = unknown. A file is downloaded only if
    /// `minimumFreeBytes` stay free after it (FS-22.02 §2).
    private let freeBytes: @Sendable () -> Int64?
    /// What stays free while a file sits in the work folder.
    static let minimumFreeBytes: Int64 = 2 * 1024 * 1024 * 1024
    /// How old a listing of the destination tree may get before a run with
    /// something to copy lists it again (FS-22.05 §3).
    static let treeListingLifetime: TimeInterval = 24 * 60 * 60

    private var progress = BackupProgress()
    private var treeListedAt: Int?
    /// Folder → lowercased name → size, listed once per folder per run.
    private var listings: [String: [String: Int64]] = [:]

    init(
        job: BackupJob,
        destination: BackupDestination,
        client: any RemoteFileClient,
        store: BackupStore,
        source: any BackupSourceReading,
        exporter: any AssetFileExporting,
        names: BackupDateName = BackupDateName(),
        workDirectory: URL,
        deviceId: String,
        retriesExhausted: Bool = false,
        freeBytes: @escaping @Sendable () -> Int64? = { nil },
        gate: @escaping @Sendable () async -> BackupJobState.Status? = { nil },
        onProgress: @escaping @Sendable (BackupProgress) -> Void = { _ in }
    ) {
        self.job = job
        self.destination = destination
        self.client = client
        self.store = store
        self.source = source
        self.exporter = exporter
        self.planner = BackupPathPlanner(organize: job.settings.organize, names: names)
        self.workDirectory = workDirectory
        self.deviceId = deviceId
        self.retriesExhausted = retriesExhausted
        self.freeBytes = freeBytes
        self.gate = gate
        self.onProgress = onProgress
    }

    /// One planned file: where it comes from and where it goes.
    private struct Planned: Sendable {
        let item: BackupSourceItem
        let file: BackupSourceFile
        let key: BackupFileKey
        let remotePath: String
    }

    func run() async -> BackupRunResult {
        let listedAt = Date()
        var result = await pass()
        result.listedAt = listedAt
        result.treeListedAt = treeListedAt
        return result
    }

    private func pass() async -> BackupRunResult {
        let items: [BackupSourceItem]
        do {
            let state = try store.state(jobId: job.id)
            let context = BackupSourceContext(
                handledItemKeys: try store.handledItemKeys(jobId: job.id),
                lastCheckedAt: state.lastCheckedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            )
            items = try await source.items(for: job, context: context)
        } catch is CancellationError {
            return BackupRunResult(stop: .cancelled, progress: progress)
        } catch BackupSourceError.noPhotosAccess {
            return BackupRunResult(stop: .blocked(.noPhotosAccess), progress: progress)
        } catch BackupSourceError.offline {
            return BackupRunResult(stop: .blocked(.sourceOffline), progress: progress)
        } catch {
            return BackupRunResult(stop: .sourceUnavailable, progress: progress)
        }

        let pending: [Planned]
        do {
            pending = try plan(items)
            progress.isFirstRun = try store.handledCount(jobId: job.id) == 0
        } catch {
            return BackupRunResult(stop: .sourceUnavailable, progress: progress)
        }
        progress.total = pending.count
        progress.bytesTotal = pending.reduce(0) { $0 + max(0, $1.file.file.estimatedBytes) }
        onProgress(progress)
        guard !pending.isEmpty else {
            await publishLeftovers()
            return BackupRunResult(stop: .finished, progress: progress)
        }

        // Whatever a killed run left in the work folder goes first: only one
        // file is ever on the device at a time.
        try? FileManager.default.removeItem(at: workDirectory)
        do {
            try await client.connect()
        } catch {
            return BackupRunResult(stop: Self.stop(for: error), progress: progress)
        }
        defer { Task.detached { [client] in await client.disconnect() } }

        do {
            try await listDestinationIfDue()
            try await readSharedIndex()
        } catch {
            return BackupRunResult(stop: Self.stop(for: error), progress: progress)
        }

        let stop = await copyAll(pending)
        switch stop {
        case .finished, .blocked(.waitingForWiFi), .blocked(.waitingToCharge), .blocked(.waitingForStorage):
            // Still connected: tell the other devices what this run learned.
            // Otherwise the next run does (the rows wait in the database).
            try? await publishSharedIndex()
        default:
            break
        }
        return BackupRunResult(stop: stop, progress: progress)
    }

    private func copyAll(_ pending: [Planned]) async -> BackupRunResult.Stop {
        for planned in pending {
            if Task.isCancelled { return .cancelled }
            if let blocked = await gate() { return .blocked(blocked) }
            do {
                try await copy(planned)
            } catch is CancellationError {
                return .cancelled
            } catch BackupSourceError.offline {
                // The drive went away mid-run: the file is not the problem.
                return .blocked(.sourceOffline)
            } catch BackupRunError.noRoom {
                return .blocked(.waitingForStorage)
            } catch let error as RemoteFileError where error.stopsBatch {
                return Self.stop(for: error)
            } catch {
                recordFailure(planned, error)
            }
            progress.done += 1
            progress.currentFile = nil
            progress.phase = nil
            onProgress(progress)
        }
        return .finished
    }

    // MARK: - Planning

    /// The files the job copies, minus what the ledger already holds, in
    /// source order. Failed files past the attempt limit wait for Retry.
    private func plan(_ items: [BackupSourceItem]) throws -> [Planned] {
        var planned: [Planned] = []
        for item in items {
            for file in item.files {
                if file.file.role == .edited && !job.settings.includesEditedVersions { continue }
                let key = BackupFileKey(itemKey: item.itemKey, resourceKey: file.file.key, sourceStamp: file.sourceStamp)
                planned.append(Planned(item: item, file: file, key: key, remotePath: remotePath(item, file)))
            }
        }
        let handled = try store.handledKeys(jobId: job.id)
        let exhausted = retriesExhausted ? [] : Set(
            try store.failedEntries(jobId: job.id).filter { $0.attempts >= Self.maxAttempts }.map(\.key)
        )
        return planned.filter { !handled.contains($0.key) && !exhausted.contains($0.key) }
    }

    private func remotePath(_ item: BackupSourceItem, _ file: BackupSourceFile) -> String {
        var name = file.file.filename
        let isEdited = file.file.role == .edited
        if isEdited {
            // The exporter already named it `<original>_edited.<ext>`; the
            // planner adds the suffix itself after the chosen stem.
            let ns = name as NSString
            let stem = ns.deletingPathExtension
            if stem.hasSuffix("_edited") {
                let bare = String(stem.dropLast("_edited".count))
                name = ns.pathExtension.isEmpty ? bare : "\(bare).\(ns.pathExtension)"
            }
        }
        let input = BackupPlacementInput(
            date: item.date, isVideo: item.isVideo, originalFilename: name, isEditedVersion: isEdited,
            isRAW: file.file.isRAW, album: item.album
        )
        return ServerUploadPath.join(job.folder, planner.relativePath(for: input))
    }

    // MARK: - Copying

    private func copy(_ planned: Planned) async throws {
        progress.currentFile = (planned.remotePath as NSString).lastPathComponent
        let folder = ServerUploadPath.parent(of: planned.remotePath)
        let name = ServerUploadPath.lastComponent(of: planned.remotePath)
        let listing = try await listing(of: folder)

        // Same name, same size: already there — no download, no upload (Q3).
        let estimate = planned.file.file.estimatedBytes
        if estimate > 0, listing[name.lowercased()] == estimate {
            try recordFound(planned, remotePath: planned.remotePath, bytes: estimate)
            return
        }

        // The original is downloaded full size, uploaded, checked and deleted
        // before the next one: never fill the device (FS-22.02 §2).
        if let free = freeBytes(), free - max(0, estimate) < Self.minimumFreeBytes { throw BackupRunError.noRoom }
        progress.phase = .downloading
        onProgress(progress)
        let local = try await exporter.export(assetId: planned.item.itemKey, file: planned.file.file, into: workDirectory)
        defer { try? FileManager.default.removeItem(at: local) }
        try Task.checkCancellation()
        let size = (try? FileManager.default.attributesOfItem(atPath: local.path)[.size] as? NSNumber)?.int64Value ?? 0
        progress.bytesTotal += size - max(0, estimate)

        if listing[name.lowercased()] == size {
            try recordFound(planned, remotePath: planned.remotePath, bytes: size)
            progress.bytesDone += size
            return
        }
        // The same bytes anywhere in the destination folder — another
        // phone's copy, a file put there by hand: nothing is sent (FS-22.05 §4).
        let localHash = try FileChecksum.sha256(of: local)
        if let existing = try await destinationFile(matching: localHash, size: size) {
            // The background-upload extension may have sent it anyway — it
            // cannot hash first (FS-22.05 §4). That part is ShotDex's own
            // unfinished write, not the user's photo: it goes.
            if listing[(name + ServerUploadPath.partSuffix).lowercased()] != nil {
                await VerifiedRemoteWrite(client: client).discardPart(for: planned.remotePath)
            }
            try recordDuplicate(planned, of: existing, sha256: localHash, bytes: size)
            progress.bytesDone += size
            return
        }

        // Same name, different file: keep both, never overwrite, never ask.
        let destination = listing[name.lowercased()] == nil
            ? planned.remotePath
            : ServerUploadPath.join(folder, ServerUploadPath.nextFreeName(for: name, existing: Set(listing.keys)))

        let writer = VerifiedRemoteWrite(client: client)
        var matched = false
        // The Photos background-upload extension may already have sent this
        // file under its part name (FS-22.02 §3c): check it instead of
        // sending it again.
        let partName = (ServerUploadPath.lastComponent(of: destination) + ServerUploadPath.partSuffix).lowercased()
        if listing[partName] == size {
            matched = (try? await writer.readBackSHA256(for: destination, progress: { _ in })) == localHash
        }
        do {
            // A mismatch is tried once more before the file counts as failed.
            for _ in 0..<2 where !matched {
                progress.phase = .uploading
                onProgress(progress)
                try await writer.uploadPart(local, for: destination, progress: { _ in })
                progress.phase = .verifying
                onProgress(progress)
                matched = try await writer.readBackSHA256(for: destination, progress: { _ in }) == localHash
                try Task.checkCancellation()
            }
            guard matched else {
                await writer.discardPart(for: destination)
                throw RemoteFileError.other(String(localized: "The copy on the server didn't match the original.", comment: "Backup: checksum read back from the server differs"))
            }
            try await writer.moveIntoPlace(destination, replacing: false)
        } catch {
            await writer.discardPart(for: destination)
            throw error
        }

        listings[folder, default: [:]][ServerUploadPath.lastComponent(of: destination).lowercased()] = size
        progress.bytesDone += size
        // Known at once, so a second copy of these bytes later in this same
        // run is a duplicate too.
        try store.saveDestinationFile(BackupDestinationFile(
            jobId: job.id, path: relativePath(destination), size: size, sha256: localHash, origin: .own, needsPublish: true
        ))
        try store.record(
            BackupLedgerEntry(
                jobId: job.id, itemKey: planned.key.itemKey, resourceKey: planned.key.resourceKey,
                sourceStamp: planned.key.sourceStamp, remotePath: destination, byteCount: size,
                sha256: localHash, outcome: .uploaded, localName: planned.file.file.filename
            ),
            // The FS-15 history is keyed on Photos assets; an FS-19 copy has
            // its own record of where it lives.
            upload: job.sourceId == PhotoLibrarySource.id ? ServerUploadRecord(
                assetId: planned.item.itemKey, fileKey: planned.file.file.key,
                serverId: self.destination.connectionId, serverName: self.destination.connectionName,
                remotePath: destination, byteCount: size, sha256: localHash
            ) : nil
        )
    }

    private func listing(of folder: String) async throws -> [String: Int64] {
        if let cached = listings[folder] { return cached }
        let entries = try await client.entries(in: folder)
        var names: [String: Int64] = [:]
        for entry in entries where !entry.isDirectory { names[entry.name.lowercased()] = entry.size }
        listings[folder] = names
        return names
    }

    private func recordFound(_ planned: Planned, remotePath: String, bytes: Int64) throws {
        try store.record(BackupLedgerEntry(
            jobId: job.id, itemKey: planned.key.itemKey, resourceKey: planned.key.resourceKey,
            sourceStamp: planned.key.sourceStamp, remotePath: remotePath, byteCount: bytes, outcome: .found,
            localName: planned.file.file.filename
        ))
    }

    // MARK: - Duplicates (FS-22.05)

    /// Lists the whole destination tree when it never was, or not in the last
    /// day — only names and sizes; nothing is read (FS-22.05 §3).
    private func listDestinationIfDue() async throws {
        let now = Date()
        if let last = try store.state(jobId: job.id).lastTreeScanAt,
           now.timeIntervalSince1970 - TimeInterval(last) < Self.treeListingLifetime { return }
        progress.phase = .checkingDestination
        progress.listedCount = 0
        onProgress(progress)
        let files = try await BackupDestinationScan.list(client, folder: job.folder) { count in
            progress.listedCount = count
            onProgress(progress)
        }
        let at = Int(now.timeIntervalSince1970)
        try store.applyListing(files, jobId: job.id, at: at)
        treeListedAt = at
        progress.phase = nil
        onProgress(progress)
    }

    private var indexFolder: String { ServerUploadPath.join(job.folder, BackupContentIndex.folder) }

    /// Takes in the segments of the shared index this device has not read
    /// (FS-22.05 §2). A segment that cannot be read is left for the next run;
    /// the job goes on.
    private func readSharedIndex() async throws {
        let entries: [RemoteEntry]
        do {
            entries = try await client.entries(in: indexFolder)
        } catch let error as RemoteFileError where error.stopsBatch {
            throw error
        } catch {
            return
        }
        let read = try store.readSegments(jobId: job.id)
        let unread = entries.filter {
            !$0.isDirectory && BackupContentIndex.parseSegment($0.name) != nil && read[$0.name] != $0.size
        }
        guard !unread.isEmpty else { return }
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        for entry in unread.sorted(by: { $0.name < $1.name }) {
            try Task.checkCancellation()
            let local = workDirectory.appendingPathComponent("index-\(UUID().uuidString).jsonl")
            defer { try? FileManager.default.removeItem(at: local) }
            do {
                try await client.download(ServerUploadPath.join(indexFolder, entry.name), to: local, progress: { _ in })
            } catch let error as RemoteFileError where error.stopsBatch {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
            let lines = BackupContentIndex.decode((try? Data(contentsOf: local)) ?? Data())
            try store.mergeIndex(lines, jobId: job.id, segment: entry.name, size: entry.size)
        }
    }

    /// Writes what this device learned — files it sent, files it hashed — as
    /// a new segment of its own: a part file first, read back, then renamed,
    /// so another device never reads half of it.
    private func publishSharedIndex() async throws {
        let rows = try store.unpublishedDestinationFiles(jobId: job.id)
        guard !rows.isEmpty else { return }
        let existing = (try? await client.entries(in: indexFolder).map(\.name)) ?? []
        let name = BackupContentIndex.segmentName(device: deviceId, number: BackupContentIndex.nextNumber(device: deviceId, existing: existing))
        let now = Int(Date().timeIntervalSince1970)
        let data = BackupContentIndex.encode(rows.compactMap { row in
            row.sha256.map { BackupContentIndex.Line(path: row.path, size: row.size, modified: row.modified, sha256: $0, device: deviceId, recordedAt: now) }
        })
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let local = workDirectory.appendingPathComponent(name)
        try data.write(to: local)
        defer { try? FileManager.default.removeItem(at: local) }
        let target = ServerUploadPath.join(indexFolder, name)
        let writer = VerifiedRemoteWrite(client: client)
        do {
            try await writer.uploadPart(local, for: target, progress: { _ in })
            guard try await writer.readBackSHA256(for: target, progress: { _ in }) == FileChecksum.sha256(of: local) else {
                await writer.discardPart(for: target)
                return
            }
            try await writer.moveIntoPlace(target, replacing: false)
        } catch {
            await writer.discardPart(for: target)
            throw error
        }
        try store.markPublished(rows, jobId: job.id, segment: name, size: Int64(data.count))
    }

    /// A run with nothing to copy still writes what an earlier, interrupted
    /// run learned — once, when there is something.
    private func publishLeftovers() async {
        guard (try? store.hasUnpublishedDestinationFiles(jobId: job.id)) == true else { return }
        do {
            try await client.connect()
        } catch {
            return
        }
        try? await publishSharedIndex()
        await client.disconnect()
    }

    /// The server path of a file in the destination folder holding exactly
    /// these bytes. What this device knows may be old — someone deleted or
    /// replaced the file on the NAS — so each candidate is asked for first,
    /// and one that is gone or has another size is forgotten.
    private func destinationFile(matching sha256: String, size: Int64) async throws -> String? {
        for candidate in try store.destinationFiles(jobId: job.id, sha256: sha256) {
            let path = ServerUploadPath.join(job.folder, candidate.path)
            if candidate.size == size, try await client.fileSize(at: path) == size { return path }
            try store.removeDestinationFile(jobId: job.id, path: candidate.path)
        }
        // Files nobody has hashed are read only when their size is exactly
        // this one's — two different photos rarely agree to the byte — and
        // each is read once: its hash is kept for every later photo and,
        // through the shared index, for the other devices (FS-22.05 §3).
        for candidate in try store.unhashedDestinationFiles(jobId: job.id, size: size) {
            let path = ServerUploadPath.join(job.folder, candidate.path)
            let hash: String
            do {
                progress.phase = .verifying
                onProgress(progress)
                hash = try await client.sha256(of: path, progress: { _ in })
            } catch let error as RemoteFileError where error.stopsBatch {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Gone since the listing, or unreadable: not a match.
                try store.removeDestinationFile(jobId: job.id, path: candidate.path)
                continue
            }
            var hashed = candidate
            hashed.sha256 = hash
            hashed.needsPublish = true
            try store.saveDestinationFile(hashed)
            if hash == sha256 { return path }
        }
        return nil
    }

    private func recordDuplicate(_ planned: Planned, of existing: String, sha256: String, bytes: Int64) throws {
        try store.record(
            BackupLedgerEntry(
                jobId: job.id, itemKey: planned.key.itemKey, resourceKey: planned.key.resourceKey,
                sourceStamp: planned.key.sourceStamp, remotePath: existing, byteCount: bytes,
                sha256: sha256, outcome: .duplicate, localName: planned.file.file.filename
            ),
            // The bytes matched by SHA-256, so the photo is on the server as
            // surely as one this job sent: Free Up Space may count it.
            upload: job.sourceId == PhotoLibrarySource.id ? ServerUploadRecord(
                assetId: planned.item.itemKey, fileKey: planned.file.file.key,
                serverId: destination.connectionId, serverName: destination.connectionName,
                remotePath: existing, byteCount: bytes, sha256: sha256
            ) : nil
        )
    }

    /// A server path as the shared index writes it: relative to the job's folder.
    private func relativePath(_ remotePath: String) -> String {
        let folder = job.folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !folder.isEmpty, remotePath.hasPrefix(folder + "/") else { return remotePath }
        return String(remotePath.dropFirst(folder.count + 1))
    }

    private func recordFailure(_ planned: Planned, _ error: Error) {
        progress.failed += 1
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        try? store.record(BackupLedgerEntry(
            jobId: job.id, itemKey: planned.key.itemKey, resourceKey: planned.key.resourceKey,
            sourceStamp: planned.key.sourceStamp, outcome: .failed, lastError: message
        ))
    }

    private static func stop(for error: Error) -> BackupRunResult.Stop {
        if error is CancellationError { return .cancelled }
        switch error as? RemoteFileError {
        case .authenticationFailed, .hostKeyChanged, .hostKeyUntrusted: return .blocked(.signInFailed)
        case .serverFull: return .blocked(.destinationFull)
        default: return .blocked(.unreachable)
        }
    }
}
