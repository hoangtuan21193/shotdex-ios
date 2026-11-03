import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.08 §6c: a scan remembers what it read, so the same folders scanned
/// again read nothing that did not change.
@MainActor
@Suite struct CommonPhotosIncrementalTests {
    /// Big enough to be hashed whole rather than read in one sample.
    nonisolated private static let size = 250_000

    private static func bytes(_ seed: UInt8, size: Int = size) -> Data {
        Data((0..<size).map { UInt8(truncatingIfNeeded: Int(seed) &* 31 &+ $0 &* 7) })
    }

    /// A and B with 3 photos in common under other names, and 2 of their own
    /// each (other sizes), all with write times.
    private static func nas() -> InMemoryRemoteFileClient {
        let client = InMemoryRemoteFileClient()
        func put(_ path: String, _ data: Data) {
            client.put(path, data)
            client.modified[path] = Date(timeIntervalSince1970: 1_700_000_000)
        }
        for n in 0..<3 {
            put("photos/A/IMG_\(n).HEIC", bytes(UInt8(n)))
            put("photos/B/from-a/copy \(n).HEIC", bytes(UInt8(n)))
        }
        for n in 0..<2 {
            put("photos/A/own\(n).HEIC", bytes(UInt8(10 + n), size: size + 1_000 + n))
            put("photos/B/own\(n).HEIC", bytes(UInt8(20 + n), size: size + 2_000 + n))
        }
        return client
    }

    private static func scan(_ sheet: CommonPhotosScanModel) async throws {
        sheet.scan()
        for _ in 0..<600 where sheet.phase != .done {
            if case .failed(let message) = sheet.phase { Issue.record("scan failed: \(message)"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(sheet.phase == .done)
    }

    /// Records land in the background: wait for them.
    private static func waitForRecords(_ database: AppDatabase, count: Int) async throws {
        for _ in 0..<200 {
            let saved = try await database.reader.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM common_photo_scan_records WHERE sha256 IS NOT NULL") ?? 0
            }
            if saved >= count { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("scan records never reached \(count)")
    }

    /// AC-159: folders that are not sources, scanned once; the same folders
    /// scanned again with nothing changed read no byte, and find the same
    /// photos.
    @Test func rescanReadsNothing() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let sheet = CommonPhotosScanModel(connectionId: "C1", sourceId: "S", folders: ["photos/A", "photos/B"],
                                          client: client, database: database)
        try await Self.scan(sheet)
        #expect(sheet.sameCount == 3)
        try await Self.waitForRecords(database, count: 6)
        let reads = (sha: client.sha256Paths.count, ranges: client.rangeReadPaths.count, downloads: client.downloadCount)
        #expect(reads.sha > 0)

        let again = CommonPhotosScanModel(connectionId: "C1", sourceId: "S", folders: ["photos/A", "photos/B"],
                                          client: client, database: database)
        try await Self.scan(again)

        #expect(again.sameCount == 3)
        #expect(client.sha256Paths.count == reads.sha)
        #expect(client.rangeReadPaths.count == reads.ranges)
        #expect(client.downloadCount == reads.downloads)
        await sheet.close()
        await again.close()
    }

    /// A file rewritten since (another write time) is read again; the rest
    /// still are not.
    @Test func changedFileIsReadAgain() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let first = CommonPhotosScanModel(connectionId: "C1", sourceId: "S", folders: ["photos/A", "photos/B"],
                                          client: client, database: database)
        try await Self.scan(first)
        try await Self.waitForRecords(database, count: 6)
        client.modified["photos/B/from-a/copy 1.HEIC"] = Date(timeIntervalSince1970: 1_800_000_000)
        let before = client.sha256Paths.count

        let again = CommonPhotosScanModel(connectionId: "C1", sourceId: "S", folders: ["photos/A", "photos/B"],
                                          client: client, database: database)
        try await Self.scan(again)

        #expect(again.sameCount == 3)
        #expect(Array(client.sha256Paths.dropFirst(before)) == ["photos/B/from-a/copy 1.HEIC"])
        await first.close()
        await again.close()
    }

    /// A Move deletes the other copies, so a Move scan hashes them now even
    /// when an earlier scan did; switching a Copy scan to Move drops it.
    @Test func moveDoesNotTrustTheCache() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let first = CommonPhotosScanModel(connectionId: "C1", sourceId: "S", folders: ["photos/A", "photos/B"],
                                          client: client, database: database)
        try await Self.scan(first)
        try await Self.waitForRecords(database, count: 6)
        #expect(first.canRun == false)  // no destination yet
        first.action = .move
        #expect(first.phase == .idle)

        let before = client.sha256Paths.count
        try await Self.scan(first)
        #expect(first.sameCount == 3)
        let hashedAgain = client.sha256Paths.dropFirst(before)
        #expect(Set(hashedAgain) == Set((0..<3).map { "photos/B/from-a/copy \($0).HEIC" }))
        await first.close()
    }

    /// A file gone from the folder is forgotten.
    @Test func goneFileIsForgotten() async throws {
        let records = CommonPhotosScanRecords(database: try AppDatabase.makeEmpty())
        try records.save(connectionId: "C1", [
            CommonPhotosScanRecord(path: "photos/A/gone.HEIC", size: 1, modifiedAt: 1, sha256: "a"),
            CommonPhotosScanRecord(path: "photos/AB/other.HEIC", size: 1, modifiedAt: 1, sha256: "b"),
        ])
        #expect(try records.prune(connectionId: "C1", under: "photos/A", keeping: ["photos/A/IMG_0.HEIC"]) == 1)
        // Another case is another folder on WebDAV and SFTP: kept.
        try records.save(connectionId: "C1", [CommonPhotosScanRecord(path: "photos/a/x.HEIC", size: 1, modifiedAt: 1, sha256: "c")])
        #expect(try records.prune(connectionId: "C1", under: "photos/A", keeping: []) == 0)
        #expect(try records.records(connectionId: "C1", paths: ["photos/A/gone.HEIC", "photos/AB/other.HEIC"]).keys.sorted()
            == ["photos/AB/other.HEIC"])
    }

