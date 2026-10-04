import Foundation
import Testing
@testable import ShotDex

/// FS-19 01b §3 — the one preview cache every source shares.
@Suite struct PreviewCacheTests {
    /// AC-47: the cache sits in the app's Application Support, carries the
    /// excluded-from-backup flag, and its limit defaults to 5 GB on iPhone
    /// and iPad (25 GB on the Mac) out of 2 / 5 / 10 / 25 / 50 GB. Server
    /// thumbnails live inside it, held to the same limit.
    @Test func locationAndDefaults() throws {
        #expect(PreviewCachePolicy.limitChoices == [2, 5, 10, 25, 50])
        #expect(PreviewCachePolicy.defaultLimit == 5)
        #expect(PreviewCachePolicy.limitChoices.contains(PreviewCachePolicy.defaultLimit))
        #expect(PreviewCachePolicy.bytes(gigabytes: 5) == 5_000_000_000)

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let standard = PreviewCacheLocation.standard
        #expect(standard.deletingLastPathComponent().standardizedFileURL == support.standardizedFileURL)
        #expect(standard.lastPathComponent == "PreviewCache")
        #expect(try standard.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)

        let servers = RemoteThumbnailCache.standard
        #expect(servers.directory.deletingLastPathComponent().standardizedFileURL == standard.standardizedFileURL)
        #expect(servers.limit == 5_000_000_000)
        #expect(FileManager.default.fileExists(atPath: servers.directory.path))
    }

    /// A fresh folder handed to `prepare` comes back created and flagged.
    @Test func prepareCreatesAndExcludes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PreviewCache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let prepared = PreviewCacheLocation.prepare(folder)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: prepared.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        #expect(try prepared.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }
}
