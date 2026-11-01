import Foundation
import GRDB
import Testing
@testable import ShotDex

/// Keep on This iPhone: the rows and the folder behind Utilities › On This
/// iPhone (intent 2026-10-19-keep-offline).
struct KeptStoreTests {
    private let store: KeptStore

    init() throws {
        store = KeptStore(database: try AppDatabase.makeEmpty())
    }

    private func item(_ id: String, video: Bool = false, album: String? = nil) -> KeptItem {
        KeptItem(id: id, isVideo: video, quality: .viewingCopy, albumId: album)
    }

    /// Keeping a photo again must not throw away the file already here.
    @Test func keepingAgainLeavesAFinishedItemAlone() throws {
        try store.add([item("A/L0/001")])
        try store.finish(id: "A/L0/001", fileName: "IMG_1.heic", byteCount: 1_200)

        let added = try store.add([item("A/L0/001"), item("B/L0/001")])

        #expect(added.map(\.id) == ["B/L0/001"])
        let kept = try #require(try store.item(id: "A/L0/001"))
        #expect(kept.state == .onDevice)
        #expect(kept.fileName == "IMG_1.heic")
        #expect(try store.totalBytes() == 1_200)
    }

    @Test func aFailureCarriesItsReasonUntilRetried() throws {
        try store.add([item("A")])
        try store.setState(id: "A", .failed, error: "Not enough space on this iPhone.")
        #expect(try store.item(id: "A")?.error == "Not enough space on this iPhone.")

        try store.setState(id: "A", .queued)
        #expect(try store.item(id: "A")?.error == nil)
    }

    /// Removing an album takes what it brought in, and nothing kept on its own.
    @Test func removingAnAlbumKeepsItemsKeptOnTheirOwn() throws {
        try store.save(KeptAlbum(id: "album-1", title: "Iceland 2026", quality: .viewingCopy, keepsNewPhotos: true))
        try store.add([item("A", album: "album-1"), item("B", album: "album-1"), item("C")])
        try store.finish(id: "A", fileName: "a.heic", byteCount: 10)

        #expect(try store.albumProgress()["album-1"]?.onDevice == 1)
        #expect(try store.albumProgress()["album-1"]?.total == 2)

        let removed = try store.removeAlbum(id: "album-1")

        #expect(Set(removed) == ["A", "B"])
        #expect(try store.keptIds() == ["C"])
        #expect(try store.albums().isEmpty)
    }

    @Test func theEstimateSplitsPhotosAndVideos() throws {
        try store.database.writer.write { db in
            for (id, type, size) in [("P1", 1, 20_000_000), ("P2", 1, 30_000_000), ("V1", 2, 100_000_000)] {
                try db.execute(sql: """
                    INSERT INTO photo_metadata (assetId, mediaType, fileSize, isFavorite, indexedAt, exifStatus, modificationDate)
                    VALUES (?, ?, ?, 0, 1, 'indexed', 100)
                    """, arguments: [id, type, size])
            }
        }

        let estimate = try store.estimate(ids: ["P1", "P2", "V1", "not-indexed"])

        #expect(estimate.photos == 3)
        #expect(estimate.videos == 1)
        #expect(estimate.unindexed == 1)
        #expect(estimate.originalBytes == 150_000_000)
        #expect(estimate.viewingCopyBytes == 3 * KeepEstimate.viewingPhotoBytes + 40_000_000)
    }
}

struct KeptFileStoreTests {
    private func makeStore() throws -> KeptFileStore {
        let root = FileManager.default.temporaryDirectory.appending(path: "KeptTests-\(UUID().uuidString)")
        let files = KeptFileStore(root: root)
        try files.prepare()
        return files
    }

    /// A PhotoKit id has slashes; it must still be one folder.
    @Test func aPhotoKitIdIsOneFolder() throws {
        let files = try makeStore()
        let work = try files.makeWorkFolder()
        let file = work.appending(path: "IMG_1.heic")
        try Data([1, 2, 3]).write(to: file)

        let placed = try files.finish(file, id: "ABC/L0/001", as: "IMG_1.heic")

        #expect(placed.bytes == 3)
        #expect(files.directory(for: "ABC/L0/001").lastPathComponent == "ABC_L0_001")
        var item = KeptItem(id: "ABC/L0/001", isVideo: false, quality: .original, albumId: nil)
        item.state = .onDevice
        item.fileName = placed.name
        #expect(FileManager.default.fileExists(atPath: try #require(files.file(for: item)).path))
    }

    /// The sweep marks a vanished file missing — it never deletes a row — and
    /// clears folders no row explains.
    @Test func theSweepReportsMissingFilesAndClearsStrays() throws {
        let files = try makeStore()
        try FileManager.default.createDirectory(at: files.directory(for: "stray"), withIntermediateDirectories: true)
        var gone = KeptItem(id: "gone", isVideo: false, quality: .original, albumId: nil)
        gone.state = .onDevice
        gone.fileName = "x.heic"

        let missing = files.sweep(items: [gone])

        #expect(missing == ["gone"])
        #expect(!FileManager.default.fileExists(atPath: files.directory(for: "stray").path))
    }

    @Test func theFolderIsLeftOutOfBackups() throws {
        let files = try makeStore()
        let values = try files.root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }
}