    /// Same size and write time keeps what was known and gains what is new;
    /// another size replaces the record.
    @Test func recordsMergeOrReplace() throws {
        let records = CommonPhotosScanRecords(database: try AppDatabase.makeEmpty())
        try records.save(connectionId: "C1", [CommonPhotosScanRecord(path: "p", size: 1, modifiedAt: 1, sha256: "AA")])
        try records.save(connectionId: "C1", [CommonPhotosScanRecord(path: "p", size: 1, modifiedAt: 1, captureKey: "k")])
        #expect(try records.records(connectionId: "C1", paths: ["p"])["p"]
            == CommonPhotosScanRecord(path: "p", size: 1, modifiedAt: 1, sha256: "aa", captureKey: "k"))
        try records.save(connectionId: "C1", [CommonPhotosScanRecord(path: "p", size: 2, modifiedAt: 1, captureKey: "z")])
        #expect(try records.records(connectionId: "C1", paths: ["p"])["p"]
            == CommonPhotosScanRecord(path: "p", size: 2, modifiedAt: 1, sha256: nil, captureKey: "z"))
    }

    /// Switched to Move while a Copy scan runs: that scan cannot run a Move.
    @Test func moveMidScanCannotRunOnTrust() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let first = CommonPhotosScanModel(connectionId: "C1", sourceId: "S", folders: ["photos/A", "photos/B"],
                                          client: client, database: database)
        try await Self.scan(first)
        try await Self.waitForRecords(database, count: 6)
        let sheet = CommonPhotosScanModel(connectionId: "C1", sourceId: "S", folders: ["photos/A", "photos/B"],
                                          client: client, database: database)
        sheet.destination = "photos/Shared"
        sheet.scan()
        sheet.action = .move
        for _ in 0..<100 where sheet.isScanning { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!sheet.canRun)
        #expect(sheet.makeRun() == nil ? true : false)
        await first.close()
        await sheet.close()
    }

    /// Removing the connection forgets what was read through it.
    @Test func removingTheServerForgetsItsRecords() throws {
        let database = try AppDatabase.makeEmpty()
        let servers = FileServerStore(database: database, passwords: InMemoryPasswordStore())
        try servers.save(FileServer(id: "C1", name: "NAS", transferProtocol: .smb, host: "nas.local", username: "u"), password: "pw")
        let records = CommonPhotosScanRecords(database: database)
        try records.save(connectionId: "C1", [CommonPhotosScanRecord(path: "p", size: 1, modifiedAt: 1, sha256: "a")])
        try records.save(connectionId: "C2", [CommonPhotosScanRecord(path: "p", size: 1, modifiedAt: 1, sha256: "a")])
        try servers.delete(id: "C1")
        #expect(try records.records(connectionId: "C1", paths: ["p"]).isEmpty)
        #expect(try records.records(connectionId: "C2", paths: ["p"]).count == 1)
    }

    /// Records nobody read again in 180 days go.
    @Test func oldRecordsGo() throws {
        let records = CommonPhotosScanRecords(database: try AppDatabase.makeEmpty())
        try records.save(connectionId: "C1", [CommonPhotosScanRecord(path: "old", size: 1, modifiedAt: 1, sha256: "a")],
                         at: Date(timeIntervalSince1970: 1_000_000))
        try records.save(connectionId: "C1", [CommonPhotosScanRecord(path: "new", size: 1, modifiedAt: 1, sha256: "b")],
                         at: Date(timeIntervalSince1970: 1_000_000 + CommonPhotosScanRecords.keptFor + 10))
        #expect(try records.records(connectionId: "C1", paths: ["old", "new"]).keys.sorted() == ["new"])
    }

    /// AC-159 on the local SMB test server (fixture: 8 of Tuấn's 12 photos
    /// in Vợ's `from-tuan`, landscapes): the second scan reads no byte.
    @Test(.enabled(if: LocalSMBTestServer.isListening))
    func rescanOnTheServerReadsNothing() async throws {
        let database = try AppDatabase.makeEmpty()
        let smb = SMBFileClient(server: FileServer(name: "Test SMB", transferProtocol: .smb, host: "127.0.0.1", port: 4450,
                                                   username: "tester", share: "photos"), password: "secret")
        let counting = CountingClient(base: smb)
        let first = CommonPhotosScanModel(connectionId: "smb", sourceId: "S", folders: ["photos/Tuan", "photos/Vo"],
                                          client: counting, database: database)
        try await Self.scan(first)
        #expect(first.sameCount == 8)
        await first.close()
        try await Self.waitForRecords(database, count: 16)
        let readsBefore = counting.reads

        let again = CommonPhotosScanModel(connectionId: "smb", sourceId: "S", folders: ["photos/Tuan", "photos/Vo"],
                                          client: counting, database: database)
        try await Self.scan(again)
        #expect(again.sameCount == 8)
        #expect(counting.reads == readsBefore)
        await again.close()
    }
}

