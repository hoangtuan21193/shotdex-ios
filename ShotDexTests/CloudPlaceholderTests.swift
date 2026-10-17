import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.01b §4 — files only in the cloud.
@MainActor
@Suite struct CloudPlaceholderTests {
    /// AC-15: an iCloud Drive folder of 100 files, 40 of them placeholders
    /// (`.Name.ext.icloud` on iOS). The read opens none of the 40: 60 photos
    /// get EXIF and a metadata row — what filters and Statistics count — and
    /// 40 copies are recorded as cloud placeholders for the grid's cloud
    /// glyph. Once one downloads, the next read turns it into a full photo.
    @Test func neverDownloadsNeverCounts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("iCloud-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let jpeg = try MetadataFixture.encode(.jpeg, options: MetadataFixture.Options())
        for n in 0..<60 { try jpeg.write(to: root.appendingPathComponent("IMG_\(n).JPG")) }
        // A placeholder holds a small plist, never the picture.
        for n in 60..<100 { try Data("bplist00".utf8).write(to: root.appendingPathComponent(".IMG_\(n).JPG.icloud")) }

        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "iCloud Photos", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        let indexer = FolderSourceIndexer(database: database, composer: FolderSourceIndexTests.composer)
        let summary = try indexer.index(sourceId: sourceId, root: root, includesSubfolders: true, pairsRawAndJpeg: true)
        #expect(summary.photos == 60)
        #expect(summary.placeholders == 40)
        #expect(try count("SELECT COUNT(*) FROM photo_metadata", database) == 60)
        #expect(try count("SELECT COUNT(*) FROM photo_copies WHERE isCloudPlaceholder = 1", database) == 40)
        #expect(try count("SELECT COUNT(*) FROM content_hashes", database) == 60)
        #expect(try count("SELECT COUNT(*) FROM photo_copies WHERE relativePath LIKE '.%'", database) == 0)

        // IMG_60 downloads: the placeholder is replaced by the file.
        try FileManager.default.removeItem(at: root.appendingPathComponent(".IMG_60.JPG.icloud"))
        try jpeg.write(to: root.appendingPathComponent("IMG_60.JPG"))
        let again = try indexer.index(sourceId: sourceId, root: root, includesSubfolders: true, pairsRawAndJpeg: true)
        #expect(again.photos == 1)
        #expect(try count("SELECT COUNT(*) FROM photo_metadata", database) == 61)
        #expect(try count("SELECT COUNT(*) FROM photo_copies WHERE isCloudPlaceholder = 1", database) == 39)
        #expect(try count("SELECT COUNT(*) FROM photos", database) == 100)
    }

