import Foundation
import Testing
@testable import ShotDex

/// FS-17.04 §5 — Network tiles in their own table.
@Suite @MainActor struct ServerShortcutStoreTests {
    private struct Stores {
        let servers: FileServerStore
        let shortcuts: ServerShortcutStore
        let history: ServerFileHistory
        let nas: FileServer
    }

    private func makeStores() throws -> Stores {
        let database = try AppDatabase.makeEmpty()
        let servers = FileServerStore(database: database, passwords: InMemoryPasswordStore())
        let nas = FileServer(name: "NAS", transferProtocol: .smb, host: "nas.local", username: "me", folder: "photos")
        try servers.save(nas, password: "p")
        return Stores(servers: servers, shortcuts: ServerShortcutStore(database: database),
                      history: ServerFileHistory(database: database), nas: nas)
    }

    /// AC-31.
    @Test func addIsIdempotent() throws {
        let stores = try makeStores()
        let first = try stores.shortcuts.add(serverId: stores.nas.id, path: "/photos/Trip/", name: "Trip")
        let again = try stores.shortcuts.add(serverId: stores.nas.id, path: "photos/Trip", name: "Other")
        #expect(first.id == again.id)
        #expect(try stores.shortcuts.fetchAll().map(\.path) == ["photos/Trip"])
        #expect(try stores.shortcuts.shortcut(serverId: stores.nas.id, path: "photos/Trip")?.name == "Trip")
    }

    /// AC-33.
    @Test func orderedByCreation() throws {
        let stores = try makeStores()
        try stores.shortcuts.add(serverId: stores.nas.id, path: "photos/B", name: "B")
        try stores.shortcuts.add(serverId: stores.nas.id, path: "photos/A", name: "A")
        #expect(try stores.shortcuts.fetchAll().map(\.name) == ["B", "A"])
    }

    /// AC-35: the cover lives in the database, so no network is needed to
    /// draw it.
    @Test func coverIsStored() throws {
        let stores = try makeStores()
        let tile = try stores.shortcuts.add(serverId: stores.nas.id, path: "photos/Trip", name: "Trip")
        #expect(tile.coverJPEG == nil)
        try stores.shortcuts.setCover(Data([0xFF, 0xD8, 0xFF]), for: tile.id)
        #expect(try stores.shortcuts.fetchAll().first?.coverJPEG == Data([0xFF, 0xD8, 0xFF]))
    }

    /// AC-36.
    @Test func renameAndRemoveLeaveServerAlone() throws {
        let stores = try makeStores()
        let tile = try stores.shortcuts.add(serverId: stores.nas.id, path: "photos/Trip", name: "Trip")
        try stores.shortcuts.rename(tile.id, to: "  Chọn lọc ")
        try stores.shortcuts.rename(tile.id, to: "   ")
        #expect(try stores.shortcuts.fetchAll().first?.name == "Chọn lọc")
        #expect(try stores.shortcuts.fetchAll().first?.path == "photos/Trip")
        try stores.shortcuts.remove(tile.id)
        #expect(try stores.shortcuts.fetchAll().isEmpty)
    }

    /// AC-37.
    @Test func deletingConnectionRemovesShortcuts() throws {
        let stores = try makeStores()
        try stores.shortcuts.add(serverId: stores.nas.id, path: "photos/A", name: "A")
        try stores.shortcuts.add(serverId: stores.nas.id, path: "photos/B", name: "B")
        try stores.servers.delete(id: stores.nas.id)
        #expect(try stores.shortcuts.fetchAll().isEmpty)
    }

    /// AC-38.
    @Test func followsRenameAndDelete() throws {
        let stores = try makeStores()
        try stores.shortcuts.add(serverId: stores.nas.id, path: "photos/Trip", name: "Trip")
        try stores.shortcuts.add(serverId: stores.nas.id, path: "photos/Tripod", name: "Tripod")
        try stores.history.move("photos/Trip", to: "photos/Holiday", on: stores.nas)
        #expect(Set(try stores.shortcuts.fetchAll().map(\.path)) == ["photos/Holiday", "photos/Tripod"])
        try stores.history.forgetUploads(at: "photos", on: stores.nas)
        #expect(try stores.shortcuts.fetchAll().isEmpty)
    }
}
