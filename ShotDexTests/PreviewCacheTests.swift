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

    /// AC-37: a 5 GB cache at 4.995 GB — thumbnails of folders and the NAS,
    /// and 300 full-size previews — takes 200 more 40 KB NAS thumbnails. It
    /// ends at or under 5 GB by dropping the longest-unopened preview; not
    /// one thumbnail goes.
    @Test func evictsPreviewsBeforeThumbnails() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        func item(_ name: String, _ kind: PreviewCacheEviction.Kind, _ size: Int64, _ minutes: Int) -> PreviewCacheEviction.Item {
            PreviewCacheEviction.Item(url: URL(fileURLWithPath: "/cache/\(name)"), kind: kind, size: size,
                                      lastUsed: start.addingTimeInterval(Double(minutes) * 60))
        }
        // Thumbnails are older than every preview: age alone would take them.
        let thumbnails = (0..<64_875).map { item("t\($0).jpg", .thumbnail, 40_000, $0 % 1_000) }
        let previews = (0..<300).map { item("p\($0).heic", .preview, 8_000_000, 2_000 + $0) }
        let added = (0..<200).map { item("nas\($0).jpg", .thumbnail, 40_000, 5_000 + $0) }
        let items = (thumbnails + previews + added).shuffled()
        let limit = PreviewCachePolicy.bytes(gigabytes: 5)

        let victims = PreviewCacheEviction.victims(items, limit: limit)
        #expect(victims.map(\.url.lastPathComponent) == ["p0.heic"])
        #expect(victims.allSatisfy { $0.kind == .preview })
        let left = items.reduce(Int64(0)) { $0 + $1.size } - victims.reduce(Int64(0)) { $0 + $1.size }
        #expect(left <= limit)

        // With no previews left, thumbnails go oldest first.
        let onlyThumbnails = [item("old.jpg", .thumbnail, 600, 1), item("new.jpg", .thumbnail, 600, 9)]
        #expect(PreviewCacheEviction.victims(onlyThumbnails, limit: 1_000).map(\.url.lastPathComponent) == ["old.jpg"])
        #expect(PreviewCacheEviction.victims(onlyThumbnails, limit: 1_200).isEmpty)
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
