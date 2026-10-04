import Foundation

/// One file that arrived: where, and how big.
struct ExportWrittenFile: Sendable, Equatable {
    let path: String
    let bytes: Int64
}

/// Where an export writes (FS-03.07b §4, §6–7): a folder in Files, or a
/// folder on a saved connection. Paths are relative to the export folder.
protocol ExportDestinationWriter: Sendable {
    /// The names already in `folder`, read once before the plan.
    func existingNames(in folder: String) async throws -> Set<String>
    /// Free bytes on the destination; nil when it doesn't say.
    func freeBytes() async -> Int64?
    /// Removes `.shotdex-part` files a run that was cut short left in `folder`
    /// — only those (FS-03.07c §3).
    func sweepLeftoverParts(in folder: String) async
    /// Writes one file: `produce` fills a local URL, the writer puts it under
    /// `<name>.shotdex-part`, checks it, then gives it its real name — over
    /// an older file only when `replacing`. An error `produce` throws is
    /// the photo's and comes back as it is, unless the destination went away
    /// or filled up under it.
    func write(
        name: String,
        in folder: String,
        replacing: Bool,
        produce: @Sendable (URL) async throws -> Void
    ) async throws -> ExportWrittenFile
}

/// A folder in Files — On My iPhone, iCloud Drive, Dropbox, a drive on the
/// cable (FS-03.07b §4, §6). The file is made straight under its part name
/// in the folder, never staged on this device first (§9), and renamed only
/// once it is whole and opens. Every write goes through the system's file
/// coordination, so a provider like Dropbox sees the new file.
struct LocalFolderWriter: ExportDestinationWriter {
    let root: URL
    /// How long a coordinated rename may take before an unreachable folder
    /// is called disconnected (FS-03.07c §3: the batch stops within 2 s,
    /// never hangs on a drive that was pulled out).
    var watchdog: Duration = .seconds(2)
    /// The rename itself; a test hands in one that hangs.
    var rename: (@Sendable (_ part: URL, _ directory: URL, _ name: String, _ replacing: Bool) throws -> String)?

    init(root: URL) {
        self.root = root
    }

    private var fileManager: FileManager { .default }

    func url(of folder: String) -> URL {
        folder.isEmpty ? root : root.appendingPathComponent(folder, isDirectory: true)
    }

    func existingNames(in folder: String) async throws -> Set<String> {
        let directory = url(of: folder)
        guard fileManager.fileExists(atPath: directory.path) else {
            // Date Folders that do not exist yet hold nothing; the root
            // itself missing is the folder gone.
            if folder.isEmpty { throw FileExportFailure.disconnected }
            return []
        }
        do {
            let names = try fileManager.contentsOfDirectory(atPath: directory.path)
            return Set(names.filter { !$0.hasSuffix(ServerUploadPath.partSuffix) })
        } catch {
            throw FileExportFailure.classify(error) ?? FileExportFailure.disconnected
        }
    }

    func freeBytes() async -> Int64? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        guard let values = try? root.resourceValues(forKeys: keys) else { return nil }
        if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        if let plain = values.volumeAvailableCapacity, plain > 0 { return Int64(plain) }
        return nil
    }

    func sweepLeftoverParts(in folder: String) async {
        let directory = url(of: folder)
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasSuffix(ServerUploadPath.partSuffix) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    func write(
        name: String,
        in folder: String,
        replacing: Bool,
        produce: @Sendable (URL) async throws -> Void
    ) async throws -> ExportWrittenFile {
        let directory = url(of: folder)
        let part = directory.appendingPathComponent(name + ServerUploadPath.partSuffix)
        // The destination's own steps: the folder, an empty part file.
        do {
            guard fileManager.fileExists(atPath: root.path) else { throw FileExportFailure.disconnected }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? fileManager.removeItem(at: part)
            guard fileManager.createFile(atPath: part.path, contents: nil) else {
                throw FileExportFailure.permissionDenied
            }
        } catch {
            throw destinationFailure(error)
        }
        do {
            try await produce(part)
            try Task.checkCancellation()
        } catch {
            try? fileManager.removeItem(at: part)
            if error is CancellationError { throw error }
            if !fileManager.fileExists(atPath: root.path) { throw FileExportFailure.disconnected }
            if let failure = FileExportFailure.classify(error), failure == .full || failure == .tooLargeForDrive { throw failure }
            throw error
        }
        do {
            try Self.checkComplete(part)
            let bytes = (try? fileManager.attributesOfItem(atPath: part.path)[.size] as? Int64) ?? 0
            let final = try await guardedRename(part, to: directory, name: name, replacing: replacing)
            return ExportWrittenFile(path: ServerUploadPath.join(folder, final), bytes: bytes)
        } catch {
            try? fileManager.removeItem(at: part)
            throw destinationFailure(error)
        }
    }

    /// The root gone is the drive pulled out, whatever the error says.
    private func destinationFailure(_ error: Error) -> Error {
        if error is CancellationError { return error }
        if let failure = error as? FileExportFailure { return failure }
        if !fileManager.fileExists(atPath: root.path) { return FileExportFailure.disconnected }
        return FileExportFailure.classify(error) ?? error
    }

    /// Whole and readable: there, not empty, and opens.
    static func checkComplete(_ url: URL) throws {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        guard size > 0, let handle = try? FileHandle(forReadingFrom: url) else {
            throw FileExportFailure.unreadable
        }
        try? handle.close()
    }

    /// The rename on a thread of its own, watched: past the watchdog with the
    /// folder unreachable, the drive is gone and the write is abandoned —
    /// the stuck coordination is left to the system. A slow provider with the
    /// folder still there is waited for.
    private func guardedRename(_ part: URL, to directory: URL, name: String, replacing: Bool) async throws -> String {
        let rename = rename ?? { try Self.coordinatedRename($0, to: $1, name: $2, replacing: $3) }
        let result = RenameResult()
        DispatchQueue.global(qos: .userInitiated).async {
            result.finish(Result { try rename(part, directory, name, replacing) })
        }
        let started = ContinuousClock.now
        while true {
            if let done = result.value { return try done.get() }
            if ContinuousClock.now - started >= watchdog, !FileManager.default.fileExists(atPath: root.path) {
                throw FileExportFailure.disconnected
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Part → real name. Replace swaps the older file out only now, after the
    /// new one is whole; Keep Both takes the next free name if someone wrote
    /// the planned one since the folder was read.
    static func coordinatedRename(_ part: URL, to directory: URL, name: String, replacing: Bool) throws -> String {
        let fileManager = FileManager.default
        var finalName = name
        var target = directory.appendingPathComponent(name)
        if !replacing, fileManager.fileExists(atPath: target.path) {
            let names = Set((try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? [])
            finalName = ServerUploadPath.nextFreeName(for: name, existing: names)
            target = directory.appendingPathComponent(finalName)
        }
        var coordinationError: NSError?
        var moveError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: part, options: .forMoving,
            writingItemAt: target, options: replacing ? .forReplacing : [],
            error: &coordinationError
        ) { from, to in
            do {
                if replacing, fileManager.fileExists(atPath: to.path) {
                    _ = try fileManager.replaceItemAt(to, withItemAt: from)
                } else {
                    try fileManager.moveItem(at: from, to: to)
                }
            } catch {
                moveError = error
            }
        }
        if let error = coordinationError ?? moveError { throw error }
        return finalName
    }
}

/// The rename's outcome, handed from its thread to the waiting task.
private final class RenameResult: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<String, Error>?

    func finish(_ result: Result<String, Error>) { lock.withLock { self.result = result } }
    var value: Result<String, Error>? { lock.withLock { result } }
}
