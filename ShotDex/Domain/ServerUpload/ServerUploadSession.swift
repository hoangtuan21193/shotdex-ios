import Foundation

/// One file of one batch, with the path it is meant to land on.
struct ServerUploadItem: Hashable, Sendable {
    let assetId: String
    let file: AssetUploadFile
    let remotePath: String
}

/// Writes one of an asset's files into a local directory — from Photos, and
/// from iCloud when the device only holds a proxy.
protocol AssetFileExporting: Sendable {
    func export(assetId: String, file: AssetUploadFile, into directory: URL) async throws -> URL
}

/// A file with the same name is already on the server and is not the same
/// file (FS-15.02 §5).
struct ServerUploadConflict: Sendable, Identifiable {
    var id: String { item.remotePath }
    let item: ServerUploadItem
    /// The file about to go up, already on local disk — the "On iPhone" side.
    let localURL: URL
    let localBytes: Int64
    let remoteBytes: Int64
}

struct ServerUploadConflictDecision: Equatable, Sendable {
    enum Choice: Sendable { case replace, keepBoth, skip }
    var choice: Choice
    /// "Apply to remaining conflicts": later conflicts in this batch take the
    /// same choice without asking.
    var appliesToRemaining = false
}

enum ServerUploadPhase: Equatable, Sendable {
    /// Writing the original out of Photos (and from iCloud).
    case preparing
    case uploading
    /// Reading the file back to check its checksum.
    case verifying
}

enum ServerUploadOutcome: Equatable, Sendable {
    case uploaded(remotePath: String)
    /// Same name and same SHA-256 already on the server: counted as up,
    /// nothing written.
    case alreadyThere(remotePath: String)
    case skipped
    case failed(String)
    /// The batch stopped (cancel, lost connection) before reaching it.
    case notAttempted

    /// The file is verified on the server after this batch.
    var isOnServer: Bool {
        switch self {
        case .uploaded, .alreadyThere: true
        case .skipped, .failed, .notAttempted: false
        }
    }
}

enum ServerUploadEvent: Sendable {
    case fileStarted(index: Int, phase: ServerUploadPhase)
    case phase(index: Int, ServerUploadPhase)
    /// Bytes moved so far over the batch. Each file counts twice — once up,
    /// once read back — so the bar does not sit at 100% while verifying.
    case bytes(done: Int64, total: Int64)
    case fileFinished(index: Int, ServerUploadOutcome)
}

struct ServerUploadResult: Equatable, Sendable {
    enum StopReason: Equatable, Sendable {
        case cancelled
        case error(RemoteFileError)
    }

    var outcomes: [ServerUploadOutcome]
    var stopReason: StopReason?
}