/// Counts every call that reads a file's bytes.
private final class CountingClient: RemoteFileClient, @unchecked Sendable {
    let base: any RemoteFileClient
    private let lock = NSLock()
    private var count = 0
    var reads: Int { lock.withLock { count } }
    init(base: any RemoteFileClient) { self.base = base }
    private func read() { lock.withLock { count += 1 } }

    func connect() async throws { try await base.connect() }
    func disconnect() async { await base.disconnect() }
    func fileSize(at path: String) async throws -> Int64? { try await base.fileSize(at: path) }
    func directoryExists(_ path: String) async throws -> Bool { try await base.directoryExists(path) }
    func fileNames(in directory: String) async throws -> Set<String> { try await base.fileNames(in: directory) }
    func folderNames(in directory: String) async throws -> Set<String> { try await base.folderNames(in: directory) }
    func createDirectory(_ path: String) async throws { try await base.createDirectory(path) }
    func upload(_ localURL: URL, to path: String, progress: @escaping @Sendable (Int64) -> Void) async throws {
        try await base.upload(localURL, to: path, progress: progress)
    }
    func sha256(of path: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        read()
        return try await base.sha256(of: path, progress: progress)
    }
    func entries(in directory: String) async throws -> [RemoteEntry] { try await base.entries(in: directory) }
    func readRange(_ path: String, offset: Int64, length: Int) async throws -> Data {
        read()
        return try await base.readRange(path, offset: offset, length: length)
    }
    func download(_ path: String, to localURL: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        read()
        return try await base.download(path, to: localURL, progress: progress)
    }
    func move(_ source: String, to destination: String) async throws { try await base.move(source, to: destination) }
    func remove(_ path: String) async throws { try await base.remove(path) }
    func removeEmptyDirectory(_ path: String) async throws { try await base.removeEmptyDirectory(path) }
    func storageSpace(at path: String) async throws -> StorageSpace? { try await base.storageSpace(at: path) }
}
