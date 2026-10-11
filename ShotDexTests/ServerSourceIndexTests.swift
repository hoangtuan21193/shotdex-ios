import Foundation
import Testing
@testable import ShotDex

/// FS-19 §3 (servers as sources): the server stack under the source read,
/// and the read itself against an in-memory server that counts every byte.
@Suite struct ServerSourceIndexTests {
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
        ServerSourceIndexer(database: database, composer: FolderSourceIndexTests.composer, client: client,
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
