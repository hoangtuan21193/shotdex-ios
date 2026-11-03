import CryptoKit
import Foundation
@testable import ShotDex

/// An SMB/SFTP server in memory, with the failures a real one has on demand.
final class InMemoryRemoteFileClient: RemoteFileClient, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]
    private var directories: Set<String> = [""]

    /// Paths whose read-back returns one byte flipped — a write that went bad
    /// on the way.
    var corruptReadBack: Set<String> = []
    /// Upload number (1-based) that loses the connection halfway.
    var dropConnectionOnUpload: Int?
    /// Called at the start of every upload with its 1-based number — where a
    /// test cancels the batch.
    var onUpload: (@Sendable (Int) -> Void)?
    /// Awaited at the start of every upload — where a test does async work
    /// while a run is held mid-photo.
    var whileUploading: (@Sendable (Int) async -> Void)?
    /// Runs inside each `sha256(of:)`, with how many it has been asked for.
    var whileHashing: (@Sendable (Int) async -> Void)?
    private(set) var uploadCount = 0
    /// Segments of the Backup shared index (`.shotdex/`) written — kept out
    /// of `uploadCount`, which counts the user's files.
    private(set) var indexUploadCount = 0

    var files: [String: Data] { lock.withLock { storage } }

    func put(_ path: String, _ data: Data) {
        lock.withLock {
            storage[path] = data
            var dir = ServerUploadPath.parent(of: path)
            while !dir.isEmpty {
                directories.insert(dir)
                dir = ServerUploadPath.parent(of: dir)
            }
        }
    }

    /// A folder and everything in it gone, as if removed on the server.
    func removeDirectory(_ path: String) {
        lock.withLock {
            directories = directories.filter { $0 != path && !$0.hasPrefix(path + "/") }
            storage = storage.filter { !$0.key.hasPrefix(path + "/") }
        }
    }

    /// A folder and its parents, set up before a test.
    func addDirectory(_ path: String) {
        lock.withLock {
            var dir = path
            while !dir.isEmpty {
                directories.insert(dir)
                dir = ServerUploadPath.parent(of: dir)
            }
        }
    }

    /// What `connect()` throws — a server that turns the login away.
    var connectError: RemoteFileError?
    private(set) var connectCount = 0

    func connect() async throws {
        lock.withLock { connectCount += 1 }
        if let connectError { throw connectError }
    }
    func disconnect() async {}

    func fileSize(at path: String) async throws -> Int64? {
        try countRead()
        return lock.withLock { storage[path].map { Int64($0.count) } }
    }

    func directoryExists(_ path: String) async throws -> Bool {
        lock.withLock { directories.contains(path) }
    }

    func fileNames(in directory: String) async throws -> Set<String> {
        lock.withLock {
            Set(storage.keys.filter { ServerUploadPath.parent(of: $0) == directory }.map(ServerUploadPath.lastComponent(of:)))
        }
    }

    /// Thrown by every `folderNames(in:)` while set.
    var folderNamesError: RemoteFileError?

    func folderNames(in directory: String) async throws -> Set<String> {
        if let folderNamesError { throw folderNamesError }
        return lock.withLock {
            Set(directories.filter { !$0.isEmpty && ServerUploadPath.parent(of: $0) == directory }.map(ServerUploadPath.lastComponent(of:)))
        }
    }

    func createDirectory(_ path: String) async throws {
        lock.withLock {
            var dir = path
            while !dir.isEmpty {
                directories.insert(dir)
                dir = ServerUploadPath.parent(of: dir)
            }
        }
    }

    func upload(_ localURL: URL, to path: String, progress: @escaping @Sendable (Int64) -> Void) async throws {
        if path.contains("/\(BackupContentIndex.folder)/") {
            lock.withLock { indexUploadCount += 1 }
            try put(path, Data(contentsOf: localURL))
            return
        }
        let number = lock.withLock { uploadCount += 1; commands.append("upload \(path)"); return uploadCount }
        let failsAfter = try countWrite()
        onUpload?(number)
        await whileUploading?(number)
        try Task.checkCancellation()
        let data = try Data(contentsOf: localURL)
        guard lock.withLock({ directories.contains(ServerUploadPath.parent(of: path)) }) else {
            throw RemoteFileError.folderMissing(path)
        }
        if dropConnectionOnUpload == number {
            put(path, data.prefix(data.count / 2))
            throw RemoteFileError.connectionLost
        }
        put(path, data)
        progress(Int64(data.count))
        if failsAfter { throw RemoteFileError.connectionLost }
    }

    /// Every path `sha256(of:)` read, in order — how a test proves a file on
    /// the server was read exactly once.
    private(set) var sha256Paths: [String] = []

    func sha256(of path: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        let count = lock.withLock { sha256Paths.append(path); commands.append("sha256 \(path)"); return sha256Paths.count }
        await whileHashing?(count)
        try countRead()
        guard var data = lock.withLock({ storage[path] }) else { throw RemoteFileError.other("missing \(path)") }
        let original = String(path.dropLast(ServerUploadPath.partSuffix.count))
        if corruptReadBack.contains(path) || corruptReadBack.contains(original), !data.isEmpty {
            data[data.startIndex] ^= 0xFF
        }
        progress(Int64(data.count))
        return FileChecksum.hex(SHA256.hash(data: data))
    }

    /// Write times by path; files without one list a nil date.
    var modified: [String: Date] = [:]
    /// Bytes handed out by `readRange` and `download` — how a test proves a
    /// thumbnail read only the head of a file.
    private(set) var bytesRead = 0
    /// Paths whose download comes back one byte short.
    var truncateDownload: Set<String> = []
    /// Download number (1-based) that loses the connection.
    var dropConnectionOnDownload: Int?
    /// Download number (1-based) that the server refuses, and how — a
    /// password changed on the NAS while a batch runs.
    var refuseDownload: (number: Int, error: RemoteFileError)?
    private(set) var downloadCount = 0

    /// What `storageSpace(at:)` answers, by path; nil — no answer.
    var spaces: [String: StorageSpace] = [:]

    func storageSpace(at path: String) async throws -> StorageSpace? {
        lock.withLock { spaces[path] }
    }

    /// What `entries(in:)` throws — a listing that fails after the login.
    var entriesError: RemoteFileError?

    func entries(in directory: String) async throws -> [RemoteEntry] {
        lock.withLock { listingCount += 1 }
        if let entriesError { throw entriesError }
        if let error = lock.withLock({ entriesErrorPaths[directory] }) { throw error }
        return lock.withLock {
            let files = storage.filter { ServerUploadPath.parent(of: $0.key) == directory }.map { path, data in
                RemoteEntry(name: ServerUploadPath.lastComponent(of: path), isDirectory: false, size: Int64(data.count), modified: modified[path])
            }
            let folders = directories.filter { !$0.isEmpty && ServerUploadPath.parent(of: $0) == directory }.map {
                RemoteEntry(name: ServerUploadPath.lastComponent(of: $0), isDirectory: true, size: 0, modified: nil)
            }
            return files + folders
        }
    }

    /// Listings that fail, by folder — a NAS subfolder that times out.
    var entriesErrorPaths: [String: RemoteFileError] = [:]

    /// Every path `readRange` was asked for, in order.
    private(set) var rangeReadPaths: [String] = []
    /// How many directory listings were asked for.
    private(set) var listingCount = 0

    /// After this many range reads, every read fails as if the server went
    /// away (nil = never) — a NAS switched off mid-download.
    var failRangeReadsAfter: Int?
    /// Paths whose range reads come back half as long as asked — a read the
    /// server cut short without an error.
    var shortRangeReads: Set<String> = []

    func readRange(_ path: String, offset: Int64, length: Int) async throws -> Data {
        try lock.withLock {
            if let limit = failRangeReadsAfter, rangeReadPaths.count >= limit { throw RemoteFileError.unreachable(host: "nas.local") }
            rangeReadPaths.append(path)
            guard let data = storage[path] else { throw RemoteFileError.other("missing \(path)") }
            let start = min(Int(offset), data.count)
            var slice = data.subdata(in: start..<min(data.count, start + length))
            if shortRangeReads.contains(path) { slice = slice.prefix(slice.count / 2) }
            bytesRead += slice.count
            return slice
        }
    }

    func download(_ path: String, to localURL: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        let number = lock.withLock { downloadCount += 1; commands.append("download \(path)"); return downloadCount }
        try countRead()
        try Task.checkCancellation()
        if dropConnectionOnDownload == number { throw RemoteFileError.connectionLost }
        if let refuseDownload, refuseDownload.number == number { throw refuseDownload.error }
        guard var data = lock.withLock({ storage[path] }) else { throw RemoteFileError.other("missing") }
        if truncateDownload.contains(path) { data = data.dropLast() }
        lock.withLock { bytesRead += data.count }
        try data.write(to: localURL)
        progress(Int64(data.count))
        return FileChecksum.hex(SHA256.hash(data: data))
    }

    /// Paths `remove` / `removeEmptyDirectory` refuse, as a server without
    /// delete permission does.
    var refuseRemoving: Set<String> = []
    /// Every path removed, in order.
    private(set) var removed: [String] = []

    /// Refuses a rename whose two paths start in different top folders — the
    /// way SMB refuses one across shares.
    var refusesMovesAcrossTopFolders = false
    /// Every server command that reads, writes or removes a file, in order —
    /// `download A/x`, `upload C/x.shotdex-part`, `sha256 …`, `move a → b`,
    /// `remove …` — how a test proves the order of a Move.
    private(set) var commands: [String] = []

    func log(_ command: String) {
        lock.withLock { commands.append(command) }
    }

    /// The write (upload, move or remove, counted from 1 since it was set)
    /// that loses the connection — before the server does it, or after.
    /// How a test stops an operation at every step in turn.
    var failOnWrite: (number: Int, afterDoing: Bool)? {
        get { lock.withLock { failingWrite } }
        set { lock.withLock { failingWrite = newValue; writeCount = 0 } }
    }
    private var failingWrite: (number: Int, afterDoing: Bool)?
    private(set) var writeCount = 0

    /// The read (size, SHA-256 or download, counted from 1 since it was
    /// set) that loses the connection.
    var failOnRead: Int? {
        get { lock.withLock { failingRead } }
        set { lock.withLock { failingRead = newValue; readCount = 0 } }
    }
    private var failingRead: Int?
    private(set) var readCount = 0

    private func countRead() throws {
        try lock.withLock {
            readCount += 1
            if failingRead == readCount { throw RemoteFileError.connectionLost }
        }
    }

    /// Counts a write; throws before it when it is the one to fail first.
    /// Returns whether to throw after doing it.
    private func countWrite() throws -> Bool {
        try lock.withLock {
            writeCount += 1
            guard let failing = failingWrite, failing.number == writeCount else { return false }
            if !failing.afterDoing { throw RemoteFileError.connectionLost }
            return true
        }
    }

    /// Called after a rename lands — where a test makes two paths one file
    /// (the destination vanishing when a source is set aside).
    var onMove: (@Sendable (String, String) -> Void)?
    /// The next rename is done on the server and then reported as failed —
    /// a reply lost on the way.
    var failMoveAfterDoing = false

    func move(_ source: String, to destination: String) async throws {
        log("move \(source) → \(destination)")
        let failsAfter = try countWrite()
        defer { onMove?(source, destination) }
        if refusesMovesAcrossTopFolders, source.split(separator: "/").first != destination.split(separator: "/").first {
            throw RemoteFileError.other("cross-share rename refused")
        }
        try lock.withLock {
            guard storage[source] != nil || directories.contains(source) else { throw RemoteFileError.other("missing \(source)") }
            guard storage[destination] == nil, !directories.contains(destination) else { throw RemoteFileError.other("exists") }
            if directories.contains(source) {
                let prefix = source + "/"
                for key in storage.keys where key.hasPrefix(prefix) {
                    storage[destination + "/" + key.dropFirst(prefix.count)] = storage.removeValue(forKey: key)
                }
                for dir in directories where dir == source || dir.hasPrefix(prefix) {
                    directories.remove(dir)
                    directories.insert(destination + dir.dropFirst(source.count))
                }
            } else {
                storage[destination] = storage.removeValue(forKey: source)
            }
        }
        if failMoveAfterDoing {
            failMoveAfterDoing = false
            throw RemoteFileError.other("gateway timeout")
        }
        if failsAfter { throw RemoteFileError.connectionLost }
    }

    /// Deletes a file behind the client's back, without logging it.
    func drop(_ path: String) {
        lock.withLock { _ = storage.removeValue(forKey: path) }
    }

    func remove(_ path: String) async throws {
        log("remove \(path)")
        let failsAfter = try countWrite()
        try lock.withLock {
            if refuseRemoving.contains(path) { throw RemoteFileError.permissionDenied(path) }
            if storage.removeValue(forKey: path) != nil { removed.append(path) }
        }
        if failsAfter { throw RemoteFileError.connectionLost }
    }

    func removeEmptyDirectory(_ path: String) async throws {
        try lock.withLock {
            if refuseRemoving.contains(path) { throw RemoteFileError.permissionDenied(path) }
            let prefix = path + "/"
            guard !storage.keys.contains(where: { $0.hasPrefix(prefix) }),
                  !directories.contains(where: { $0.hasPrefix(prefix) }) else {
                throw RemoteFileError.other("not empty")
            }
            if directories.remove(path) != nil { removed.append(path) }
        }
    }
}

