import Foundation
import Testing
@testable import ShotDex

/// FS-19.03 §5 — a server photo's original comes down only while it is open.
@Suite struct ServerOriginalTests {
    /// AC-34: NAS Home indexed; an ARW is opened in the viewer, then left.
    /// The original downloads to a scratch folder (the grid's preview was
    /// already there), leaving deletes the folder, and nothing reaches
    /// Photos — the library still counts one photo. Without room for it
    /// plus the headroom, nothing downloads.
    @Test func tempDeletedOnClose() async throws {
        let client = InMemoryRemoteFileClient()
        let raw = try ServerSourceIndexTests.raw(padding: 3 * 1024 * 1024, seed: 7)
        client.put("Photos/2026/DSC07.ARW", raw)
        let database = try AppDatabase.makeEmpty()
        let servers = FileServerStore(database: database, passwords: InMemoryPasswordStore())
        try servers.save(FileServer(id: "C1", name: "NAS Home", transferProtocol: .smb, host: "nas.local", username: "u",
                                    folder: "Photos/2026"), password: "pw")
        let source = try SourceStore(database: database).addServer(name: "NAS Home", connectionId: "C1")
        _ = try await ServerSourceIndexer(database: database, composer: FolderSourceIndexTests.composer, client: client, readsSidecars: false)
            .index(sourceId: source, folder: "Photos/2026", pairsRawAndJpeg: true)
        let copyId = try #require(try await database.reader.read { db in
            try String.fetchOne(db, sql: "SELECT id FROM photo_copies WHERE sourceId = ?", arguments: [source])
        })
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("ServerOriginal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let cramped = ServerOriginalLoader(database: database, servers: servers, makeClient: { _, _ in client },
                                           workDirectory: work, freeSpace: { 500_000_000 })
        await #expect(throws: ServerOriginalLoader.Failure.self) { try await cramped.load(copyId: copyId) }
        #expect(client.downloadCount == 0)

        let loader = ServerOriginalLoader(database: database, servers: servers, makeClient: { _, _ in client },
                                          workDirectory: work, freeSpace: { 100_000_000_000 })
        let original = try await loader.load(copyId: copyId)
        #expect(try Data(contentsOf: original.url) == raw)
        #expect(original.directory.lastPathComponent.hasPrefix(TemporaryWorkspace.serverEditPrefix))
        #expect(original.url.lastPathComponent == "DSC07.ARW")

        original.discard()
        #expect(try FileManager.default.contentsOfDirectory(atPath: work.path).isEmpty)
        #expect(try await database.reader.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photos") } == 1)
        #expect(try await database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_copies WHERE kind = 'photos'")
        } == 0)
    }
}
