import Foundation
import Testing
@testable import ShotDex

/// A browser over an in-memory server, with the stores it writes to.
@MainActor
struct BrowserFixture {
    let client = InMemoryRemoteFileClient()
    let database: AppDatabase
    let servers: FileServerStore
    let uploads: ServerUploadStore
    let defaults: UserDefaults
    let server: FileServer
    let shortcuts: ServerShortcutCatalog

    init(transferProtocol: FileServer.TransferProtocol = .smb, host: String = "nas.local") throws {
        database = try AppDatabase.makeEmpty()
        servers = FileServerStore(database: database, passwords: InMemoryPasswordStore())
        uploads = ServerUploadStore(database: database)
        defaults = UserDefaults(suiteName: "ServerBrowserModelTests-\(UUID().uuidString)")!
        server = FileServer(name: "NAS", transferProtocol: transferProtocol, host: host, username: "me", folder: "photos")
        try servers.save(server, password: "p")
        shortcuts = ServerShortcutCatalog(store: ServerShortcutStore(database: database))
    }

    func model(start: String = "photos", mode: ServerBrowserModel.Mode = .browse, onForgot: @escaping () -> Void = {}) -> ServerBrowserModel {
        let session = ServerBrowseSession(server: server, client: client)
        let cache = RemoteThumbnailCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("thumbs-\(UUID().uuidString)"))
        let downloads = ServerDownloadStore(database: database)
        return ServerBrowserModel(
            session: session, start: start, mode: mode,
            fileHistory: ServerFileHistory(database: database), shortcuts: mode == .browse ? shortcuts : nil, defaults: defaults,
            onUploadsForgotten: onForgot
        ) { path in
            ServerFolderModel(session: session, folder: path, cache: cache, downloads: downloads, existingAssetIds: { _ in [] })
        }
    }
}

/// FS-17.01 §2, §5 — FS-17 AC-21, 24, 28; FS-15 AC-22, 23.
@Suite @MainActor struct ServerBrowserModelTests {
    /// AC-21: one layout for folders and photos, remembered per connection.
    @Test func viewModeSharedByFoldersAndPhotos() async throws {
        let fixture = try BrowserFixture()
        fixture.client.addDirectory("photos/2026")
        fixture.client.addDirectory("photos/2025")
        for name in ["c.JPG", "a.JPG", "b.png"] { fixture.client.put("photos/\(name)", Data([1])) }
        let model = fixture.model()
        await model.current.load()

        #expect(model.layout == .icons)
        #expect(model.items.map(\.id) == ["folder:2025", "folder:2026", "photo:a.JPG", "photo:b.png", "photo:c.JPG"])

        model.setLayout(.list)
        #expect(fixture.model().layout == .list)
        let other = FileServer(name: "Other", transferProtocol: .smb, host: "x", username: "me")
        #expect(fixture.defaults.string(forKey: "serverBrowser.layout.\(other.id)") == nil)
    }

    /// AC-24: New Folder makes it, opens it and puts it in the history.
    @Test func newFolderOpensIt() async throws {
        let fixture = try BrowserFixture()
        fixture.client.addDirectory("photos")
        let model = fixture.model()
        await model.current.load()

        #expect(await model.createFolder(named: "Trip"))
        #expect(model.path == "photos/Trip")
        #expect(try await fixture.client.directoryExists("photos/Trip"))
        #expect(model.goBack())
        #expect(model.path == "photos")
        #expect(model.current.contents.folders == ["Trip"])

        #expect(!(await model.createFolder(named: ".x")))
        #expect(!(await model.createFolder(named: "a/b")))
        // Already there: opened, not an error.
        #expect(await model.createFolder(named: "Trip"))
        #expect(model.path == "photos/Trip")
        #expect(model.editError == nil)
    }