/// Runs one batch against one server, one file at a time (FS-15.02 §4):
///
/// 1. write the original to local disk and hash it;
/// 2. a file with the same name on the server → same hash is "already
///    there", otherwise ask (§5) before writing anything;
/// 3. upload to `<name>.shotdex-part`;
/// 4. read it back and hash it;
/// 5. match → rename to the real name and record it; mismatch → delete the
///    part, the file failed.
///
/// So no real name on the server ever points at an unverified file: a cancel
/// or a dropped connection leaves only a part, and the session removes it on
/// the way out when it still can.
actor ServerUploadSession {
    typealias ConflictResolver = @Sendable (ServerUploadConflict) async -> ServerUploadConflictDecision
    typealias EventSink = @Sendable (ServerUploadEvent) -> Void
    typealias Recorder = @Sendable (ServerUploadRecord) throws -> Void

    private let client: any RemoteFileClient
    private let exporter: any AssetFileExporting
    private let serverId: String?
    private let serverName: String
    private let workDirectory: URL
    private let resolveConflict: ConflictResolver
    private let onEvent: EventSink
    private let record: Recorder

    private var stickyDecision: ServerUploadConflictDecision?
    private var bytesDone: Int64 = 0
    private var bytesTotal: Int64 = 0

    init(
        client: any RemoteFileClient,
        exporter: any AssetFileExporting,
        serverId: String?,
        serverName: String,
        workDirectory: URL,
        resolveConflict: @escaping ConflictResolver,
        onEvent: @escaping EventSink = { _ in },
        record: @escaping Recorder
    ) {
        self.client = client
        self.exporter = exporter
        self.serverId = serverId
        self.serverName = serverName
        self.workDirectory = workDirectory
        self.resolveConflict = resolveConflict
        self.onEvent = onEvent
        self.record = record
    }

    /// The conflict preview's "On Server" side: the remote file on local disk.
    func downloadForPreview(_ remotePath: String) async throws -> URL {
        let url = workDirectory.appendingPathComponent("preview-\(UUID().uuidString)-\(ServerUploadPath.lastComponent(of: remotePath))")
        try await client.download(remotePath, to: url)
        return url
    }

    func run(_ items: [ServerUploadItem]) async -> ServerUploadResult {
        var outcomes = Array(repeating: ServerUploadOutcome.notAttempted, count: items.count)
        bytesDone = 0
        bytesTotal = items.reduce(0) { $0 + 2 * max(0, $1.file.estimatedBytes) }
        stickyDecision = nil
        try? FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)

        do {
            try await client.connect()
        } catch {
            return ServerUploadResult(outcomes: outcomes, stopReason: Self.stopReason(for: error))
        }

        var stopReason: ServerUploadResult.StopReason?
        for (index, item) in items.enumerated() {
            if Task.isCancelled {
                stopReason = .cancelled
                break
            }
            onEvent(.fileStarted(index: index, phase: .preparing))
            do {
                let outcome = try await upload(item, index: index)
                outcomes[index] = outcome
                onEvent(.fileFinished(index: index, outcome))
            } catch {
                let reason = Self.stopReason(for: error)
                // Checked first: a library interrupted by the cancel throws
                // its own error, and that is still a cancel, not a failure.
                if Task.isCancelled || reason == .cancelled {
                    stopReason = .cancelled
                    break
                }
                outcomes[index] = .failed(Self.message(for: error))
                onEvent(.fileFinished(index: index, outcomes[index]))
                if case .error(let remote) = reason, remote.stopsBatch {
                    stopReason = reason
                    break
                }
            }
        }

        await Self.detached { await self.client.disconnect() }
        return ServerUploadResult(outcomes: outcomes, stopReason: stopReason)
    }

    // MARK: - One file

    private func upload(_ item: ServerUploadItem, index: Int) async throws -> ServerUploadOutcome {
        let local: URL
        do {
            local = try await exporter.export(assetId: item.assetId, file: item.file, into: workDirectory)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // One unreadable asset (gone, iCloud refused) is that file's
            // problem, not the batch's.
            throw RemoteFileError.other(Self.message(for: error))
        }
        defer { try? FileManager.default.removeItem(at: local) }
        try Task.checkCancellation()

        let size = (try? FileManager.default.attributesOfItem(atPath: local.path)[.size] as? NSNumber)?.int64Value ?? 0
        adjustTotal(estimated: item.file.estimatedBytes, actual: size)
        let localHash = try FileChecksum.sha256(of: local)

        let directory = ServerUploadPath.parent(of: item.remotePath)
        var destination = item.remotePath
        var replacesExisting = false

        if let remoteSize = try await client.fileSize(at: destination) {
            if remoteSize == size,
               try await client.sha256(of: destination, progress: { _ in }) == localHash {
                try writeRecord(item, remotePath: destination, bytes: size, sha256: localHash)
                advance(by: 2 * size)
                return .alreadyThere(remotePath: destination)
            }
            let decision: ServerUploadConflictDecision
            if let sticky = stickyDecision {
                decision = sticky
            } else {
                decision = await resolveConflict(ServerUploadConflict(
                    item: item, localURL: local, localBytes: size, remoteBytes: remoteSize
                ))
                if decision.appliesToRemaining { stickyDecision = decision }
            }
            try Task.checkCancellation()
            switch decision.choice {
            case .skip:
                advance(by: 2 * size)
                return .skipped
            case .keepBoth:
                let names = try await client.fileNames(in: directory)
                destination = ServerUploadPath.join(
                    directory,
                    ServerUploadPath.nextFreeName(for: ServerUploadPath.lastComponent(of: item.remotePath), existing: names)
                )
            case .replace:
                replacesExisting = true
            }
        }

        try await client.createDirectory(directory)
        let part = ServerUploadPath.partPath(for: destination)
        do {
            onEvent(.phase(index: index, .uploading))
            try await client.upload(local, to: part, progress: progressSink(base: bytesDone))
            bytesDone += size
            report()

            onEvent(.phase(index: index, .verifying))
            let remoteHash = try await client.sha256(of: part, progress: progressSink(base: bytesDone))
            bytesDone += size
            report()
            try Task.checkCancellation()

            guard remoteHash == localHash else {
                await removeQuietly(part)
                return .failed(String(localized: "The copy on the server didn't match the original.", comment: "Upload to Server: checksum read back from the server differs"))
            }
            if replacesExisting {
                try await client.remove(destination)
            }
            try await client.move(part, to: destination)
        } catch {
            await removeQuietly(part)
            throw error
        }

        try writeRecord(item, remotePath: destination, bytes: size, sha256: localHash)
        return .uploaded(remotePath: destination)
    }

    // MARK: - Helpers

    private func writeRecord(_ item: ServerUploadItem, remotePath: String, bytes: Int64, sha256: String) throws {
        try record(ServerUploadRecord(
            assetId: item.assetId,
            fileKey: item.file.key,
            serverId: serverId,
            serverName: serverName,
            remotePath: remotePath,
            byteCount: bytes,
            sha256: sha256
        ))
    }

    /// Clean-up runs even when the batch was cancelled: a cancelled task's
    /// own awaits may throw at once, and the part must still go.
    private func removeQuietly(_ path: String) async {
        let client = client
        await Self.detached { try? await client.remove(path) }
    }

    private static func detached(_ work: @escaping @Sendable () async -> Void) async {
        await Task.detached(operation: work).value
    }

    private func adjustTotal(estimated: Int64, actual: Int64) {
        bytesTotal += 2 * (actual - max(0, estimated))
        report()
    }

    private func advance(by bytes: Int64) {
        bytesDone += bytes
        report()
    }

    /// A progress callback the libraries can call from any thread: it
    /// captures the numbers instead of reaching back into the actor.
    private func progressSink(base: Int64) -> @Sendable (Int64) -> Void {
        let onEvent = onEvent
        let total = bytesTotal
        return { sent in onEvent(.bytes(done: min(total, base + sent), total: total)) }
    }

    private func report() {
        onEvent(.bytes(done: min(bytesTotal, bytesDone), total: bytesTotal))
    }

    private static func stopReason(for error: Error) -> ServerUploadResult.StopReason {
        if error is CancellationError { return .cancelled }
        if let remote = error as? RemoteFileError { return .error(remote) }
        return .error(.other(message(for: error)))
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
