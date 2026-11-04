import Foundation
import Testing
@testable import ShotDex

/// FS-18.04 §3 AC-76: the preview cache held to the limit Settings picks.
@Suite struct MacPreviewCacheTests {
    private func cache() throws -> PreviewCacheStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PreviewCache-\(UUID().uuidString)", isDirectory: true)
        for folder in ["Thumbnails", PreviewCachePolicy.serverFolderName, "Previews"] {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        return PreviewCacheStore(directory: directory)
    }

    private func write(_ store: PreviewCacheStore, _ path: String, bytes: Int, daysAgo: Double) throws {
        let url = store.directory.appendingPathComponent(path)
        try Data(repeating: 7, count: bytes).write(to: url)
        let date = Date().addingTimeInterval(-daysAgo * 86_400)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    /// Over the limit, full-size previews go first, then the oldest thumbnails;
    /// what fits stays.
    @Test func limitTrims() throws {
        let store = try cache()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        // Written newest first: only the modification date can put "old" first.
        try write(store, "Previews/big.jpg", bytes: 400_000, daysAgo: 0)
        try write(store, "Servers/new.jpg", bytes: 40_000, daysAgo: 1)
        try write(store, "Thumbnails/old.jpg", bytes: 40_000, daysAgo: 30)
        let before = store.usage()
        #expect(before >= 480_000)

        store.trim(to: before - 1)
        #expect(!FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("Previews/big.jpg").path))
        #expect(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("Thumbnails/old.jpg").path))

        store.trim(to: store.usage() - 1)
        #expect(!FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("Thumbnails/old.jpg").path))
        #expect(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("Servers/new.jpg").path))
    }

    /// Clear Cache empties it; the folder stays, out of backups.
    @Test func clearEmpties() throws {
        let store = try cache()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try write(store, "Thumbnails/a.jpg", bytes: 1_000, daysAgo: 0)
        store.clear()
        #expect(store.usage() == 0)
        #expect(FileManager.default.fileExists(atPath: store.directory.path))
        // The writers keep their folders: a server thumbnail stored right after still lands.
        for folder in PreviewCacheStore.thumbnailFolders {
            #expect(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent(folder).path))
        }
        #expect(try store.directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    /// A server thumbnail and its record go together; a record left without
    /// its picture is not a hit, so the browser asks the server again.
    @Test func pairsGoTogether() throws {
        let store = try cache()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try write(store, "Servers/k1.jpg", bytes: 40_000, daysAgo: 9)
        try write(store, "Servers/k1.json", bytes: 100, daysAgo: 9)
        try write(store, "Servers/k2.jpg", bytes: 40_000, daysAgo: 0)
        try write(store, "Servers/k2.json", bytes: 100, daysAgo: 0)
        store.trim(to: store.usage() - 1)
        let left = try FileManager.default.contentsOfDirectory(atPath: store.directory.appendingPathComponent("Servers").path).sorted()
        #expect(left == ["k2.jpg", "k2.json"])
    }

    /// A trailing slash on the cache's own URL does not turn thumbnails into previews.
    @Test func trailingSlashKeepsKinds() throws {
        let store = try cache()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let slashed = PreviewCacheStore(directory: URL(fileURLWithPath: store.directory.path + "/", isDirectory: true))
        try write(store, "Thumbnails/t.jpg", bytes: 40_000, daysAgo: 30)
        try write(store, "Previews/p.jpg", bytes: 40_000, daysAgo: 0)
        slashed.trim(to: slashed.usage() - 1)
        #expect(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("Thumbnails/t.jpg").path))
        #expect(!FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("Previews/p.jpg").path))
    }

    /// The stored limit is one of the choices, else the platform default.
    @Test func storedLimit() throws {
        let suite = "MacPreviewCacheTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(PreviewCachePolicy.limit(from: defaults) == PreviewCachePolicy.defaultLimit)
        defaults.set(10, forKey: SettingsKeys.previewCacheLimitGB)
        #expect(PreviewCachePolicy.limit(from: defaults) == 10)
        defaults.set(7, forKey: SettingsKeys.previewCacheLimitGB)
        #expect(PreviewCachePolicy.limit(from: defaults) == PreviewCachePolicy.defaultLimit)
    }
}
