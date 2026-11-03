import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ShotDex

/// FS-19.02 §1b — Photos assets take part in content identity.
@MainActor
@Suite struct PhotosHashTests {
    /// AC-49: hashing two Photos originals reads each into memory once,
    /// stores a fast and a full hash for its copy, and leaves no file behind:
    /// nothing the size of an original appears in the temporary or caches
    /// folders.
    /// A second run has nothing left to do; an unreadable original is skipped
    /// and stays queued.
    @Test func streamsWithoutDiskGrowth() async throws {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch(
            ["A", "B", "gone"].map { PhotoMarksStoreTests.record($0) }, cursorAssetId: nil)
        let originals = [
            "A": try MetadataFixture.encode(.jpeg, options: MetadataFixture.Options()),
            "B": try MetadataFixture.encode(.tiff, options: MetadataFixture.Options()),
        ]
        let reads = Counter()
        let pass = PhotosContentHashPass(store: ContentHashStore(database: database)) { assetId in
            reads.add(assetId)
            guard let data = originals[assetId] else { throw PhotosContentHashPass.ReadError.missingAsset }
            return data
        }
        let started = Date()

        #expect(try await pass.run() == 2)
        let sizes = Set(originals.values.map(\.count))
        #expect(Self.filesWritten(since: started).filter { sizes.contains($0.value) }.isEmpty)
        #expect(reads.ids.sorted() == ["A", "B", "gone"])

        let store = ContentHashStore(database: database)
        let a = try #require(try store.hash(copyId: "photos:A"))
        #expect(a == (try ContentHasher.hash(DataBytes(data: originals["A"]!), full: true)))
        #expect(try store.hash(copyId: "photos:gone") == nil)

        #expect(try await pass.run() == 0)
        #expect(try store.photosCopiesNeedingHash(limit: 10).map(\.assetId) == ["gone"])
    }

    /// FS-19.07 AC-114: the Photos side lists what joined the library last
    /// first — a picture imported today with a 2017 capture date must not
    /// wait behind 55,000 older shots — then newest capture first.
    @Test func listsRecentlyAddedFirst() throws {
        let database = try AppDatabase.makeEmpty()
        var imported = PhotoMarksStoreTests.record("A", created: 1_500_000_000)
        imported.indexedAt = 1_800_000_000
        var recentShot = PhotoMarksStoreTests.record("B", created: 1_750_000_000)
        recentShot.indexedAt = 1_700_000_000
        var olderShot = PhotoMarksStoreTests.record("C", created: 1_600_000_000)
        olderShot.indexedAt = 1_700_000_000
        try MetadataStore(database: database).saveBatch([olderShot, imported, recentShot], cursorAssetId: nil)

        let queue = try CopyFileStore(database: database).photosCopiesNeedingListing(limit: 10)
        #expect(queue.map(\.assetId) == ["A", "B", "C"])
    }

