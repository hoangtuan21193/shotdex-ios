import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.08 §6c, Keep gathering: one pass of the helper for one set.
@MainActor
@Suite struct CommonPhotosGatherTests {
    nonisolated private static let size = 250_000

    private static func bytes(_ seed: UInt8, size: Int = size) -> Data {
        Data((0..<size).map { UInt8(truncatingIfNeeded: Int(seed) &* 31 &+ $0 &* 7) })
    }

    /// A and B sharing 3 photos (other names), 2 of their own each; Shared
    /// exists, empty.
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
        client.addDirectory("photos/Shared")
        return client
    }

    /// The 3 photos as gathered: copied to Shared and recorded so.
    private static func gather(_ client: InMemoryRemoteFileClient, _ database: AppDatabase) async throws {
        let sheet = CommonPhotosScanModel(connectionId: "C1", sourceId: "S", folders: ["photos/A", "photos/B"],
                                          client: client, database: database)
        sheet.destination = "photos/Shared"
        await sheet.scanToEnd()
        let made = try #require(sheet.makeRun())
        let items = try made.items.map { item -> CommonPhotosItem in
            var item = item
            let source = try #require(item.sources.first)
            item.destinationPath = "photos/Shared/" + ServerUploadPath.lastComponent(of: source.path)
            client.put(item.destinationPath!, try #require(client.files[source.path]))
            item.status = .copied
            return item
        }
        let store = CommonPhotosStore(database: database)
        try store.start(made.run, items: items)
        try store.markState(.finished, runId: made.run.id)
        await sheet.close()
    }

    private static func pass(_ client: any RemoteFileClient, _ database: AppDatabase,
                             charging: Bool = true, metered: Bool = false) -> CommonPhotosGatherPass {
        CommonPhotosGatherPass(database: database, connection: { _ in (client, "NAS Home") },
                               conditions: { (metered, charging) })
    }

    private static func watch(_ database: AppDatabase, action: CommonPhotosRun.Action = .copy) throws -> CommonPhotosWatch {
        try CommonPhotosWatchStore(database: database).keepGathering(connectionId: "C1", folders: ["photos/B", "photos/A"],
                                                                     destination: "photos/Shared", action: action)
    }

    /// AC-166: nothing new — no run, nothing read, the check time moves.
    @Test func nothingNewLeavesNoRun() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        try await Self.gather(client, database)
        let watch = try Self.watch(database)
        let runs = try CommonPhotosStore(database: database).keptRuns().count
        let reads = (sha: client.sha256Paths.count, ranges: client.rangeReadPaths.count, downloads: client.downloadCount)

        var handed = false
        let outcome = await Self.pass(client, database).run(watch, now: Date(timeIntervalSince1970: 1_800_000_000)) { _ in handed = true }

        #expect(outcome == .nothingNew)
        #expect(!handed)
        #expect(try CommonPhotosStore(database: database).keptRuns().count == runs)
        #expect(client.sha256Paths.count == reads.sha && client.rangeReadPaths.count == reads.ranges
                && client.downloadCount == reads.downloads)
        #expect(try CommonPhotosWatchStore(database: database).watch(id: watch.id)?.checkedAt
                == Date(timeIntervalSince1970: 1_800_000_000))
    }

    /// New common photos: found, held by the scan for the caller to run.
    @Test func newPhotosAreFound() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        try await Self.gather(client, database)
        let watch = try Self.watch(database)
        client.put("photos/A/new.HEIC", Self.bytes(99, size: 300_001))
        client.put("photos/B/new copy.HEIC", Self.bytes(99, size: 300_001))

        var items = 0
        let outcome = await Self.pass(client, database).run(watch) { scan in items = scan.makeRun()?.items.count ?? 0 }

        #expect(outcome == .found(1))
        #expect(items == 1)
    }

    /// AC-167: on battery, or on a metered network — nothing is asked of the
    /// server, and the set says what it waits for.
    @Test func waitsForPowerAndNetwork() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let watch = try Self.watch(database)
        let commands = client.commands.count

        #expect(await Self.pass(client, database, charging: false).run(watch) == .waiting(.charging))
        #expect(try CommonPhotosWatchStore(database: database).watch(id: watch.id)?.waiting == .charging)
        #expect(await Self.pass(client, database, metered: true).run(watch) == .waiting(.wifi))
        #expect(try CommonPhotosWatchStore(database: database).watch(id: watch.id)?.waiting == .wifi)
        #expect(client.commands.count == commands)
        #expect(client.connectCount == 0)
    }

    /// AC-168: Backup holds the connection; the pass waits for it.
    @Test func backupGoesFirst() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let watch = try Self.watch(database)
        let lock = ConnectionLock()
        await lock.acquire("C1", priority: .backup)
        let locked = LockedRemoteFileClient(client, lock: lock, connectionId: "C1", priority: .normal)
        let pass = Self.pass(locked, database)
        let running = Task { await pass.run(watch) }
        while await lock.waitingCount("C1") < 1 { await Task.yield() }
        #expect(client.connectCount == 0)
        await lock.release("C1")
        #expect(await running.value == .found(3))
        #expect(client.connectCount > 0)
    }

    /// AC-171: a source folder gone — gathering stops, says which, and the
    /// next pass asks nothing of the server.
    @Test func folderGoneStops() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let watch = try Self.watch(database)
        client.removeDirectory("photos/B")

        #expect(await Self.pass(client, database).run(watch) == .stopped(.folderGone("photos/B")))
        let stopped = try #require(try CommonPhotosWatchStore(database: database).watch(id: watch.id))
        #expect(!stopped.isOn && stopped.stopped == .folderGone("photos/B"))
        let commands = client.commands.count
        let connects = client.connectCount
        #expect(await Self.pass(client, database).run(stopped) == .off)
        #expect(client.commands.count == commands && client.connectCount == connects)
        // Turned on again from the sheet: it gathers again.
        #expect(try Self.watch(database).isOn)
    }

    /// The connection removed from ShotDex: gathering stops.
    @Test func connectionGoneStops() async throws {
        let database = try AppDatabase.makeEmpty()
        let watch = try Self.watch(database)
        let pass = CommonPhotosGatherPass(database: database, connection: { _ in nil }, conditions: { (false, true) })
        #expect(await pass.run(watch) == .stopped(.connectionGone))
    }

    /// AC-172: Stop Gathering — no more passes; the runs stay.
    @Test func stopGatheringKeepsTheRuns() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        try await Self.gather(client, database)
        let watch = try Self.watch(database)
        let runs = try CommonPhotosStore(database: database).keptRuns()

        try CommonPhotosWatchStore(database: database).stopGathering(id: watch.id)
        let off = try #require(try CommonPhotosWatchStore(database: database).watch(id: watch.id))
        #expect(!off.isOn && off.stopped == nil)
        #expect(await Self.pass(client, database).run(off) == .off)
        #expect(try CommonPhotosStore(database: database).keptRuns() == runs)
    }

    /// One row per set, whatever the folders' order; turning it on again
    /// changes the action.
    @Test func oneWatchPerSet() throws {
        let database = try AppDatabase.makeEmpty()
        let store = CommonPhotosWatchStore(database: database)
        let first = try store.keepGathering(connectionId: "C1", folders: ["photos/A", "photos/B"], destination: "photos/Shared", action: .copy)
        let again = try store.keepGathering(connectionId: "C1", folders: ["photos/B", "photos/A"], destination: "photos/Shared/", action: .move)
        #expect(first.id == again.id)
        #expect(again.action == .move)
        #expect(try store.watches().count == 1)
    }

    /// A folder the server cannot confirm gone (its parent does not list)
    /// is the server away, not a stop.
    @Test func unconfirmedGoneIsUnreachable() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let watch = try Self.watch(database)
        client.removeDirectory("photos/B")
        client.entriesErrorPaths["photos"] = RemoteFileError.connectionLost
        client.folderNamesError = RemoteFileError.connectionLost

        #expect(await Self.pass(client, database).run(watch) == .waiting(.unreachable("NAS Home")))
        #expect(try CommonPhotosWatchStore(database: database).watch(id: watch.id)?.isOn == true)
    }

    /// The listing says a folder is missing but the folder above still
    /// lists it: not proof, the server is away. Gone for real: stops.
    @Test func missingWhileListingNeedsProof() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let watch = try Self.watch(database)
        client.entriesErrorPaths["photos/B"] = RemoteFileError.folderMissing("photos/B")

        #expect(await Self.pass(client, database).run(watch) == .waiting(.unreachable("NAS Home")))
        client.removeDirectory("photos/B")
        let still = try #require(try CommonPhotosWatchStore(database: database).watch(id: watch.id))
        #expect(await Self.pass(client, database).run(still) == .stopped(.folderGone("photos/B")))
    }

    /// Stop Gathering pressed while the pass scans: nothing handed on.
    @Test func stopDuringThePass() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let watch = try Self.watch(database)
        client.whileHashing = { _ in try? CommonPhotosWatchStore(database: database).stopGathering(id: watch.id) }
        var handed = false
        #expect(await Self.pass(client, database).run(watch) { _ in handed = true } == .off)
        #expect(!handed)
        #expect(try CommonPhotosWatchStore(database: database).watch(id: watch.id)?.checkedAt == nil)
    }

    /// Cancelled (the helper quitting): nothing recorded.
    @Test func cancelledRecordsNothing() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let watch = try Self.watch(database)
        client.whileHashing = { _ in withUnsafeCurrentTask { $0?.cancel() } }
        let pass = Self.pass(client, database)
        let outcome = await Task { await pass.run(watch) }.value
        #expect(outcome == .cancelled)
        let after = try #require(try CommonPhotosWatchStore(database: database).watch(id: watch.id))
        #expect(after.checkedAt == nil && after.waiting == nil && after.isOn)
    }

    /// Not a set, or a row this build cannot read: never gathers, still
    /// listed.
    @Test func notASetCannotGather() async throws {
        let database = try AppDatabase.makeEmpty()
        let store = CommonPhotosWatchStore(database: database)
        #expect(throws: CommonPhotosWatchStore.NotASet.self) {
            try store.keepGathering(connectionId: "C1", folders: ["photos/A"], destination: "photos/Shared", action: .copy)
        }
        let watch = try Self.watch(database)
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE common_photo_watches SET action = 'teleport' WHERE id = ?", arguments: [watch.id])
        }
        let unreadable = try #require(try store.watches().first)
        #expect(!unreadable.isOn && unreadable.stopped == .cannotGather)
    }

    // MARK: Copy on its own, one run a day (AC-165, AC-173)

    private static func autoGather(_ client: InMemoryRemoteFileClient, _ database: AppDatabase) -> CommonPhotosAutoGather {
        CommonPhotosAutoGather(database: database, pass: pass(client, database), timeZone: TimeZone(identifier: "Asia/Tokyo")!)
    }

    private static func addCommon(_ client: InMemoryRemoteFileClient, _ name: String, seed: UInt8) {
        client.put("photos/A/\(name).HEIC", bytes(seed, size: 300_000 + Int(seed)))
        client.put("photos/B/copy \(name).HEIC", bytes(seed, size: 300_000 + Int(seed)))
    }

    private static func run(_ runId: String, _ client: InMemoryRemoteFileClient, _ database: AppDatabase) async throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("Gather-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        try await CommonPhotosRunner(client: client, store: CommonPhotosStore(database: database), workDirectory: work).run(runId)
    }

    /// AC-165: a Copy set, two new common photos — copied into Shared as a
    /// run of the day, read back, with its log, nobody at the sheet.
    @Test func copiesWithoutTheApp() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        try await Self.gather(client, database)
        let watch = try Self.watch(database)
        Self.addCommon(client, "N1", seed: 41)
        Self.addCommon(client, "N2", seed: 42)
        let now = Date(timeIntervalSince1970: 1_793_700_000)  // 2026-11-03 in Tokyo

        let result = await Self.autoGather(client, database).gather(watch, now: now)

        #expect(result.outcome == .found(2))
        let runId = try #require(result.runId)
        try await Self.run(runId, client, database)
        let store = CommonPhotosStore(database: database)
        let run = try #require(try store.run(id: runId))
        #expect(run.watchId == watch.id && run.day == "2026-11-03" && run.state == .finished)
        #expect(try store.items(runId: runId).map(\.status) == [.copied, .copied])
        let placed = try store.items(runId: runId).compactMap(\.destinationPath)
        #expect(placed.count == 2 && placed.allSatisfy { client.files[$0] != nil })
        #expect(run.csvPath == "photos/Shared/ShotDex Common Photos 2026-11-03 auto.csv")
    }

    /// AC-173: three passes in a day, two photos each — one run of six and
    /// one log of six; the next day is another run.
    @Test func oneRunPerDay() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        try await Self.gather(client, database)
        let watch = try Self.watch(database)
        let gather = Self.autoGather(client, database)
        let day = Date(timeIntervalSince1970: 1_793_700_000)
        var ids: [String] = []
        for pass in 0..<3 {
            Self.addCommon(client, "D\(pass)a", seed: UInt8(50 + pass * 2))
            Self.addCommon(client, "D\(pass)b", seed: UInt8(51 + pass * 2))
            let result = await gather.gather(watch, now: day.addingTimeInterval(TimeInterval(pass * 900)))
            let runId = try #require(result.runId)
            try await Self.run(runId, client, database)
            ids.append(runId)
        }
        #expect(Set(ids).count == 1)
        let store = CommonPhotosStore(database: database)
        #expect(try store.items(runId: ids[0]).filter { $0.status == .copied }.count == 6)
        let csv = try #require(client.files["photos/Shared/ShotDex Common Photos 2026-11-03 auto.csv"])
        #expect(String(decoding: csv, as: UTF8.self).components(separatedBy: "\n").filter { $0.contains("Copied") }.count == 6)
        #expect(client.files.keys.filter { $0.hasSuffix(".csv") && $0.contains("2026-11-03") }.count == 1)

        Self.addCommon(client, "Next", seed: 90)
        let next = await gather.gather(watch, now: day.addingTimeInterval(24 * 3600))
        #expect(next.runId != nil && next.runId != ids[0])
        #expect(try store.run(id: try #require(next.runId))?.day == "2026-11-04")
    }

    /// The day's run still going (paused here): the pass adds nothing and
    /// the photo waits; once it is over, the next pass takes it.
    @Test func busyDayWaits() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        try await Self.gather(client, database)
        let watch = try Self.watch(database)
        let gather = Self.autoGather(client, database)
        let day = Date(timeIntervalSince1970: 1_793_700_000)
        Self.addCommon(client, "P1", seed: 61)
        let first = try #require(await gather.gather(watch, now: day).runId)
        let store = CommonPhotosStore(database: database)
        try store.markState(.paused, runId: first)

        Self.addCommon(client, "P2", seed: 62)
        let busy = await gather.gather(watch, now: day.addingTimeInterval(900))
        #expect(busy.outcome == .found(2) && busy.runId == nil)
        #expect(try store.items(runId: first).count == 1)

        try await Self.run(first, client, database)
        let later = await gather.gather(watch, now: day.addingTimeInterval(1_800))
        #expect(later.outcome == .found(1) && later.runId == first)
        #expect(try store.items(runId: first).map(\.position) == [0, 1])
    }

    /// A day the user stopped: what follows goes into a run of its own.
    @Test func stoppedDayStartsAnother() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        try await Self.gather(client, database)
        let watch = try Self.watch(database)
        let gather = Self.autoGather(client, database)
        let day = Date(timeIntervalSince1970: 1_793_700_000)
        Self.addCommon(client, "S1", seed: 71)
        let first = try #require(await gather.gather(watch, now: day).runId)
        try CommonPhotosStore(database: database).markState(.stopped, runId: first)

        Self.addCommon(client, "S2", seed: 72)
        let next = await gather.gather(watch, now: day.addingTimeInterval(900))
        let second = try #require(next.runId)
        #expect(second != first)
        #expect(try CommonPhotosStore(database: database).run(id: second)?.day == "2026-11-03")
    }

    /// One photo of the day undone: the next pass does not copy it back,
    /// and it no longer counts as gathered. Undone from a sheet's run, it is
    /// offered again (as before).
    @Test func undoneStaysUndone() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        try await Self.gather(client, database)
        let watch = try Self.watch(database)
        let gather = Self.autoGather(client, database)
        let day = Date(timeIntervalSince1970: 1_793_700_000)
        Self.addCommon(client, "U1", seed: 81)
        Self.addCommon(client, "U2", seed: 82)
        let runId = try #require(await gather.gather(watch, now: day).runId)
        try await Self.run(runId, client, database)
        let store = CommonPhotosStore(database: database)
        let before = try store.gathered(connectionId: "C1", folders: watch.folders, destination: watch.destination).photoCount
        let undo = try store.startUndo(of: runId, positions: [0])
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("GatherUndo-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        try await CommonPhotosUndoer(client: client, store: store, workDirectory: work).run(undo.id)
        #expect(try store.items(runId: runId).map(\.status) == [.undone, .copied])

        let again = await gather.gather(watch, now: day.addingTimeInterval(900))
        #expect(again.outcome == .nothingNew && again.runId == nil)
        let after = try store.gathered(connectionId: "C1", folders: watch.folders, destination: watch.destination).photoCount
        #expect(after == before - 1)
    }

    /// A Move set only finds its photos: no run, nothing moved (G7 asks).
    @Test func moveSetMovesNothing() async throws {
        let client = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let watch = try Self.watch(database, action: .move)
        let result = await Self.autoGather(client, database).gather(watch)
        #expect(result.outcome == .found(3) && result.runId == nil)
        #expect(client.removed.isEmpty)
    }

    /// On the local SMB test server, in a scratch folder: a real Copy
    /// gathers 3 photos; a pass then finds nothing new and reads no byte;
    /// a source folder removed on the server stops the set.
    @Test(.enabled(if: LocalSMBTestServer.isListening))
    func passOnTheServer() async throws {
        func smb() -> SMBFileClient {
            SMBFileClient(server: FileServer(name: "Test SMB", transferProtocol: .smb, host: "127.0.0.1", port: 4450,
                                             username: "tester", share: "photos"), password: "secret")
        }
        let database = try AppDatabase.makeEmpty()
        let root = "photos/e2e-g5-\(UUID().uuidString.prefix(8))"
        let admin = smb()
        try await admin.connect()
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("CommonPhotosG5-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        do {
            for folder in ["A", "B", "Shared"] { try await admin.createDirectory("\(root)/\(folder)") }
            for n in 1...3 {
                let name = String(format: "IMG_%04d.JPG", n)
                let local = work.appendingPathComponent(name)
                _ = try await admin.download("photos/Tuan/2025/06/\(name)", to: local, progress: { _ in })
                try await admin.upload(local, to: "\(root)/A/\(name)", progress: { _ in })
                try await admin.upload(local, to: "\(root)/B/copy \(name)", progress: { _ in })
            }
            let sheet = CommonPhotosScanModel(connectionId: "smb", sourceId: "S", folders: ["\(root)/A", "\(root)/B"],
                                              client: smb(), database: database)
            sheet.destination = "\(root)/Shared"
            await sheet.scanToEnd()
            let made = try #require(sheet.makeRun())
            #expect(made.items.count == 3)
            let store = CommonPhotosStore(database: database)
            try store.start(made.run, items: made.items)
            try await CommonPhotosRunner(client: admin, store: store, workDirectory: work).run(made.run.id)
            await sheet.close()

            let watch = try CommonPhotosWatchStore(database: database).keepGathering(
                connectionId: "smb", folders: ["\(root)/A", "\(root)/B"], destination: "\(root)/Shared", action: .copy)
            let reader = smb()
            let pass = CommonPhotosGatherPass(database: database, connection: { _ in (reader, "Test SMB") },
                                              conditions: { (false, true) })
            #expect(await pass.run(watch) == .nothingNew)

            // AC-165 on the server: a new common photo is copied on its own.
            let name = "IMG_0004.JPG"
            let local = work.appendingPathComponent(name)
            _ = try await admin.download("photos/Tuan/2025/06/\(name)", to: local, progress: { _ in })
            try await admin.upload(local, to: "\(root)/A/\(name)", progress: { _ in })
            try await admin.upload(local, to: "\(root)/B/copy \(name)", progress: { _ in })
            let result = await CommonPhotosAutoGather(database: database, pass: pass).gather(watch)
            #expect(result.outcome == .found(1))
            try await CommonPhotosRunner(client: admin, store: store, workDirectory: work).run(try #require(result.runId))
            let shared = try await admin.entries(in: "\(root)/Shared").map(\.name)
            #expect(shared.contains(name))
            #expect(shared.contains { $0.hasSuffix(" auto.csv") })

            try await admin.removeFolderTree("\(root)/B")
            #expect(await pass.run(watch) == .stopped(.folderGone("\(root)/B")))
        } catch {
            try? await admin.removeFolderTree(root)
            await admin.disconnect()
            throw error
        }
        do { try await admin.removeFolderTree(root) } catch { Issue.record("left \(root) on the test share: \(error)") }
        await admin.disconnect()
    }
}
