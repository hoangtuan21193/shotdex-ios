import Foundation
import Testing
@testable import ShotDex

/// File servers and the upload history (FS-15 §4): the history is evidence
/// that a file is safe elsewhere, so it outlives the server that holds it.
@Suite @MainActor struct ServerUploadStoreTests {
    private struct Stores {
        let servers: FileServerStore
        let uploads: ServerUploadStore
        let passwords: InMemoryPasswordStore
    }

    private func makeStores() throws -> Stores {
        let database = try AppDatabase.makeEmpty()
        let passwords = InMemoryPasswordStore()
        return Stores(
            servers: FileServerStore(database: database, passwords: passwords),
            uploads: ServerUploadStore(database: database),
            passwords: passwords
        )
    }

    private func upload(_ assetId: String, _ key: String, server: FileServer, at time: Int = 1_000) -> ServerUploadRecord {
        ServerUploadRecord(
            assetId: assetId, fileKey: key, serverId: server.id, serverName: server.name,
            remotePath: "Photos/\(key)", byteCount: 10, sha256: "ab", uploadedAt: time
        )
    }

    @Test func deletingServerKeepsHistory() throws {
        let stores = try makeStores()
        let nas = FileServer(name: "NAS", transferProtocol: .smb, host: "nas.local", username: "me", share: "photo")
        try stores.servers.save(nas, password: "secret")
        for n in 0..<7 {
            try stores.uploads.record(upload("A\(n)", "photo:IMG_\(n).CR3", server: nas))
        }
        #expect(stores.passwords.password(for: nas.id) == "secret")

        try stores.servers.delete(id: nas.id)

        #expect(try stores.servers.count() == 0)
        #expect(try stores.uploads.count() == 7)
        let kept = try stores.uploads.uploads(assetId: "A3")
        #expect(kept.count == 1)
        #expect(kept[0].serverId == nil)
        #expect(kept[0].serverName == "NAS")
        #expect(stores.passwords.password(for: nas.id) == nil)
    }

    @Test func uploadedIdsQuery() throws {
        let stores = try makeStores()
        let nas = FileServer(name: "NAS", transferProtocol: .smb, host: "nas.local", username: "me", share: "photo")
        let studio = FileServer(name: "Studio", transferProtocol: .sftp, host: "studio.example.com", username: "me")
        try stores.servers.save(nas, password: nil)
        try stores.servers.save(studio, password: nil)
        try stores.uploads.record(upload("A", "photo:a.cr3", server: nas, at: 100))
        try stores.uploads.record(upload("A", "alternatePhoto:a.jpg", server: nas, at: 100))
        try stores.uploads.record(upload("B", "photo:b.cr3", server: studio, at: 300))
        try stores.uploads.record(upload("C", "photo:c.cr3", server: nas, at: 200))

        #expect(try stores.uploads.uploadedAssetIds() == ["A", "B", "C"])
        #expect(try stores.uploads.uploadedAssetIdsNewestFirst() == ["B", "C", "A"])
        let keys = try stores.uploads.uploadedFileKeys(assetIds: ["A", "Z"])
        #expect(keys == ["A": ["photo:a.cr3", "alternatePhoto:a.jpg"]])
    }

    @Test func mostRecentlyUsedServerIsTheDefault() throws {
        let stores = try makeStores()
        let first = FileServer(name: "First", transferProtocol: .smb, host: "a", username: "u", share: "s", createdAt: 1)
        let second = FileServer(name: "Second", transferProtocol: .sftp, host: "b", username: "u", createdAt: 2)
        try stores.servers.save(first, password: nil)
        try stores.servers.save(second, password: nil)
        #expect(try stores.servers.mostRecentlyUsed()?.id == first.id)

        try stores.servers.markUsed(second.id, folder: "", usesDateFolders: false, at: Date(timeIntervalSince1970: 5_000))
        #expect(try stores.servers.mostRecentlyUsed()?.id == second.id)
    }

    @Test func changingHostForgetsTrustedKey() throws {
        let stores = try makeStores()
        var server = FileServer(name: "Mac", transferProtocol: .sftp, host: "mac.local", username: "u",
                                hostKeyFingerprint: "SHA256:abc")
        try stores.servers.save(server, password: nil)
        server.name = "My Mac"
        try stores.servers.save(server, password: nil)
        #expect(try stores.servers.fetch(id: server.id)?.hostKeyFingerprint == "SHA256:abc")

        server.host = "other.local"
        try stores.servers.save(server, password: nil)
        #expect(try stores.servers.fetch(id: server.id)?.hostKeyFingerprint == nil)
    }

    /// AC-18: the same server added twice gets a second name, and editing a
    /// connection does not number it against itself.
    @Test func saveNumbersDuplicateName() throws {
        let stores = try makeStores()
        let first = FileServer(name: "nas.local", transferProtocol: .smb, host: "nas.local", username: "u", share: "s")
        let named = FileServer(name: "NAS", transferProtocol: .smb, host: "nas.local", username: "u", share: "s")
        try stores.servers.save(first, password: nil)
        try stores.servers.save(named, password: nil)

        let again = FileServer(name: "nas.local", transferProtocol: .smb, host: "nas.local", username: "v", share: "s")
        let lower = FileServer(name: "nas", transferProtocol: .sftp, host: "nas.local", username: "u")
        try stores.servers.save(again, password: nil)
        try stores.servers.save(lower, password: nil)
        #expect(try stores.servers.fetch(id: again.id)?.name == "nas.local (2)")
        #expect(try stores.servers.fetch(id: lower.id)?.name == "nas (2)")

        var edited = named
        edited.username = "someone"
        try stores.servers.save(edited, password: nil)
        #expect(try stores.servers.fetch(id: named.id)?.name == "NAS")
    }

    /// AC-19, store half: an upload remembers its folder and switch; a new
    /// default folder typed in the form forgets the folder but not the switch.
    @Test func editingFolderForgetsRememberedFolder() throws {
        let stores = try makeStores()
        var server = FileServer(name: "A", transferProtocol: .smb, host: "a", username: "u", share: "s", folder: "Photos")
        try stores.servers.save(server, password: nil)
        #expect(try stores.servers.fetch(id: server.id)?.startingUploadFolder == "Photos")
        #expect(try stores.servers.fetch(id: server.id)?.usesDateFolders == false)

        try stores.servers.markUsed(server.id, folder: "/Photos/Trip/", usesDateFolders: true)
        var saved = try #require(try stores.servers.fetch(id: server.id))
        #expect(saved.startingUploadFolder == "Photos/Trip")
        #expect(saved.usesDateFolders)

        // A form opened before that upload still saves without undoing it.
        server.username = "other"
        try stores.servers.save(server, password: nil)
        saved = try #require(try stores.servers.fetch(id: server.id))
        #expect(saved.startingUploadFolder == "Photos/Trip")

        server.folder = "Archive"
        try stores.servers.save(server, password: nil)
        saved = try #require(try stores.servers.fetch(id: server.id))
        #expect(saved.startingUploadFolder == "Archive")
        #expect(saved.usesDateFolders)
    }
}
