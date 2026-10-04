import Foundation
import Testing
@testable import ShotDex

/// FS-03.07b §4 / FS-03.07c AC-2: the folder Export… wrote to is there next
/// time — a bookmark in the app's settings, five recents, renewed when it
/// moves, dropped when it is gone, kept when its drive is unplugged.
@Suite @MainActor struct ExportFolderStoreTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ExportFolderStore-\(UUID().uuidString)", isDirectory: true)

    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "ExportFolderStoreTests-\(UUID().uuidString)"))
    }

    private func folder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A fresh store on the same settings — the app after a relaunch —
    /// opens the folder without the picker.
    @Test func bookmarkSurvivesRelaunch() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = try defaults()
        let exports = try folder("Exports")
        try ExportFolderStore(defaults: defaults).remember(exports)

        let relaunched = ExportFolderStore(defaults: defaults)
        let current = try #require(relaunched.current)
        #expect(current.name == "Exports")
        guard case .available(let url) = relaunched.resolve(current) else { Issue.record("not available"); return }
        #expect(url.standardizedFileURL.path == exports.standardizedFileURL.path)
    }

    /// Moved since: it still opens, and the bookmark and the path are made
    /// again.
    @Test func staleBookmarkIsRenewed() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ExportFolderStore(defaults: try defaults())
        let exports = try folder("Exports")
        let saved = try store.remember(exports)
        let moved = root.appendingPathComponent("Client Exports", isDirectory: true)
        try FileManager.default.moveItem(at: exports, to: moved)

        let state = store.resolve(saved)

        guard case .available(let url) = state else { Issue.record("not available: \(state)"); return }
        #expect(url.lastPathComponent == "Client Exports")
        #expect(store.current?.name == "Client Exports")
        #expect(store.current?.bookmark != saved.bookmark)
    }

    @Test func recentsKeepFive() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ExportFolderStore(defaults: try defaults())
        for index in 1...6 { try store.remember(try folder("F\(index)")) }
        #expect(store.recents.map(\.name) == ["F6", "F5", "F4", "F3", "F2"])

        // Picking one already there moves it up, not in twice.
        try store.remember(root.appendingPathComponent("F3", isDirectory: true))
        #expect(store.recents.map(\.name) == ["F3", "F6", "F5", "F4", "F2"])
        store.use(try #require(store.recents.last))
        #expect(store.current?.name == "F2")
    }

    /// Deleted: *can't open this folder anymore*, out of the list. On a
    /// drive that is unplugged: *Not connected*, kept.
    @Test func goneFolderDropsFromRecents() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ExportFolderStore(defaults: try defaults())
        let exports = try folder("Exports")
        let saved = try store.remember(exports)
        try FileManager.default.removeItem(at: exports)

        #expect(store.resolve(saved) == .gone)
        #expect(store.recents.isEmpty)

        var onDrive = saved
        onDrive.id = UUID()
        onDrive.isOnExternalDrive = true
        onDrive.place = "T7"
        store.remember(onDrive)
        #expect(store.resolve(onDrive) == .notConnected)
        #expect(store.recents.map(\.title) == ["T7 › Exports"])
    }
}
