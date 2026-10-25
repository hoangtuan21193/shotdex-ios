import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19 §3 (servers as sources): the server stack under the source read,
/// and the read itself against an in-memory server that counts every byte.
@Suite struct ServerSourceIndexTests {
    static let composer = MetadataComposer(sensorLookup: SensorLookup(records: [], customMappings: []))

    /// A RAW-named file whose head carries a sharp 480px JPEG with the
    /// camera's EXIF, followed by megabytes of image data — what a 30 MB ARW
    /// looks like to the thumbnail ladder and the hasher.
    static func raw(padding: Int, seed: UInt8) throws -> Data {
        var options = MetadataFixture.Options()
        options.width = 480
        options.height = 320
        var data = try MetadataFixture.encode(.jpeg, options: options)
        var tail = Data(repeating: 0x5A, count: padding)
        tail[tail.endIndex - 1] = seed
        data.append(tail)
        return data
    }

    private static func indexer(_ database: AppDatabase, _ client: InMemoryRemoteFileClient,
                                thumbnails: FolderThumbnails? = nil) -> ServerSourceIndexer {
        ServerSourceIndexer(database: database, composer: Self.composer, client: client,
                            thumbnails: thumbnails, readsSidecars: true)
    }

    /// AC-33: NAS Home, Folder Photos/2026 — nine folders of RAWs (27 here;
    /// the AC's 1,102 is the same per-file sum). The first read puts every
    /// photo in the library with its metadata and a thumbnail in the shared
    /// cache, and reads no more than the thumbnail ladder's 256 KB head plus
    /// the hash's 3 × 64 KB per file: no file is downloaded whole.
    @Test func rangeReadsOnly() async throws {
        let client = InMemoryRemoteFileClient()
        let padding = 2 * 1024 * 1024
        for folder in 1...9 {
            for n in 1...3 {
                client.put("Photos/2026/Day\(folder)/DSC0\(folder)\(n).ARW", try Self.raw(padding: padding, seed: UInt8(folder * 10 + n)))
            }
        }
        client.put("Photos/2026/.DS_Store", Data(count: 4_096))
        client.put("Photos/2026/.thumbs/DSC.ARW", try Self.raw(padding: 1_024, seed: 1))
        client.put("Photos/2026/Day1/notes.txt", Data("trip".utf8))
        client.put("Elsewhere/IMG_1.ARW", try Self.raw(padding: 1_024, seed: 2))

        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("ServerThumbs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cache) }
        let database = try AppDatabase.makeEmpty()
        let source = try SourceStore(database: database).addServer(name: "NAS Home", connectionId: "C1")

        let summary = try await Self.indexer(database, client, thumbnails: FolderThumbnails(directory: cache) { 100_000_000_000 })
            .index(sourceId: source, folder: "Photos/2026", pairsRawAndJpeg: true)

        #expect(summary.photos == 27)
        #expect(summary.stoppedBy == nil)
        #expect(client.downloadCount == 0)
        #expect(client.bytesRead <= 27 * (EmbeddedPreview.firstRead + 3 * ContentHasher.sampleSize))
        #expect(client.bytesRead < 27 * padding / 4)
        let rows = try await database.reader.read { db in
            (copies: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_copies WHERE sourceId = ? AND kind = 'server'", arguments: [source]),
             hashed: try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT fastHash) FROM content_hashes"),
             cameras: try String.fetchAll(db, sql: "SELECT DISTINCT cameraModel FROM photo_metadata"),
             paths: try String.fetchAll(db, sql: "SELECT relativePath FROM photo_copies ORDER BY relativePath"))
        }
        #expect(rows.copies == 27)
        #expect(rows.hashed == 27)
        #expect(rows.cameras.count == 1 && rows.cameras.first?.isEmpty == false)
        #expect(rows.paths.first == "Day1/DSC011.ARW")
        #expect(try FileManager.default.contentsOfDirectory(atPath: cache.path).count == 27)
    }

    /// AC-38: another computer adds 5 files to NAS Home/Photos/2026. Rescan
    /// adds 5 photos and opens none of the files it already had — they are
    /// matched by size and write time from the listing alone.
    @Test func rescanReadsOnlyNew() async throws {
        let client = InMemoryRemoteFileClient()
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        func add(_ path: String, seed: UInt8) throws {
            client.put(path, try Self.raw(padding: 64 * 1024, seed: seed))
            client.modified[path] = date
        }
        for n in 1...12 { try add("Photos/2026/Day\(n % 3)/DSC\(n).ARW", seed: UInt8(n)) }
        let database = try AppDatabase.makeEmpty()
        let source = try SourceStore(database: database).addServer(name: "NAS Home", connectionId: "C1")
        let first = try await Self.indexer(database, client).index(sourceId: source, folder: "Photos/2026", pairsRawAndJpeg: true)
        #expect(first.photos == 12)

        let added = (1...5).map { "Photos/2026/Day9/NEW\($0).ARW" }
        for (n, path) in added.enumerated() { try add(path, seed: UInt8(100 + n)) }
        let readsBefore = client.rangeReadPaths.count
        let rescan = try await Self.indexer(database, client).index(sourceId: source, folder: "Photos/2026", pairsRawAndJpeg: true)

        #expect(rescan.photos == 5)
        #expect(rescan.unchanged == 12)
        #expect(Set(client.rangeReadPaths.dropFirst(readsBefore)) == Set(added))
        #expect(client.downloadCount == 0)
        #expect(try await database.reader.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photos") } == 17)
    }

