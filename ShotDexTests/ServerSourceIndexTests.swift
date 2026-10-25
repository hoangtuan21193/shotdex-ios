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
        // Its whole-file hash, once known, is not lost to the move (FS-19.07 §5).
        try CopyFileStore(database: database).saveHash("sha-a", copyId: before.id, fileKey: "primary", origin: .hashed)

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
        #expect(try CopyFileStore(database: database).files(copyId: after.id).map(\.sha256) == ["sha-a"])
    }

    /// FS-19.07 §5: each time the app comes to the foreground the listing
    /// is compared again — not while it stays in front, not on any clock.
    /// Rescan, and a server back from Not reachable, each compare once.
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

        let launch = await refresh.appBecameActive()
        #expect(launch[source]?.photos == 2)
        let onePass = client.listingCount
        #expect(onePass == 3)

        // Staying in front with the server still there, time passing: nothing.
        #expect(await refresh.serverReachable(sourceId: source) == nil)
        try await Task.sleep(for: .milliseconds(300))
        #expect(client.listingCount == onePass)

        // Back to the foreground: one pass, nothing read again.
        let reads = client.rangeReadPaths.count
        #expect(await refresh.appBecameActive()[source]?.unchanged == 2)
        #expect(client.listingCount == onePass * 2)
        #expect(client.rangeReadPaths.count == reads)

        // Rescan: one pass.
        #expect(await refresh.rescan(sourceId: source)?.unchanged == 2)
        #expect(client.listingCount == onePass * 3)

        // Server gone, then back: one pass when it returns.
        try SourceStore(database: database).setOnline(false, sourceId: source)
        #expect(await refresh.serverReachable(sourceId: source)?.unchanged == 2)
        #expect(client.listingCount == onePass * 4)
        #expect(await refresh.serverReachable(sourceId: source) == nil)
    }

    /// AC-87 (album): a photo on `Shared/` is in **is**; the script deletes
    /// the file; the app comes to the foreground — the check lists the
    /// source again and the photo moves to **is not**.
    @MainActor
    @Test func rescanOnForeground() async throws {
        let data = try Self.raw(padding: 4_096, seed: 7)
        let client = InMemoryRemoteFileClient()
        client.put("iCloud Photo/Shared/2025/c.ARW", data)
        let f = try OnServerFixture(photos: 1)
        let servers = FileServerStore(database: f.database, passwords: InMemoryPasswordStore())
        try servers.save(FileServer(id: "C1", name: "NAS Home", transferProtocol: .smb, host: "nas.local", username: "u",
                                    folder: "iCloud Photo"), password: "pw")
        let refresh = ServerSourceRefresh(database: f.database, servers: servers, composer: Self.composer) { _, _ in client }
        let store = CopyFileStore(database: f.database)
        let check = OnServerCheck(environment: .init(
            serverSources: { [(id: f.source, name: "NAS Home", connectionId: "C1")] },
            jobRules: { _ in [] },
            conditions: { (false, true) },
            list: { id in await refresh.rescan(sourceId: id).map { !$0.disconnected && $0.stoppedBy == nil } ?? false },
            hashServer: { id, connectionId, now in
                try await ServerFileHashPass(store: store, client: client).run(sourceId: id, connectionId: connectionId,
                                                                                folder: "iCloud Photo", now: now)
            },
            hashPhotos: { _ in .init() }
        ))
        try f.photo(0, files: [("1:c.ARW", .raw, Int64(data.count), BackupFixture.sha(data))])

        await check.run()
        #expect(try await f.count(.isExactly, folder: "Shared") == 1)

        try await client.remove("iCloud Photo/Shared/2025/c.ARW")
        await check.run()
        #expect(try await f.count(.isExactly, folder: "Shared") == 0)
        #expect(try await f.count(.isNot, folder: "Shared") == 1)
    }

    /// FS-19.07 AC-96: `IMG_1.HEIC` + `IMG_1.MOV` are one Live Photo whose
    /// movie is its companion; `IMG_2.MOV` alone is a video. The pairing
    /// holds with RAW + JPEG pairing off, and the still's thumbnail is not
    /// read from the movie.
    @Test func pairsLivePhoto() async throws {
        let client = InMemoryRemoteFileClient()
        client.put("Photos/IMG_1.HEIC", try MetadataFixture.encode(.heic, options: MetadataFixture.Options()))
        client.put("Photos/IMG_1.MOV", Data(repeating: 1, count: 40_000))
        client.put("Photos/IMG_2.MOV", Data(repeating: 2, count: 50_000))
        let database = try AppDatabase.makeEmpty()
        let source = try SourceStore(database: database).addServer(name: "NAS Home", connectionId: "C1")
        let summary = try await Self.indexer(database, client).index(sourceId: source, folder: "Photos", pairsRawAndJpeg: false)
        #expect(summary.photos == 2)
        let copies = try await database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT c.relativePath, c.pairedPath, m.mediaType FROM photo_copies c JOIN photo_metadata m ON m.assetId = c.photoId
                WHERE c.sourceId = ? ORDER BY c.relativePath
                """, arguments: [source]).map { "\($0["relativePath"] as String) + \(($0["pairedPath"] as String?) ?? "-") \($0["mediaType"] as Int)" }
        }
        #expect(copies == ["IMG_1.HEIC + IMG_1.MOV \(MediaKind.photo.storedValue)", "IMG_2.MOV + - \(MediaKind.video.storedValue)"])
        let roles = try await database.reader.read { db in
            try String.fetchAll(db, sql: "SELECT f.fileKey || ':' || f.role FROM copy_files f JOIN photo_copies c ON c.id = f.copyId WHERE c.relativePath = 'IMG_1.HEIC' ORDER BY f.fileKey")
        }
        #expect(roles == ["companion:video", "primary:photo"])
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
        #expect(await refresh.appBecameActive()[source]?.photos == 1)

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

    /// FS-19.07 AC-84: of 50 files on the NAS, only those the size of a
    /// Photos file not yet matched are read whole — here 4, plus one that
    /// vanished after the listing, whose failure is recorded and does not
    /// stop the rest. A file the size of a Photos file that is already
    /// matched on this source is not read. The next pass reads only the
    /// failed file again.
    @Test func fullHashOnlySizeCandidates() async throws {
        let database = try AppDatabase.makeEmpty()
        let source = try SourceStore(database: database).addServer(name: "NAS Home", connectionId: "C1")
        let client = InMemoryRemoteFileClient()
        // Two files share 1,040 bytes: s40 is known, s41 is not.
        let data = Dictionary(uniqueKeysWithValues: (0..<50).map { n in (n, Data(repeating: UInt8(n), count: n == 41 ? 1_040 : 1_000 + n)) })
        for n in 0..<50 where n != 45 { client.put("iCloud Photo/Shared/f\(n).JPG", data[n]!) }
        try await database.writer.write { db in
            for n in 0..<50 {
                let size = data[n]!.count
                let path = "Shared/f\(n).JPG"
                try db.execute(sql: """
                    INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey, size)
                    VALUES (?, ?, ?, 'server', ?, ?, ?)
                    """, arguments: ["s\(n)", "p\(n)", source, path, path.lowercased(), size])
                try db.execute(sql: "INSERT INTO copy_files (copyId, fileKey, role, size, sha256) VALUES (?, 'primary', 'photo', ?, ?)",
                               arguments: ["s\(n)", size, n == 40 ? "known" : nil])
            }
            // Photos files: four unmatched sizes, one vanished candidate, one
            // matched by s40, one with no server file of its size.
            let photos: [(Int, String?)] = [(1_005, nil), (1_010, nil), (1_020, "other"), (1_030, nil), (1_045, nil),
                                            (1_040, "known"), (9_999, nil)]
            for (k, (size, sha)) in photos.enumerated() {
                try db.execute(sql: "INSERT INTO photo_copies (id, photoId, sourceId, kind, photoKitId) VALUES (?, ?, ?, 'photos', ?)",
                               arguments: ["photos:P\(k)", "P\(k)", PhotoLibrarySource.id, "P\(k)"])
                try db.execute(sql: "INSERT INTO copy_files (copyId, fileKey, role, size, stamp, sha256) VALUES (?, '1:IMG.HEIC', 'photo', ?, '', ?)",
                               arguments: ["photos:P\(k)", size, sha])
            }
        }
        let store = CopyFileStore(database: database)
        let pass = ServerFileHashPass(store: store, client: client)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let first = try await pass.run(sourceId: source, connectionId: "C1", folder: "iCloud Photo", now: now)

        #expect(first == .init(seeded: 0, hashed: 4, failed: 1))
        #expect(Set(client.sha256Paths) == Set([5, 10, 20, 30, 45].map { "iCloud Photo/Shared/f\($0).JPG" }))
        for n in [5, 10, 20, 30] {
            #expect(try store.files(copyId: "s\(n)").first?.sha256 == BackupFixture.sha(data[n]!))
            #expect(try store.files(copyId: "s\(n)").first?.origin == .hashed)
        }
        let failed = try #require(try store.files(copyId: "s45").first)
        #expect(failed.sha256 == nil)
        #expect(failed.attempts == 1)
        #expect(failed.lastError != nil)

        let second = try await pass.run(sourceId: source, connectionId: "C1", folder: "iCloud Photo", now: now.addingTimeInterval(60))
        #expect(second == .init(seeded: 0, hashed: 0, failed: 1))
        #expect(client.sha256Paths.count == 6)
        #expect(client.sha256Paths.last == "iCloud Photo/Shared/f45.JPG")
    }
}