/// Photos, as far as the session can tell: bytes per (asset, file key).
struct FakeAssetExporter: AssetFileExporting {
    let contents: [String: Data]

    static func key(_ assetId: String, _ fileKey: String) -> String { "\(assetId)|\(fileKey)" }

    func export(assetId: String, file: AssetUploadFile, into directory: URL) async throws -> URL {
        guard let data = contents[Self.key(assetId, file.key)] else {
            throw RemoteFileError.other("unreadable")
        }
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(file.filename)
        try data.write(to: url)
        return url
    }
}

/// A batch of `count` files of `bytes` each under `Photos/2026/2026-09-24/`.
struct UploadFixture {
    let items: [ServerUploadItem]
    let exporter: FakeAssetExporter
    let workDirectory: URL

    init(count: Int, bytes: Int = 10_000_000, names: [String]? = nil) {
        var items: [ServerUploadItem] = []
        var contents: [String: Data] = [:]
        for n in 0..<count {
            let name = names?[n] ?? "IMG_\(n).CR3"
            let file = AssetUploadFile(key: "photo:\(name)", filename: name, isRAW: true, role: .original, estimatedBytes: Int64(bytes))
            var data = Data(repeating: UInt8(truncatingIfNeeded: n &* 37 &+ 11), count: bytes)
            data.replaceSubrange(0..<min(bytes, 4), with: withUnsafeBytes(of: UInt32(n).bigEndian) { Data($0) }.prefix(min(bytes, 4)))
            items.append(ServerUploadItem(assetId: "A\(n)", file: file, remotePath: "Photos/2026/2026-09-24/\(name)"))
            contents[FakeAssetExporter.key("A\(n)", file.key)] = data
        }
        self.items = items
        self.exporter = FakeAssetExporter(contents: contents)
        self.workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotDexUpload-test-\(UUID().uuidString)", isDirectory: true)
    }