    /// FS-19.07 AC-76: a script moves and renames a file inside the source
    /// (`Shared/2025/a.ARW` → `Shared/x/b.ARW`). The next pass keeps the same
    /// copy and the same photo — matched by quick hash and size — and never
    /// reads the moved file whole.
    @Test func renameKeepsIdentity() async throws {
        let client = InMemoryRemoteFileClient()
        let padding = 1024 * 1024
        client.put("iCloud Photo/Shared/2025/a.ARW", try Self.raw(padding: padding, seed: 7))
        client.put("iCloud Photo/Shared/2025/c.ARW", try Self.raw(padding: padding, seed: 8))
        let database = try AppDatabase.makeEmpty()
        let source = try SourceStore(database: database).addServer(name: "NAS Home", connectionId: "C1")
        _ = try await Self.indexer(database, client).index(sourceId: source, folder: "iCloud Photo", pairsRawAndJpeg: true)
        func copy(_ path: String) async throws -> (id: String, photoId: String, missing: Int?)? {
            try await database.reader.read { db in
                try Row.fetchOne(db, sql: "SELECT id, photoId, missingSince FROM photo_copies WHERE sourceId = ? AND relativePath = ?",
                                 arguments: [source, path]).map { ($0["id"], $0["photoId"], $0["missingSince"]) }
            }
        }
        let before = try #require(try await copy("Shared/2025/a.ARW"))

        // The script makes the folder and moves the file (same bytes, new name).
        let moved = try #require(client.files["iCloud Photo/Shared/2025/a.ARW"])
        client.put("iCloud Photo/Shared/x/b.ARW", moved)
        try await client.remove("iCloud Photo/Shared/2025/a.ARW")
        let bytesBefore = client.bytesRead
        let rescan = try await Self.indexer(database, client).index(sourceId: source, folder: "iCloud Photo", pairsRawAndJpeg: true)

        let after = try #require(try await copy("Shared/x/b.ARW"))
        #expect(after.id == before.id)
        #expect(after.photoId == before.photoId)
        #expect(after.missing == nil)
        #expect(try await copy("Shared/2025/a.ARW") == nil)
        #expect(rescan.unchanged == 1)
        #expect(client.downloadCount == 0)
        #expect(client.bytesRead - bytesBefore <= EmbeddedPreview.firstRead + 3 * ContentHasher.sampleSize)
        #expect(try await database.reader.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photos") } == 2)
    }

    /// AC-55: NAS Home connected, the app open for hours, nothing touched.
    /// The listing is compared once at launch — not again when the app
    /// comes back to the foreground, not while the server stays reachable,
    /// not on any clock. Rescan, and a server back from Not reachable, each
    /// compare once.
    @Test func noTimedRescan() async throws {
        let client = InMemoryRemoteFileClient()
        client.put("Photos/2026/Day1/DSC1.ARW", try Self.raw(padding: 1_024, seed: 1))
        client.put("Photos/2026/Day2/DSC2.ARW", try Self.raw(padding: 1_024, seed: 2))
        let database = try AppDatabase.makeEmpty()
        let servers = FileServerStore(database: database, passwords: InMemoryPasswordStore())
        try servers.save(FileServer(id: "C1", name: "NAS Home", transferProtocol: .smb, host: "nas.local", username: "u",
                                    folder: "Photos/2026"), password: "pw")
        let source = try SourceStore(database: database).addServer(name: "NAS Home", connectionId: "C1")
        let refresh = ServerSourceRefresh(database: database, servers: servers, composer: Self.composer) { _, _ in client }

        let launch = await refresh.appLaunched()
        #expect(launch[source]?.photos == 2)
        let afterLaunch = client.listingCount
        #expect(afterLaunch == 3)

        // Back to the foreground, server still there, time passing.
        #expect(await refresh.appLaunched().isEmpty)
        #expect(await refresh.serverReachable(sourceId: source) == nil)
        try await Task.sleep(for: .milliseconds(300))
        #expect(client.listingCount == afterLaunch)

        // Rescan: one pass, nothing read again.
        let reads = client.rangeReadPaths.count
        #expect(await refresh.rescan(sourceId: source)?.unchanged == 2)
        #expect(client.listingCount == afterLaunch * 2)
        #expect(client.rangeReadPaths.count == reads)

        // Server gone, then back: one pass when it returns.
        try SourceStore(database: database).setOnline(false, sourceId: source)
        #expect(await refresh.serverReachable(sourceId: source)?.unchanged == 2)
        #expect(client.listingCount == afterLaunch * 3)
        #expect(await refresh.serverReachable(sourceId: source) == nil)
    }

