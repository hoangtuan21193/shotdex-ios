import Foundation
import Testing
@testable import ShotDex

/// FS-18.04 §3 AC-77: Settings › Servers' Delete Connection.
@MainActor
@Suite struct MacServersSettingsTests {
    private struct Fixture {
        let database: AppDatabase
        let servers: FileServerStore
        let sources: SourcesModel
        let client: InMemoryRemoteFileClient
        let nas: FileServer
        var deletion: ServerConnectionDeletion { ServerConnectionDeletion(database: database, servers: servers) }
    }

    /// NAS Home read as a source, 3 photos on it.
    private func fixture() async throws -> Fixture {
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
        return Fixture(database: database, servers: servers, sources: sources, client: client, nas: nas)
    }

    /// Deleted: the source and its 3 photos leave, the row, its password and its
    /// backup go; the files on the server stay.
    @Test func deleteConnection() async throws {
        let f = try await fixture()
        try BackupStore(database: f.database).add(BackupJob(sourceId: PhotoLibrarySource.id, connectionId: f.nas.id, folder: "Backup/iPhone"))
        let impact = try f.deletion.impact(of: f.nas.id)
        #expect(impact.photoCount == 3)
        #expect(impact.backupJobs == 1)

        try f.deletion.delete(connectionId: f.nas.id, readingSourceId: nil)

        #expect(try SourceStore(database: f.database).serverSourceId(connectionId: f.nas.id) == nil)
        #expect(try f.servers.fetch(id: f.nas.id) == nil)
        #expect(f.servers.password(for: f.nas.id) == nil)
        #expect(try f.deletion.impact(of: f.nas.id).backupJobs == 0)
        #expect(try LibraryQueries(database: f.database).count(matching: FilterCriteria()) == 0)
        #expect(f.client.files.count == 3)
    }

    /// While its source is read, nothing is deleted: the read would write the photos back.
    @Test func deleteWaitsForTheRead() async throws {
        let f = try await fixture()
        let sourceId = try #require(try SourceStore(database: f.database).serverSourceId(connectionId: f.nas.id))
        #expect(throws: ServerConnectionDeletion.Failure.sourceBusy) {
            try f.deletion.delete(connectionId: f.nas.id, readingSourceId: sourceId)
        }
        #expect(try f.servers.fetch(id: f.nas.id) != nil)
        #expect(try SourceStore(database: f.database).serverSourceId(connectionId: f.nas.id) == sourceId)
    }

    /// The dialog names what goes: photos only for a source, backups, and that the server keeps its files.
    @Test func deleteMessage() {
        let upload = ServerConnectionDeletion.Impact(sourceId: nil, photoCount: 0, backupJobs: 0, shortcuts: 0)
        #expect(ServerConnectionText.deleteMessage(upload) == "Nothing on the server is deleted. Its password leaves your Keychain.")
        let source = ServerConnectionDeletion.Impact(sourceId: "S", photoCount: 1_102, backupJobs: 2, shortcuts: 1)
        let text = ServerConnectionText.deleteMessage(source)
        #expect(text.hasPrefix("Its \(1_102.formatted(.number)) photos leave ShotDex"))
        #expect(text.contains("Its 2 backups are deleted too."))
        #expect(text.contains("Its folder shortcuts go too."))
    }
}
