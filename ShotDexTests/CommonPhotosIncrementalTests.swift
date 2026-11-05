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
        // The plan of the destination too: it reads there, and a test counts reads.
        for _ in 0..<600 where sheet.phase != .done || sheet.isCutting || sheet.isPlanning {
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
        client.whileHashing = { _ in try? await Task.sleep(for: .milliseconds(30)) }
        sheet.scan()
        // Switched once the Copy scan has started trusting the cache.
        for _ in 0..<200 where sheet.phase != .checking { try await Task.sleep(for: .milliseconds(2)) }
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

    // MARK: Only new photos (AC-160…162)

    private static func sheet(_ client: InMemoryRemoteFileClient, _ database: AppDatabase, action: CommonPhotosRun.Action = .copy) -> CommonPhotosScanModel {
        let sheet = CommonPhotosScanModel(connectionId: "C1", sourceId: "S", folders: ["photos/A", "photos/B"],
                                          client: client, database: database)
        sheet.destination = "photos/Shared"
        sheet.action = action
        return sheet
    }

    private static func put(_ client: InMemoryRemoteFileClient, _ path: String, _ data: Data, at time: TimeInterval = 1_700_000_500) {
        client.put(path, data)
        client.modified[path] = Date(timeIntervalSince1970: time)
    }

    /// AC-160: after a run gathered 3, three more common photos arrive; the
    /// next scan of the set lists those 3 only and reads nothing of the old.
    @Test func onlyNewPhotos() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let first = Self.sheet(client, database)
        try await Self.scan(first)
        try Self.copyAll(first, database, into: client)
        for n in 3..<6 {
            Self.put(client, "photos/A/IMG_\(n).HEIC", Self.bytes(UInt8(n), size: Self.size + 10 * n))
            Self.put(client, "photos/B/from-a/copy \(n).HEIC", Self.bytes(UInt8(n), size: Self.size + 10 * n))
        }
        let before = (sha: client.sha256Paths.count, ranges: client.rangeReadPaths.count)

        let again = Self.sheet(client, database, action: .move)
        try await Self.scan(again)

        #expect(again.sameCount == 3)
        #expect(again.lastGathered != nil)
        #expect(Set(again.rows.map(\.name)) == ["IMG_3.HEIC", "IMG_4.HEIC", "IMG_5.HEIC"])
        let touched = Set(client.sha256Paths.dropFirst(before.sha) + client.rangeReadPaths.dropFirst(before.ranges))
        #expect(touched.allSatisfy { $0.contains("_3") || $0.contains("_4") || $0.contains("_5") || $0.contains(" 3") || $0.contains(" 4") || $0.contains(" 5") },
                "\(touched.sorted())")
        #expect(again.makeRun()?.items.count == 3)
        await first.close()
        await again.close()
    }

    /// AC-161: a new photo only in A is not common yet; once B has it, it is.
    @Test func newInOneFolderWaits() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let first = Self.sheet(client, database)
        try await Self.scan(first)
        try Self.copyAll(first, database, into: client)
        Self.put(client, "photos/A/X.HEIC", Self.bytes(77, size: 300_123))

        let waiting = Self.sheet(client, database)
        try await Self.scan(waiting)
        #expect(waiting.sameCount == 0)

        Self.put(client, "photos/B/X copy.HEIC", Self.bytes(77, size: 300_123), at: 1_700_000_900)
        let ready = Self.sheet(client, database)
        try await Self.scan(ready)
        #expect(ready.rows.map(\.name) == ["X.HEIC"])
        await first.close()
        await waiting.close()
        await ready.close()
    }

    /// AC-162: a gathered photo rewritten in both folders (other size) is
    /// new again and read again.
    @Test func changedFileIsNew() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let first = Self.sheet(client, database)
        try await Self.scan(first)
        try Self.copyAll(first, database, into: client)
        Self.put(client, "photos/A/IMG_1.HEIC", Self.bytes(91, size: Self.size + 55))
        Self.put(client, "photos/B/from-a/copy 1.HEIC", Self.bytes(91, size: Self.size + 55))
        let before = client.sha256Paths.count

        let again = Self.sheet(client, database)
        try await Self.scan(again)

        #expect(again.rows.map(\.name) == ["IMG_1.HEIC"])
        #expect(Set(client.sha256Paths.dropFirst(before)) == ["photos/A/IMG_1.HEIC", "photos/B/from-a/copy 1.HEIC"])
        await first.close()
        await again.close()
    }

    /// Scan Everything lists every common photo again; another destination
    /// is another set, with no earlier runs.
    @Test func everythingAndOtherDestination() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let first = Self.sheet(client, database)
        try await Self.scan(first)
        try Self.copyAll(first, database, into: client)

        let all = Self.sheet(client, database)
        all.scanEverything()
        for _ in 0..<600 where all.phase != .done { try await Task.sleep(for: .milliseconds(20)) }
        #expect(all.sameCount == 3)
        #expect(all.lastGathered == nil)
        #expect(all.scansEverything)

        let elsewhere = Self.sheet(client, database)
        elsewhere.destination = "photos/Elsewhere"
        try await Self.scan(elsewhere)
        #expect(elsewhere.sameCount == 3)

        // Chosen after the scan: the gathered ones drop out.
        let late = CommonPhotosScanModel(connectionId: "C1", sourceId: "S", folders: ["photos/B", "photos/A"],
                                         client: client, database: database)
        try await Self.scan(late)
        #expect(late.sameCount == 3)
        late.destination = "photos/Shared"
        for _ in 0..<100 where late.sameCount != 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(late.sameCount == 0)
        #expect(late.lastGathered != nil)
        // Another destination: the whole results come back, no rescan.
        late.destination = "photos/Elsewhere"
        for _ in 0..<100 where late.sameCount != 3 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(late.sameCount == 3)
        #expect(late.phase == .done)
        // Scan Everything is never cut.
        all.destination = "photos/Other"
        all.destination = "photos/Shared"
        for _ in 0..<50 where all.isCutting { try await Task.sleep(for: .milliseconds(10)) }
        #expect(all.sameCount == 3)
        for sheet in [first, all, elsewhere, late] { await sheet.close() }
    }

    /// Scan Everything is one scan's choice; the next Scan checks only new
    /// photos again. A photo gathered twice (Copy, then Skipped by a Scan
    /// Everything run) counts once.
    @Test func everythingIsOneScan() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let first = Self.sheet(client, database)
        try await Self.scan(first)
        try Self.copyAll(first, database, into: client)
        let all = Self.sheet(client, database)
        all.scanEverything()
        for _ in 0..<600 where all.phase != .done { try await Task.sleep(for: .milliseconds(20)) }
        #expect(all.sameCount == 3)
        // Recorded again as already there: still 3 photos.
        let made = try #require(all.makeRun())
        let store = CommonPhotosStore(database: database)
        try store.start(made.run, items: made.items.map { item in
            var item = item
            item.status = .skipped
            item.destinationPath = "photos/Shared/" + ServerUploadPath.lastComponent(of: item.sources[0].path)
            return item
        })
        try store.markState(.finished, runId: made.run.id)

        try await Self.scan(all)
        #expect(!all.scansEverything)
        #expect(all.sameCount == 0)
        #expect(all.alreadyGathered == 3)
        await first.close()
        await all.close()
    }

    /// A destination picked while the scan runs: the results are cut to it
    /// when the scan ends.
    @Test func destinationDuringTheScan() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let first = Self.sheet(client, database)
        try await Self.scan(first)
        try Self.copyAll(first, database, into: client)
        client.whileHashing = { _ in try? await Task.sleep(for: .milliseconds(30)) }

        let sheet = CommonPhotosScanModel(connectionId: "C1", sourceId: "S", folders: ["photos/A", "photos/B"],
                                          client: client, database: try AppDatabase.makeEmpty())
        let shared = CommonPhotosScanModel(connectionId: "C1", sourceId: "S", folders: ["photos/A", "photos/B"],
                                           client: client, database: database)
        shared.scan()
        for _ in 0..<200 where shared.phase != .checking { try await Task.sleep(for: .milliseconds(5)) }
        shared.destination = "photos/Shared"
        for _ in 0..<600 where shared.phase != .done || shared.isCutting { try await Task.sleep(for: .milliseconds(10)) }
        #expect(shared.sameCount == 0)
        #expect(!shared.canRun)
        for model in [first, sheet, shared] { await model.close() }
    }

    // MARK: Gone from the destination (AC-163)

    /// The sheet's photos as copied into `photos/Shared`: there for real,
    /// and recorded so.
    private static func copyAll(_ sheet: CommonPhotosScanModel, _ database: AppDatabase, into client: InMemoryRemoteFileClient) throws {
        let made = try #require(sheet.makeRun())
        let store = CommonPhotosStore(database: database)
        let items = try made.items.map { item -> CommonPhotosItem in
            var item = item
            let source = try #require(item.sources.first)
            let name = ServerUploadPath.lastComponent(of: source.path)
            item.destinationPath = "photos/Shared/" + name
            client.put(item.destinationPath!, try #require(client.files[source.path]))
            item.status = .copied
            return item
        }
        try store.start(made.run, items: items)
        try store.markState(.finished, runId: made.run.id)
    }

    /// AC-163: a gathered photo whose copy left the destination comes back
    /// and is copied again; the others, still there, are not read.
    @Test func goneFromSharedComesBack() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let first = Self.sheet(client, database)
        try await Self.scan(first)
        try Self.copyAll(first, database, into: client)

        let unchanged = Self.sheet(client, database)
        try await Self.scan(unchanged)
        #expect(unchanged.sameCount == 0)

        try await client.remove("photos/Shared/IMG_2.HEIC")
        let before = client.sha256Paths.count
        let again = Self.sheet(client, database)
        try await Self.scan(again)

        #expect(again.rows.map(\.name) == ["IMG_2.HEIC"])
        // A Copy scan: its hashes are known, nothing is read again.
        #expect(client.sha256Paths.count == before)
        await first.close()
        await unchanged.close()
        await again.close()
    }

    /// Replaced in the destination by other bytes of another size: gathered
    /// again; the destination missing altogether: everything comes back.
    @Test func replacedOrMissingDestination() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let first = Self.sheet(client, database)
        try await Self.scan(first)
        try Self.copyAll(first, database, into: client)
        client.put("photos/Shared/IMG_0.HEIC", Data(repeating: 1, count: 10))

        let again = Self.sheet(client, database)
        try await Self.scan(again)
        #expect(again.rows.map(\.name) == ["IMG_0.HEIC"])

        // Shared cannot be listed: nothing counts as gathered, every photo
        // is checked (Copy would skip the bytes already there).
        client.entriesErrorPaths["photos/Shared"] = RemoteFileError.permissionDenied("photos/Shared")
        let unlisted = Self.sheet(client, database)
        try await Self.scan(unlisted)
        #expect(unlisted.sameCount == 3)
        #expect(unlisted.lastGathered == nil)
        await unlisted.close()
        client.entriesErrorPaths = [:]

        for n in 0..<3 { try await client.remove("photos/Shared/IMG_\(n).HEIC") }
        let empty = Self.sheet(client, database)
        client.entriesErrorPaths["photos/Shared"] = RemoteFileError.folderMissing("photos/Shared")
        try await Self.scan(empty)
        #expect(empty.sameCount == 3)
        for sheet in [first, again, empty] { await sheet.close() }
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

    /// AC-163 on the local SMB test server: a real Copy into a scratch
    /// folder; the set scanned again has nothing new; one copy removed from
    /// the destination brings that photo back, and only it.
    @Test(.enabled(if: LocalSMBTestServer.isListening))
    func goneFromSharedOnTheServer() async throws {
        let database = try AppDatabase.makeEmpty()
        func smb() -> SMBFileClient {
            SMBFileClient(server: FileServer(name: "Test SMB", transferProtocol: .smb, host: "127.0.0.1", port: 4450,
                                             username: "tester", share: "photos"), password: "secret")
        }
        let destination = "photos/Shared/e2e-g3-\(UUID().uuidString.prefix(8))"
        let runnerClient = smb()
        try await runnerClient.connect()
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("CommonPhotosG3-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        var opened: [CommonPhotosScanModel] = []
        func sheet() -> CommonPhotosScanModel {
            let sheet = CommonPhotosScanModel(connectionId: "smb", sourceId: "S", folders: ["photos/Tuan", "photos/Vo"],
                                              client: smb(), database: database)
            sheet.destination = destination
            opened.append(sheet)
            return sheet
        }
        do {
            let first = sheet()
            try await Self.scan(first)
            #expect(first.sameCount == 8)
            let made = try #require(first.makeRun())
            let store = CommonPhotosStore(database: database)
            try store.start(made.run, items: made.items)
            try await CommonPhotosRunner(client: runnerClient, store: store, workDirectory: work).run(made.run.id)
            await first.close()

            let nothing = sheet()
            try await Self.scan(nothing)
            #expect(nothing.sameCount == 0)
            await nothing.close()

            let placed = try #require(try store.items(runId: made.run.id).first { $0.destinationPath?.hasSuffix("IMG_0003.JPG") == true })
            try await runnerClient.remove(try #require(placed.destinationPath))
            let back = sheet()
            try await Self.scan(back)
            #expect(back.rows.map(\.name) == ["IMG_0003.JPG"])
            await back.close()
        } catch {
            for model in opened { await model.close() }
            try? await runnerClient.removeFolderTree(destination)
            await runnerClient.disconnect()
            throw error
        }
        do { try await runnerClient.removeFolderTree(destination) } catch {
            Issue.record("left \(destination) on the test share: \(error)")
        }
        await runnerClient.disconnect()
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
    func fileInfo(at path: String) async throws -> RemoteFileInfo? { try await base.fileInfo(at: path) }
    func sourceInfo(at path: String) async throws -> RemoteFileInfo? { try await base.sourceInfo(at: path) }
    func setFileInfo(_ info: RemoteFileInfo, at path: String) async throws -> FileInfoSupport {
        try await base.setFileInfo(info, at: path)
    }
}
