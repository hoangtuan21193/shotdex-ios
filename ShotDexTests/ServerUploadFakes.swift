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
    private(set) var uploadCount = 0

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

    func connect() async throws {}
    func disconnect() async {}

    func fileSize(at path: String) async throws -> Int64? {
        lock.withLock { storage[path].map { Int64($0.count) } }
    }

    func fileNames(in directory: String) async throws -> Set<String> {
        lock.withLock {
            Set(storage.keys.filter { ServerUploadPath.parent(of: $0) == directory }.map(ServerUploadPath.lastComponent(of:)))
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
        let number = lock.withLock { uploadCount += 1; return uploadCount }
        onUpload?(number)
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
    }

    func sha256(of path: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        guard var data = lock.withLock({ storage[path] }) else { throw RemoteFileError.other("missing \(path)") }
        let original = String(path.dropLast(ServerUploadPath.partSuffix.count))
        if corruptReadBack.contains(path) || corruptReadBack.contains(original), !data.isEmpty {
            data[data.startIndex] ^= 0xFF
        }
        progress(Int64(data.count))
        return FileChecksum.hex(SHA256.hash(data: data))
    }

    func download(_ path: String, to localURL: URL) async throws {
        guard let data = lock.withLock({ storage[path] }) else { throw RemoteFileError.other("missing") }
        try data.write(to: localURL)
    }

    func move(_ source: String, to destination: String) async throws {
        try lock.withLock {
            guard storage[destination] == nil else { throw RemoteFileError.other("exists") }
            storage[destination] = storage.removeValue(forKey: source)
        }
    }

    func remove(_ path: String) async throws {
        _ = lock.withLock { storage.removeValue(forKey: path) }
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