    /// AC-24, AC-28: the SMB root holds only shares.
    @Test func chooseModeRules() async throws {
        let fixture = try BrowserFixture()
        fixture.client.put("photos/a.CR3", Data([1]))
        let model = fixture.model(start: "", mode: .chooseFolder)
        #expect(model.isAtSMBRoot)
        #expect(!model.canChoose)
        #expect(!model.canCreateFolder)
        #expect(!(await model.createFolder(named: "New")))

        model.open(folder: "photos")
        #expect(model.canChoose)
        #expect(model.canCreateFolder)
        #expect(!model.canSelect)
        #expect(!model.canEdit)
        #expect(model.title == "photos")
        #expect(model.title(for: "") == "NAS")
    }

    /// FS-15 AC-22: choosing lists folders and shows photos, dimmed by the
    /// screen because they cannot be picked.
    @Test func chooseModeListsFoldersAndDimsPhotos() async throws {
        let fixture = try BrowserFixture()
        for folder in ["Photos/RAW", "Photos/.snapshots", "Photos/10", "Photos/2"] { fixture.client.addDirectory(folder) }
        fixture.client.put("Photos/a.CR3", Data([1]))
        let model = fixture.model(start: "Photos", mode: .chooseFolder)
        await model.current.load()

        #expect(model.items.map(\.id) == ["folder:2", "folder:10", "folder:RAW", "photo:a.CR3"])
        #expect(!model.canSelect)
        #expect(await model.createFolder(named: "Trip"))
        #expect(model.path == "Photos/Trip")
        #expect(model.canChoose)
    }

    /// FS-15 AC-23: a refused login shows the reason; Try Again dials again.
    @Test func failureShowsReasonAndRetries() async throws {
        let fixture = try BrowserFixture()
        fixture.client.addDirectory("photos/RAW")
        fixture.client.connectError = .authenticationFailed
        let model = fixture.model()
        await model.current.load()
        #expect(model.current.listing == .failed(.authenticationFailed))
        #expect(model.current.listing.failure?.localizedDescription == "The username or password was rejected.")

        fixture.client.connectError = nil
        await model.current.load(force: true)
        #expect(model.current.listing == .loaded)
        #expect(model.current.contents.folders == ["RAW"])
    }

    /// FS-17.04 AC-31, 32: Add to Collections toggles a tile for the folder
    /// on screen or a folder in it; never at an SMB root, never while
    /// choosing a folder.
    @Test func shortcutToggle() async throws {
        let fixture = try BrowserFixture()
        fixture.client.addDirectory("photos/Trip")
        let model = fixture.model(start: "photos/Trip")

        #expect(model.canAddShortcut(at: model.path))
        #expect(!model.isShortcut(model.path))
        model.toggleShortcut(at: model.path)
        #expect(model.isShortcut("photos/Trip"))
        #expect(fixture.shortcuts.shortcuts.map(\.name) == ["Trip"])
        model.toggleShortcut(at: "photos/Trip")
        #expect(fixture.shortcuts.shortcuts.isEmpty)

        #expect(!model.canAddShortcut(at: ""))
        #expect(!fixture.model(mode: .chooseFolder).canAddShortcut(at: "photos"))

        let sftp = try BrowserFixture(transferProtocol: .sftp)
        let home = sftp.model(start: "")
        #expect(home.canAddShortcut(at: ""))
        home.toggleShortcut(at: "")
        #expect(sftp.shortcuts.shortcuts.map(\.name) == ["NAS"])
    }

    /// AC-22, remembered: Files' Sort By flips on a second pick and is kept
    /// per connection.
    @Test func sortByFlipsAndIsRemembered() async throws {
        let fixture = try BrowserFixture()
        let model = fixture.model()
        model.chooseSort(.size)
        #expect(model.sort == .size)
        #expect(!model.ascending)
        model.chooseSort(.size)
        #expect(model.ascending)
        model.chooseSort(.name)
        #expect(model.ascending)
        model.chooseSort(.dateModified)
        let reopened = fixture.model()
        #expect(reopened.sort == .dateModified)
        #expect(!reopened.ascending)
        #expect(reopened.current.sort == .dateModified)
    }
}