    func data(_ index: Int) -> Data {
        exporter.contents[FakeAssetExporter.key(items[index].assetId, items[index].file.key)]!
    }

    /// Files left in the work directory, subfolders included.
    var leftoverFiles: [String] {
        let enumerator = FileManager.default.enumerator(at: workDirectory, includingPropertiesForKeys: [.isRegularFileKey])
        return (enumerator?.allObjects as? [URL] ?? []).filter { !$0.hasDirectoryPath }.map(\.lastPathComponent)
    }
}

/// Collects what the session records and asks.
final class UploadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _records: [ServerUploadRecord] = []
    private var _conflicts: [ServerUploadConflict] = []

    var records: [ServerUploadRecord] { lock.withLock { _records } }
    var conflicts: [ServerUploadConflict] { lock.withLock { _conflicts } }

    func record(_ row: ServerUploadRecord) { lock.withLock { _records.append(row) } }
    func asked(_ conflict: ServerUploadConflict) { lock.withLock { _conflicts.append(conflict) } }
}

func makeSession(
    _ fixture: UploadFixture,
    client: InMemoryRemoteFileClient,
    recorder: UploadRecorder,
    decide: @escaping @Sendable (ServerUploadConflict) -> ServerUploadConflictDecision = { _ in .init(choice: .skip) }
) -> ServerUploadSession {
    ServerUploadSession(
        client: client,
        exporter: fixture.exporter,
        serverId: "S1",
        serverName: "NAS",
        workDirectory: fixture.workDirectory,
        resolveConflict: { conflict in
            recorder.asked(conflict)
            return decide(conflict)
        },
        record: { recorder.record($0) }
    )
}
