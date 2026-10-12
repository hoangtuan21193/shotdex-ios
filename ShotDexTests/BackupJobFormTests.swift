import Foundation
import Testing
@testable import ShotDex

/// New Backup (FS-22.01 §2).
@Suite @MainActor struct BackupJobFormTests {
    private func makeModel() throws -> (BackupFormModel, BackupStore, FileServer) {
        let database = try AppDatabase.makeEmpty()
        let servers = FileServerStore(database: database, passwords: InMemoryPasswordStore())
        let nas = FileServer(id: "S1", name: "NAS Home", transferProtocol: .webdav, host: "127.0.0.1", username: "me", folder: "")
        try servers.save(nas, password: "pw")
        let store = BackupStore(database: database)
        return (BackupFormModel(database: database, store: store, servers: servers), store, nas)
    }

    /// AC-3: Start needs a source, a connection and a folder; Only on Wi‑Fi
    /// starts on, Include Edited Versions off.
    @Test func startNeedsSourceDestinationFolder() throws {
        let (model, _, nas) = try makeModel()
        #expect(model.sourceId == PhotoLibrarySource.id)
        #expect(model.connectionId == nas.id)
        // No default folder: the user browses the server and chooses one.
        #expect(model.folder == nil)
        #expect(!model.canStart)
        #expect(model.settings.onlyOnWiFi)
        #expect(!model.settings.includesEditedVersions)

        model.folder = "Photos/Backup"
        #expect(model.canStart)
        model.choose(connection: "other")
        #expect(model.folder == nil)
        #expect(!model.canStart)
    }

    /// AC-26: the same source, connection and folder twice is refused and
    /// makes no second job.
    @Test func duplicateJobRefused() throws {
        let (model, store, _) = try makeModel()
        model.folder = "Backup/iPhone"
        #expect(model.save() != nil)
        let (_, _, _) = try makeModel()
        let again = BackupFormModel(database: store.database, store: store, servers: FileServerStore(database: store.database, passwords: InMemoryPasswordStore()))
        again.folder = "Backup/iPhone/"
        #expect(again.save() == nil)
        #expect(again.duplicateError)
        #expect(try store.jobs().count == 1)
    }

    /// A folder or drive source asks which folder inside it; Photos does not.
    @Test func folderSourceNeedsItsFolder() throws {
        let (model, store, nas) = try makeModel()
        model.folder = "Archive"
        model.choose(source: "folder-1")
        #expect(!model.canStart)
        model.sourceFolder = "Trips/2026"
        #expect(model.canStart)
        let job = try #require(model.save())
        #expect(job.sourceFolder == "Trips/2026")
        #expect(try store.job(id: job.id)?.sourceFolder == "Trips/2026")
        model.choose(source: PhotoLibrarySource.id)
        #expect(model.sourceFolder == nil)
        _ = nas
    }
}
