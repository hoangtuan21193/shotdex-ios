import CryptoKit
import Foundation
@testable import ShotDex

/// A backup source held in memory: items can be added between runs, and the
/// listing can be made to fail.
final class FakeBackupSource: BackupSourceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _items: [BackupSourceItem] = []
    var listError: Error?

    init(_ items: [BackupSourceItem] = []) { _items = items }

    var items: [BackupSourceItem] { lock.withLock { _items } }
    func add(_ more: [BackupSourceItem]) { lock.withLock { _items += more } }
    func replace(_ items: [BackupSourceItem]) { lock.withLock { _items = items } }

    func items(for job: BackupJob, context: BackupSourceContext) async throws -> [BackupSourceItem] {
        if let listError { throw listError }
        return items.filter { item in
            switch job.settings.content {
            case .photosAndVideos: true
            case .photosOnly: !item.isVideo
            case .videosOnly: item.isVideo
            }
        }
    }
}

/// An exporter that fails a given file a set number of times, then serves it.
final class FlakyAssetExporter: AssetFileExporting, @unchecked Sendable {
    private let lock = NSLock()
    private let base: FakeAssetExporter
    private var failuresLeft: [String: Int]
    private(set) var exportCount = 0

    init(base: FakeAssetExporter, failing: [String: Int] = [:]) {
        self.base = base
        self.failuresLeft = failing
    }

    func export(assetId: String, file: AssetUploadFile, into directory: URL) async throws -> URL {
        let shouldFail = lock.withLock { () -> Bool in
            exportCount += 1
            guard let left = failuresLeft[assetId], left > 0 else { return false }
            failuresLeft[assetId] = left - 1
            return true
        }
        if shouldFail { throw RemoteFileError.other("iCloud download failed") }
        return try await base.export(assetId: assetId, file: file, into: directory)
    }
}

/// Items, their bytes, and a job pointing at `Backup/iPhone`, with Organize
/// set to No Folders unless the test changes it.
struct BackupFixture {
    let database: AppDatabase
    let store: BackupStore
    let client = InMemoryRemoteFileClient()
    let source: FakeBackupSource
    var contents: [String: Data]
    var job: BackupJob
    let workDirectory: URL

    static let taken = Date(timeIntervalSince1970: 1_760_277_807)

    init(photos: Int, videos: Int = 0, bytes: Int = 4_000, organize: BackupOrganize? = nil) throws {
        database = try AppDatabase.makeEmpty()
        let servers = FileServerStore(database: database, passwords: InMemoryPasswordStore())
        let nas = FileServer(id: "S1", name: "NAS Home", transferProtocol: .webdav, host: "127.0.0.1", username: "me")
        try servers.save(nas, password: "pw")
        store = BackupStore(database: database)
        var settings = BackupSettings()
        settings.organize = organize ?? {
            var o = BackupOrganize()
            o.levels = .noFolders
            o.videoPlacement = .together
            return o
        }()
        job = BackupJob(sourceId: PhotoLibrarySource.id, connectionId: nas.id, folder: "Backup/iPhone", settings: settings)
        try store.add(job)

        var items: [BackupSourceItem] = []
        var contents: [String: Data] = [:]
        for n in 0..<(photos + videos) {
            let isVideo = n >= photos
            let name = isVideo ? "IMG_\(n).MOV" : "IMG_\(n).HEIC"
            let (item, data) = Self.item(n, name: name, isVideo: isVideo, bytes: bytes)
            items.append(item)
            contents.merge(data) { $1 }
        }
        source = FakeBackupSource(items)
        self.contents = contents
        workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ShotDexBackup-test-\(UUID().uuidString)", isDirectory: true)
    }

    static func item(_ n: Int, name: String, isVideo: Bool = false, bytes: Int = 4_000, seed: Int? = nil, edited: String? = nil, editedBytes: Int? = nil) -> (BackupSourceItem, [String: Data]) {
        var files: [BackupSourceFile] = []
        var contents: [String: Data] = [:]
        let original = AssetUploadFile(key: "1:\(name)", filename: name, isRAW: false, role: .original, estimatedBytes: Int64(bytes))
        files.append(BackupSourceFile(file: original, sourceStamp: "\(bytes):1"))
        contents[FakeAssetExporter.key("A\(n)", original.key)] = payload(seed ?? n, bytes: bytes)
        if let edited {
            let size = editedBytes ?? bytes
            let file = AssetUploadFile(key: "7:FullSizeRender.JPG", filename: edited, isRAW: false, role: .edited, estimatedBytes: Int64(size))
            files.append(BackupSourceFile(file: file, sourceStamp: "\(size):\(seed ?? 2)"))
            contents[FakeAssetExporter.key("A\(n)", file.key)] = payload((seed ?? n) + 10_000, bytes: size)
        }
        return (BackupSourceItem(itemKey: "A\(n)", date: taken, isVideo: isVideo, album: nil, files: files), contents)
    }

    static func payload(_ n: Int, bytes: Int) -> Data {
        var data = Data(repeating: UInt8(truncatingIfNeeded: n &* 37 &+ 11), count: bytes)
        data.replaceSubrange(0..<4, with: withUnsafeBytes(of: UInt32(n).bigEndian) { Data($0) })
        return data
    }

    func runner(
        exporter: (any AssetFileExporting)? = nil,
        retriesExhausted: Bool = false,
        gate: @escaping @Sendable () async -> BackupJobState.Status? = { nil },
        onProgress: @escaping @Sendable (BackupProgress) -> Void = { _ in }
    ) -> BackupRunner {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return BackupRunner(
            job: job,
            destination: BackupDestination(connectionId: "S1", connectionName: "NAS Home"),
            client: client,
            store: store,
            source: source,
            exporter: exporter ?? FakeAssetExporter(contents: contents),
            names: BackupDateName(calendar: calendar, locale: Locale(identifier: "en_US")),
            workDirectory: workDirectory,
            retriesExhausted: retriesExhausted,
            gate: gate,
            onProgress: onProgress
        )
    }

    /// Files at the destination that are not part files.
    var remoteFiles: [String: Data] { client.files.filter { !$0.key.hasSuffix(ServerUploadPath.partSuffix) } }
    var partFiles: [String] { client.files.keys.filter { $0.hasSuffix(ServerUploadPath.partSuffix) } }

    static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
