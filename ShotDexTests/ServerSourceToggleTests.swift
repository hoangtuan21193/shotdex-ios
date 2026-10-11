import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.03 §1 — Add as Source on a connection.
@MainActor
@Suite struct ServerSourceToggleTests {
    /// AC-39, data half: saving NAS Home with Add as Source on adds a server
    /// source and reads its Folder at once — the Sources group shows
    /// "NAS Home · 3" with its protocol. Turning it off removes the source:
    /// its photos leave the grid, nothing on the server is touched, and the
    /// connection stays for uploads.
    @Test func addAsSourceIndexesThenOffRemoves() async throws {
        let client = InMemoryRemoteFileClient()
        for n in 1...3 { client.put("Photos/2026/DSC\(n).ARW", try ServerSourceIndexTests.raw(padding: 1_024, seed: UInt8(n))) }
        let database = try AppDatabase.makeEmpty()
        let servers = FileServerStore(database: database, passwords: InMemoryPasswordStore())
        let nas = FileServer(id: "C1", name: "NAS Home", transferProtocol: .smb, host: "127.0.0.1", username: "tester", folder: "Photos/2026")
        try servers.save(nas, password: "secret")
        let refresh = ServerSourceRefresh(database: database, servers: servers, composer: ServerSourceIndexTests.composer) { _, _ in client }
        let sources = SourcesModel(database: database,
                                   runner: FolderSourceRunner(database: database, metadataStore: MetadataStore(database: database), thumbnails: nil),
                                   servers: refresh, photoLibrary: PhotoLibraryService())

        await sources.setServerSource(true, connection: nas)
        let row = try #require(sources.rows.first { $0.name == "NAS Home" })
        #expect(row.text.count == 3)
        #expect(row.text.badge == "Server")
        #expect(row.text.detail().hasPrefix("SMB · 3 items"))
        #expect(sources.readCount == 1)
        #expect(try LibraryQueries(database: database).count(matching: FilterCriteria()) == 3)

        // Saving again with the switch on adds nothing twice.
        await sources.setServerSource(true, connection: nas)
        #expect(sources.rows.filter { $0.name == "NAS Home" }.count == 1)

        await sources.setServerSource(false, connection: nas)
        #expect(!sources.rows.contains { $0.name == "NAS Home" })
        #expect(try LibraryQueries(database: database).count(matching: FilterCriteria()) == 0)
        #expect(client.files.count == 3)
        #expect(client.removed.isEmpty)
        #expect(try servers.fetch(id: "C1") != nil)
    }
}