/// FS-17.01 §4b — AC-25, 26, 27.
@Suite @MainActor struct ServerBrowserEditTests {
    private func record(_ fixture: BrowserFixture, _ assetId: String, _ path: String, on server: FileServer) throws {
        try fixture.uploads.record(ServerUploadRecord(
            assetId: assetId, fileKey: "k:\(path)", serverId: server.id, serverName: server.name,
            remotePath: path, byteCount: 1, sha256: "ab"
        ))
    }

    /// AC-25.
    @Test func renamePairMovesHistory() async throws {
        let fixture = try BrowserFixture()
        fixture.client.put("photos/A.CR3", Data([1]))
        fixture.client.put("photos/A.JPG", Data([2]))
        fixture.client.put("photos/B.JPG", Data([3]))
        try record(fixture, "1", "photos/A.CR3", on: fixture.server)
        let model = fixture.model()
        await model.current.load()
        let pair = try #require(model.items.first { $0.id == "photo:A.JPG" })

        #expect(await model.rename(pair, to: "Beach"))
        #expect(Set(fixture.client.files.keys) == ["photos/Beach.CR3", "photos/Beach.JPG", "photos/B.JPG"])
        #expect(try fixture.uploads.uploads(assetId: "1").map(\.remotePath) == ["photos/Beach.CR3"])

        let beach = try #require(model.items.first { $0.id == "photo:Beach.JPG" })
        #expect(!(await model.rename(beach, to: "B")))
        #expect(model.editError == "An item named “B” already exists.")
        #expect(Set(fixture.client.files.keys) == ["photos/Beach.CR3", "photos/Beach.JPG", "photos/B.JPG"])
    }

    /// AC-26.
    @Test func deleteFolderIsRecursiveAndDropsProof() async throws {
        let fixture = try BrowserFixture()
        fixture.client.put("photos/2024/a.CR3", Data([1]))
        fixture.client.put("photos/2024/x/b.JPG", Data([2]))
        fixture.client.put("photos/keep.JPG", Data([3]))
        let sibling = FileServer(name: "NAS 2", transferProtocol: .smb, host: "NAS.local", username: "other")
        let elsewhere = FileServer(name: "Office", transferProtocol: .smb, host: "office.local", username: "me")
        try fixture.servers.save(sibling, password: "p")
        try fixture.servers.save(elsewhere, password: "p")
        try record(fixture, "A", "photos/2024/a.CR3", on: fixture.server)
        try record(fixture, "B", "photos/2024/a.CR3", on: sibling)
        try record(fixture, "C", "photos/2024/a.CR3", on: elsewhere)
        var forgot = 0
        let model = fixture.model(onForgot: { forgot += 1 })
        await model.current.load()

        await model.delete([.folder("2024")])

        #expect(Set(fixture.client.files.keys) == ["photos/keep.JPG"])
        #expect(!(try await fixture.client.directoryExists("photos/2024")))
        #expect(try fixture.uploads.uploadedAssetIds() == ["C"])
        #expect(forgot == 1)
        #expect(model.current.contents.folders.isEmpty)
    }

    /// AC-27.
    @Test func deleteStopsAtFirstFailure() async throws {
        let fixture = try BrowserFixture()
        for name in ["1.JPG", "2.JPG", "3.JPG"] { fixture.client.put("photos/\(name)", Data([1])) }
        fixture.client.refuseRemoving = ["photos/2.JPG"]
        let model = fixture.model()
        await model.current.load()

        await model.delete(model.items)

        #expect(Set(fixture.client.files.keys) == ["photos/2.JPG", "photos/3.JPG"])
        #expect(model.editError == "You don't have permission to write to photos/2.JPG.")
        #expect(model.current.photos.map(\.id) == ["2.JPG", "3.JPG"])
    }
}