    /// AC-36, source half: the NAS password was changed on the server.
    /// Three passes (launch, two Rescans) each stop at the login — one try,
    /// no file read, no prompt — and the row says Password rejected; the
    /// photos stay. Saving the new password in Edit Connection… and one
    /// Rescan bring it back.
    @Test func passwordRejectedRow() async throws {
        let client = InMemoryRemoteFileClient()
        client.put("Photos/2026/DSC1.ARW", try Self.raw(padding: 1_024, seed: 1))
        let database = try AppDatabase.makeEmpty()
        let servers = FileServerStore(database: database, passwords: InMemoryPasswordStore())
        let nas = FileServer(id: "C1", name: "NAS Home", transferProtocol: .smb, host: "nas.local", username: "u", folder: "Photos/2026")
        try servers.save(nas, password: "old")
        let sources = SourceStore(database: database)
        let source = try sources.addServer(name: "NAS Home", connectionId: "C1")
        let refresh = ServerSourceRefresh(database: database, servers: servers, composer: Self.composer) { _, _ in client }
        #expect(await refresh.appLaunched()[source]?.photos == 1)

        client.connectError = .authenticationFailed
        let connects = client.connectCount
        let reads = client.rangeReadPaths.count
        #expect(await refresh.rescan(sourceId: source)?.stoppedBy == .authenticationFailed)
        #expect(await refresh.rescan(sourceId: source)?.stoppedBy == .authenticationFailed)
        #expect(await refresh.rescan(sourceId: source)?.stoppedBy == .authenticationFailed)
        #expect(client.connectCount == connects + 3)
        #expect(client.rangeReadPaths.count == reads)
        #expect(try sources.status(sourceId: source) == .passwordRejected)
        // A refused password is not an unreachable server: the reachability
        // trigger leaves it alone, and the photo is still in the grid.
        #expect(await refresh.serverReachable(sourceId: source) == nil)
        #expect(try await database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_copies WHERE sourceId = ? AND isOnline = 1 AND missingSince IS NULL", arguments: [source])
        } == 1)

        try servers.save(nas, password: "new")
        client.connectError = nil
        #expect(await refresh.rescan(sourceId: source)?.stoppedBy == nil)
        #expect(try sources.status(sourceId: source) == .online)
    }

    private func photo(_ client: InMemoryRemoteFileClient, _ name: String) -> ServerDownloadItem {
        let data = RemoteThumbnailTests.jpeg(width: 200)
        client.put("Trip/\(name)", data)
        let entry = RemoteEntry(name: name, isDirectory: false, size: Int64(data.count), modified: nil)
        return ServerDownloadItem(photo: ServerPhoto(files: [entry]), folder: "Trip")
    }

    private func session(_ client: InMemoryRemoteFileClient) -> ServerDownloadSession {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("ShotDexSourceIndex-test-\(UUID().uuidString)")
        return ServerDownloadSession(client: client, creator: RecordingAssetCreator(), serverId: "S1", serverName: "NAS Home",
                                     workDirectory: work, albumId: nil, record: { _ in })
    }

    /// AC-36, client half: a password changed on the NAS stops the batch at
    /// the first refusal — no retry per file, and nothing in the session can
    /// ask for a password (the row reports it; signing in is the user's move).
    @Test func passwordRejectedNoPrompts() async {
        #expect(RemoteFileError.authenticationFailed.stopsBatch)

        let refusedAtLogin = InMemoryRemoteFileClient()
        let items = (1...3).map { photo(refusedAtLogin, "IMG_\($0).JPG") }
        refusedAtLogin.connectError = .authenticationFailed
        let atLogin = await session(refusedAtLogin).run(items)
        #expect(atLogin.stopReason == .error(.authenticationFailed))
        #expect(atLogin.outcomes == [.notAttempted, .notAttempted, .notAttempted])
        #expect(refusedAtLogin.connectCount == 1)
        #expect(refusedAtLogin.downloadCount == 0)

        let refusedMidway = InMemoryRemoteFileClient()
        let more = (1...3).map { photo(refusedMidway, "IMG_\($0).JPG") }
        refusedMidway.refuseDownload = (number: 2, error: .authenticationFailed)
        let midway = await session(refusedMidway).run(more)
        #expect(midway.stopReason == .error(.authenticationFailed))
        #expect(midway.outcomes.dropFirst() == [.notAttempted, .notAttempted])
        #expect(refusedMidway.downloadCount == 2)
        #expect(refusedMidway.connectCount == 1)
    }
}