    /// A photo deleted from Photos takes its listed files and hashes with
    /// it — they were left behind, unreachable, for every deleted photo.
    @Test func deletedPhotoTakesItsFiles() throws {
        let database = try AppDatabase.makeEmpty()
        let metadata = MetadataStore(database: database)
        try metadata.saveBatch(["A", "B"].map { PhotoMarksStoreTests.record($0) }, cursorAssetId: nil)
        let store = CopyFileStore(database: database)
        for copy in try store.photosCopiesNeedingListing(limit: 10) {
            try store.saveListing(copyId: copy.copyId, stamp: copy.stamp,
                                  files: [PhotosFile(fileKey: "1:\(copy.assetId).HEIC", role: .photo, size: 4_000, stamp: "s")])
        }

        try metadata.deleteAssets(ids: ["A"])

        let left = try database.reader.read { db in
            (try String.fetchAll(db, sql: "SELECT fileKey FROM copy_files ORDER BY fileKey"),
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM copy_file_listings") ?? 0)
        }
        #expect(left.0 == ["1:B.HEIC"])
        #expect(left.1 == 1)
    }

    /// FS-19.07 AC-100: assets Backup already copied, whose files still
    /// carry the stamp the ledger recorded, get the ledger's SHA-256 for
    /// every file — listed from PhotoKit, nothing downloaded, though the NAS
    /// has files of their size. A file whose stamp changed is not seeded;
    /// neither is an asset Backup never saw, which is downloaded once to be
    /// hashed. A second pass lists nothing; an asset edited since is listed
    /// again and keeps the hash of a file that did not change.
    @Test func seedsFromBackupLedger() async throws {
        let f = try BackupFixture(photos: 5)
        #expect(await f.runner().run().stop == .finished)
        let ids = (0...5).map { "A\($0)" }
        try MetadataStore(database: f.database).saveBatch(
            ids.enumerated().map { PhotoMarksStoreTests.record($1, created: 1_700_000_000 + $0) }, cursorAssetId: nil)

        try Self.addServerFiles(f.database, sizes: [4_000])
        let lists = Counter()
        let downloads = Counter()
        var pass = PhotosFileHashPass(store: CopyFileStore(database: f.database)) { assetId in
            lists.add(assetId)
            let n = Int(assetId.dropFirst())!
            // A4 changed since its backup; A5 was never backed up.
            let stamp = n == 4 ? "4001:1" : "4000:1"
            return [PhotosFile(fileKey: "1:IMG_\(n).HEIC", role: .photo, size: n == 4 ? 4_001 : 4_000, stamp: stamp)]
        }
        pass.download = Self.writer(log: downloads) { _, _ in Data(repeating: 5, count: 4_000) }
        pass.freeBytes = { nil }

        let summary = try await pass.run()
        #expect(summary == .init(listed: 6, seeded: 4, hashed: 1))
        #expect(downloads.ids == ["A5"])
        // Newest first.
        #expect(lists.ids == ids.reversed())
        let store = CopyFileStore(database: f.database)
        for n in 0...3 {
            let file = try #require(try store.files(copyId: "photos:A\(n)").first)
            #expect(file.sha256 == BackupFixture.sha(f.contents[FakeAssetExporter.key("A\(n)", "1:IMG_\(n).HEIC")]!))
            #expect(file.origin == .backup)
        }
        #expect(try store.files(copyId: "photos:A4").first?.sha256 == nil)
        #expect(try store.files(copyId: "photos:A5").first?.origin == .hashed)

        #expect(try await pass.run() == .init(listed: 0, seeded: 0))

        var edited = PhotoMarksStoreTests.record("A1", created: 1_700_000_001)
        edited.modificationDate = 1_700_100_000
        try MetadataStore(database: f.database).saveBatch([edited], cursorAssetId: nil)
        #expect(try await pass.run() == .init(listed: 1, seeded: 0))
        #expect(try store.files(copyId: "photos:A1").first?.origin == .backup)
    }

    /// FS-19.07 AC-101: 100 photos never backed up, 10 of them with a file
    /// of the same size on the NAS — exactly those 10 are downloaded, newest
    /// first; the other 90 are never fetched.
    @Test func downloadsOnlySizeCandidates() async throws {
        let (database, pass, downloads) = try Self.library(count: 100)
        try Self.addServerFiles(database, sizes: (0..<10).map { Int64(10_000 + $0 * 7) })

        let summary = try await pass.run()

        #expect(summary.listed == 100)
        #expect(summary.hashed == 10)
        #expect(downloads.ids == (0..<10).map { "P\($0 * 7)" }.reversed())
        #expect(try CopyFileStore(database: database).photosCandidates(triedBefore: .distantFuture, limit: 1_000).isEmpty)
    }

    /// FS-19.07 AC-144 (§12.1): the Mac hashing for every device takes every
    /// file — none has a file of its size on a server here — newest first,
    /// one temporary file at a time, nothing left after. Off, none is taken.
    @Test func macHashesEveryItem() async throws {
        let (database, base, downloads) = try Self.library(count: 4)
        var pass = base
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("OnServer-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }
        pass.workDirectory = work
        #expect(try await pass.run().hashed == 0)
        // Indexed in the opposite order to capture, P3 with no metadata: the
        // last indexed goes first, the one without a row last.
        try await database.writer.write { db in
            for n in 0..<3 { try db.execute(sql: "UPDATE photo_metadata SET indexedAt = ? WHERE assetId = ?", arguments: [2_000 - n, "P\(n)"]) }
            try db.execute(sql: "DELETE FROM photo_metadata WHERE assetId = 'P3'")
        }

        pass.hashesEverything = true
        let summary = try await pass.run(now: Date().addingTimeInterval(1))

        #expect(summary.hashed == 4)
        #expect(downloads.ids == ["P0", "P1", "P2", "P3"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: work.path).isEmpty)
        #expect(try (0..<4).allSatisfy { try CopyFileStore(database: database).files(copyId: "photos:P\($0)").first?.origin == .hashed })
    }

    /// FS-19.07 AC-149 (§12.3): on the very first pass, what another device
    /// hashed is taken right after listing — before the pass picks what to
    /// download — so the first round downloads only the rest.
    @Test func adoptsBeforeDownloading() async throws {
        let (database, base, downloads) = try Self.library(count: 2)
        var pass = base
        pass.hashesEverything = true
        let sha = String(repeating: "c", count: 64)
        pass.adoptListed = { copyIds, now in
            #expect(Set(copyIds) == ["photos:P0", "photos:P1"])
            let filled = try? CopyFileStore(database: database).saveHash(sha, copyId: "photos:P0", fileKey: "1:IMG_0.HEIC",
                                                                       origin: .shared, sharedFrom: "MAC", at: now)
            return filled == true ? 1 : 0
        }

        let summary = try await pass.run()

        #expect(summary.adopted == 1 && summary.hashed == 1)
        #expect(downloads.ids == ["P1"])
    }

    /// FS-19.07 AC-82: three candidates are downloaded one temporary file at
    /// a time; each is gone before the next starts and nothing is left
    /// after. One that cannot be read is recorded and holds up none of the
    /// others.
    @Test func oneTempFileAtATime() async throws {
        let (database, base, downloads) = try Self.library(count: 4)
        var pass = base
        try Self.addServerFiles(database, sizes: [10_000, 10_001, 10_002, 10_003])
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("OnServer-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }
        pass.workDirectory = work
        let most = Counter()
        pass.download = Self.writer(log: downloads) { assetId, _ in
            most.add("\((try? FileManager.default.contentsOfDirectory(atPath: work.path).count) ?? -1)")
            return assetId == "P2" ? nil : Data(repeating: 1, count: 10_000)
        }

        let summary = try await pass.run()

        #expect(summary.hashed == 3)
        #expect(summary.failed == 1)
        #expect(Set(most.ids) == ["0"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: work.path).isEmpty)
        let failed = try #require(try CopyFileStore(database: database).files(copyId: "photos:P2").first)
        #expect(failed.attempts == 1)
        #expect(failed.sha256 == nil)
    }

    /// FS-19.07 AC-83: 2.5 GB free and the next file is 1 GB — the pass
    /// stops before downloading it and says it is waiting for space.
    @Test func waitsForSpace() async throws {
        let (database, base, downloads) = try Self.library(count: 1, size: { _ in 1 << 30 })
        var pass = base
        try Self.addServerFiles(database, sizes: [1 << 30])
        pass.freeBytes = { 5 << 29 }

        let summary = try await pass.run()

        #expect(summary.waitingForSpace)
        #expect(summary.hashed == 0)
        #expect(downloads.ids.isEmpty)
        #expect(try CopyFileStore(database: database).files(copyId: "photos:P0").first?.triedAt == nil)
    }

    /// FS-19.07 AC-81: killed after 10 of 20 downloads, the next pass picks up
    /// at the file it was on — none of the files already hashed is fetched
    /// again.
    @Test func resumesAfterKill() async throws {
        let (database, base, downloads) = try Self.library(count: 20)
        var pass = base
        try Self.addServerFiles(database, sizes: (0..<20).map { Int64(10_000 + $0) })
        var killed = base
        // The 11th download is where iOS stops the app.
        killed.download = { assetId, fileKey, directory in
            if downloads.ids.count == 10 { throw CancellationError() }
            return try await base.download(assetId, fileKey, directory)
        }
        await #expect(throws: CancellationError.self) { try await killed.run() }
        let store = CopyFileStore(database: database)
        let hashed = try (0..<20).filter { try store.files(copyId: "photos:P\($0)").first?.sha256 != nil }.map { "P\($0)" }
        #expect(hashed.count == 10)
        #expect(Set(hashed) == Set(downloads.ids))

        let resumed = Counter()
        pass.download = Self.writer(log: resumed) { _, _ in Data(repeating: 2, count: 64) }
        #expect(try await pass.run().hashed == 20 - hashed.count)
        #expect(Set(resumed.ids).isDisjoint(with: hashed))
        #expect(Set(resumed.ids).union(hashed).count == 20)
    }

    /// `count` indexed photos P0…, P0 the oldest, each with one listed file of
    /// `size(n)` bytes (10,000 + n by default), and a pass whose downloads
    /// are logged.
    private static func library(count: Int, size: @escaping @Sendable (Int) -> Int64 = { Int64(10_000 + $0) })
        throws -> (AppDatabase, PhotosFileHashPass, Counter) {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch(
            (0..<count).map { PhotoMarksStoreTests.record("P\($0)", created: 1_700_000_000 + $0) }, cursorAssetId: nil)
        let downloads = Counter()
        var pass = PhotosFileHashPass(store: CopyFileStore(database: database)) { assetId in
            let n = Int(assetId.dropFirst())!
            return [PhotosFile(fileKey: "1:IMG_\(n).HEIC", role: .photo, size: size(n), stamp: "\(size(n))")]
        }
        pass.download = writer(log: downloads) { _, _ in Data(repeating: 9, count: 32) }
        pass.freeBytes = { nil }
        return (database, pass, downloads)
    }

    /// A server source with one copy per size.
    static func addServerFiles(_ database: AppDatabase, sizes: [Int64]) throws {
        let source = try SourceStore(database: database).addServer(name: "NAS Home", connectionId: "C1")
        try database.writer.write { db in
            for (n, size) in sizes.enumerated() {
                let path = "Shared/s\(n).HEIC"
                try db.execute(sql: """
                    INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey, size)
                    VALUES (?, ?, ?, 'server', ?, ?, ?)
                    """, arguments: ["server-\(n)", "server-\(n)", source, path, path.lowercased(), size])
                try db.execute(sql: "INSERT INTO copy_files (copyId, fileKey, role, size) VALUES (?, 'primary', 'photo', ?)",
                               arguments: ["server-\(n)", size])
            }
        }
    }

    /// A download that logs the asset and writes `data` (nil = fails).
    private static func writer(log: Counter, _ data: @escaping @Sendable (String, String) -> Data?)
        -> @Sendable (String, String, URL) async throws -> URL {
        { assetId, fileKey, directory in
            guard let bytes = data(assetId, fileKey) else {
                log.add(assetId)
                throw PhotosFileHashPass.ListError.missingAsset
            }
            let url = directory.appendingPathComponent(UUID().uuidString)
            try bytes.write(to: url)
            log.add(assetId)
            return url
        }
    }

    /// Files under the app's temporary and caches folders written since
    /// `start`, with their sizes — other tests may write there too, so the
    /// check looks for a file the size of an original.
    private static func filesWritten(since start: Date) -> [String: Int] {
        var out: [String: Int] = [:]
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let roots = [FileManager.default.temporaryDirectory,
                     FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]]
        for root in roots {
            guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys)) else { continue }
            for case let url as URL in walk {
                guard let values = try? url.resourceValues(forKeys: keys),
                      let modified = values.contentModificationDate, modified >= start else { continue }
                out[url.path] = values.fileSize ?? 0
            }
        }
        return out
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var _ids: [String] = []
        var ids: [String] { lock.withLock { _ids } }
        func add(_ id: String) { lock.withLock { _ids.append(id) } }
    }
}