    /// AC-16: opening one of the 40 placeholders downloads exactly that file;
    /// once it is down the photo — same id — has EXIF, a hash and a tile, and
    /// Statistics counts 61. Cancel stops it and leaves the placeholder.
    @Test func openingOneDownloadsOnlyIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("iCloud-\(UUID().uuidString)", isDirectory: true)
        let tiles = FileManager.default.temporaryDirectory.appendingPathComponent("Tiles-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: tiles)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tiles, withIntermediateDirectories: true)
        // Every file different: identical bytes would be one photo (FS-19.02 §1).
        func jpeg(_ n: Int) throws -> Data { try MetadataFixture.encode(.jpeg, options: MetadataFixture.Options(width: 200 + n)) }
        for n in 0..<60 { try jpeg(n).write(to: root.appendingPathComponent("IMG_\(n).JPG")) }
        for n in 60..<100 { try Data("bplist00".utf8).write(to: root.appendingPathComponent(".IMG_\(n).JPG.icloud")) }

        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "iCloud Photos", bookmark: try root.bookmarkData(),
                                                                    includesSubfolders: true, pairsRawAndJpeg: true)
        let runner = FolderSourceRunner(database: database, metadataStore: MetadataStore(database: database),
                                        thumbnails: FolderThumbnails(directory: tiles) { nil })
        try await runner.read(sourceId: sourceId)
        let photoId = try #require(try await database.reader.read { db in
            try String.fetchOne(db, sql: "SELECT photoId FROM photo_copies WHERE relativePath = 'IMG_60.JPG'")
        })
        let file = try #require(try await runner.cloudFile(photoId: photoId))
        #expect(file.filename == "IMG_60.JPG")

        // Cancelled: nothing came down, the placeholder stays.
        let stalled = FakeCloudDownloader(jpeg: Data(), waitsForCancel: true)
        let cancelled = Task { try await runner.download(file, with: stalled) { _ in } }
        try await Task.sleep(for: .milliseconds(100))
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(try count("SELECT COUNT(*) FROM photo_copies WHERE isCloudPlaceholder = 1", database) == 40)

        let downloader = FakeCloudDownloader(jpeg: try jpeg(60))
        let outcome = try await runner.download(file, with: downloader, freeBytes: { _ in 50_000_000_000 }) { _ in }
        #expect(outcome == .downloaded)
        #expect(downloader.requested == [root.appendingPathComponent("IMG_60.JPG").standardizedFileURL.path])
        #expect(try count("SELECT COUNT(*) FROM photo_copies WHERE isCloudPlaceholder = 1", database) == 39)
        #expect(try count("SELECT COUNT(*) FROM photo_metadata WHERE assetId = '\(photoId)' AND cameraModel IS NOT NULL", database) == 1)
        #expect(try count("SELECT COUNT(*) FROM content_hashes", database) == 61)
        let copyId = try #require(try await database.reader.read { db in
            try String.fetchOne(db, sql: "SELECT id FROM photo_copies WHERE photoId = ?", arguments: [photoId])
        })
        #expect(FileManager.default.fileExists(atPath: tiles.appendingPathComponent(copyId + ".jpg").path))
        #expect(try StatisticsQueries(database: database).totalPhotos(scope: .allTime) == 61)
        #expect(try await runner.cloudFile(photoId: photoId) == nil)
    }

    /// No download starts when the file plus the 1 GB headroom does not fit.
    @Test func notEnoughSpaceNeverStarts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("iCloud-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["NSURLFileSizeKey": 3_000_000], format: .binary, options: 0)
        try plist.write(to: root.appendingPathComponent(".IMG_1.JPG.icloud"))
        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "iCloud Photos", bookmark: try root.bookmarkData(),
                                                                    includesSubfolders: true, pairsRawAndJpeg: true)
        let runner = FolderSourceRunner(database: database, metadataStore: MetadataStore(database: database), thumbnails: nil)
        try await runner.read(sourceId: sourceId)
        let photoId = try #require(try await database.reader.read { db in try String.fetchOne(db, sql: "SELECT photoId FROM photo_copies") })
        let file = try #require(try await runner.cloudFile(photoId: photoId))
        #expect(file.size == 3_000_000)
        let downloader = FakeCloudDownloader(jpeg: Data())
        let outcome = try await runner.download(file, with: downloader, freeBytes: { _ in 500_000_000 }) { _ in }
        #expect(outcome == .notEnoughSpace(short: 503_000_000))
        #expect(downloader.requested.isEmpty)
    }

    /// AC-15 grid half: cloud files sit among photos by the file's date when
    /// the grid sorts by date, and after every photo under a metric sort.
    @Test func cloudTilesMergeByDate() {
        func item(_ id: String, _ date: Int?) -> LibraryGridItem {
            LibraryGridItem(assetId: id, creationDate: date, mediaType: 1, originalFilename: nil, iso: nil, aperture: nil,
                            shutterSpeedDisplay: nil, focalLength: nil, equivalentFocalLength: nil, width: nil, height: nil, fileSize: nil)
        }
        let rows = [item("p30", 30), item("p10", 10), item("pNil", nil)]
        let cloud = [item("c5", 5), item("c20", 20), item("cNil", nil)]
        #expect(LibraryModel.merging(cloud, into: rows, sort: .dateTakenNewest).map(\.assetId)
                == ["p30", "c20", "p10", "c5", "pNil", "cNil"])
        #expect(LibraryModel.merging(cloud, into: rows.reversed().filter { $0.creationDate != nil }, sort: .dateTakenOldest).map(\.assetId)
                == ["c5", "p10", "c20", "p30", "cNil"])
        #expect(LibraryModel.merging(cloud, into: rows, sort: .isoDescending).map(\.assetId)
                == ["p30", "p10", "pNil", "c5", "c20", "cNil"])
    }

    private func count(_ sql: String, _ database: AppDatabase) throws -> Int {
        try database.reader.read { db in try Int.fetchOne(db, sql: sql) ?? -1 }
    }
}

/// Stands in for the file provider: "downloads" by swapping the placeholder
/// for the file, and records every URL it was asked for.
private final class FakeCloudDownloader: CloudFileDownloading, @unchecked Sendable {
    private let jpeg: Data
    private let waitsForCancel: Bool
    private let lock = NSLock()
    private var urls: [String] = []

    init(jpeg: Data, waitsForCancel: Bool = false) {
        self.jpeg = jpeg
        self.waitsForCancel = waitsForCancel
    }

    var requested: [String] { lock.withLock { urls } }

    func download(_ url: URL, progress: @escaping @Sendable (Double?) -> Void) async throws {
        if waitsForCancel {
            while true { try await Task.sleep(for: .milliseconds(20)) }
        }
        lock.withLock { urls.append(url.standardizedFileURL.path) }
        progress(0.5)
        try FileManager.default.removeItem(at: CloudPlaceholder.placeholderURL(for: url))
        try jpeg.write(to: url)
        progress(1)
    }
}
