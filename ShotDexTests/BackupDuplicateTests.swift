import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-22.05: a photo whose bytes are already somewhere in the destination
/// folder is not copied again, whoever put them there.
@Suite @MainActor struct BackupDuplicateTests {
    /// AC-37: two photos with identical bytes (a Duplicate in Photos) and an
    /// empty destination — one file goes up, the other is a `duplicate`
    /// pointing at it.
    @Test func identicalItemsInOneLibraryCopyOnce() async throws {
        var f = try BackupFixture(photos: 0)
        let (first, d1) = BackupFixture.item(0, name: "IMG_0.HEIC", seed: 5)
        let (second, d2) = BackupFixture.item(1, name: "IMG_1.HEIC", seed: 5)
        f.source.replace([first, second])
        f.contents = d1.merging(d2) { $1 }

        let result = await f.runner().run()

        #expect(result.stop == .finished)
        #expect(result.progress.done == 2)
        #expect(f.client.uploadCount == 1)
        #expect(Array(f.remoteFiles.keys) == ["Backup/iPhone/IMG_0.HEIC"])
        let rows = try await f.database.reader.read { db in try BackupLedgerEntry.order(Column("itemKey")).fetchAll(db) }
        #expect(rows.map(\.outcome) == [.uploaded, .duplicate])
        #expect(rows[1].remotePath == "Backup/iPhone/IMG_0.HEIC")
        #expect(rows[1].localName == "IMG_1.HEIC")
        #expect(rows[1].sha256 == rows[0].sha256)
        #expect(try f.store.handledItemCount(jobId: f.job.id) == 2)
        #expect(try f.store.duplicateCount(jobId: f.job.id) == 1)
        // Both photos show as on the server, both pointing at the one file.
        let uploads = try await f.database.reader.read { db in try ServerUploadRecord.fetchAll(db) }
        #expect(Set(uploads.map(\.assetId)) == ["A0", "A1"])
        #expect(Set(uploads.map(\.remotePath)) == ["Backup/iPhone/IMG_0.HEIC"])

        // Nothing is left for the next run.
        #expect(await f.runner().run().progress.total == 0)
    }

    /// AC-35: what this device knew says `a/IMG_1.HEIC` holds these bytes,
    /// but someone deleted it on the NAS — the photo goes up again and the
    /// stale row is forgotten.
    @Test func deletedOnNASIsSentAgain() async throws {
        let f = try BackupFixture(photos: 1)
        let bytes = try #require(f.contents.values.first)
        try f.store.saveDestinationFile(BackupDestinationFile(
            jobId: f.job.id, path: "a/IMG_1.HEIC", size: Int64(bytes.count), sha256: BackupFixture.sha(bytes), origin: .index
        ))

        let result = await f.runner().run()

        #expect(result.stop == .finished)
        #expect(f.client.uploadCount == 1)
        #expect(f.remoteFiles["Backup/iPhone/IMG_0.HEIC"] == bytes)
        let row = try #require(try f.store.handledEntries(jobId: f.job.id).first)
        #expect(row.outcome == .uploaded)
        #expect(try f.store.destinationFiles(jobId: f.job.id, sha256: BackupFixture.sha(bytes)).map(\.path) == ["IMG_0.HEIC"])
    }

    /// AC-34: the folder already holds 8,000 files ShotDex did not write; 3
    /// have the size of a photo about to go up (2 with its bytes, 1 not).
    /// The tree is listed — `Checking NAS Home · 8,000 files` — before the
    /// first copy; only those 3 are read; 2 photos are `duplicate`, 1 goes up.
    @Test func existingFilesCheckedBySizeFirst() async throws {
        var f = try BackupFixture(photos: 0)
        var items: [BackupSourceItem] = []
        var contents: [String: Data] = [:]
        for n in 0..<3 {
            let (item, data) = BackupFixture.item(n, name: "IMG_\(n).HEIC", bytes: 4_000 + n)
            items.append(item)
            contents.merge(data) { $1 }
        }
        f.source.replace(items)
        f.contents = contents
        // 7,997 files of other sizes, 100 to a folder.
        for n in 0..<7_997 {
            f.client.put("Backup/iPhone/Old/\(n / 100)/DSC_\(n).JPG", Data(repeating: 7, count: 100 + n % 50))
        }
        let photo0 = try #require(contents[FakeAssetExporter.key("A0", "1:IMG_0.HEIC")])
        let photo1 = try #require(contents[FakeAssetExporter.key("A1", "1:IMG_1.HEIC")])
        f.client.put("Backup/iPhone/Trip/P1000.HEIC", photo0)
        f.client.put("Backup/iPhone/Trip/2019/P1001.HEIC", photo1)
        f.client.put("Backup/iPhone/Trip/P1002.HEIC", Data(repeating: 9, count: 4_002))

        let events = Events()
        let result = await f.runner(onProgress: { events.append($0) }).run()

        #expect(result.stop == .finished)
        #expect(result.treeListedAt != nil)
        let checking = events.all.filter { $0.phase == .checkingDestination }
        #expect(checking.last?.listedCount == 8_000)
        let firstUpload = try #require(events.all.firstIndex { $0.phase == .uploading })
        let lastChecking = try #require(events.all.lastIndex { $0.phase == .checkingDestination })
        #expect(lastChecking < firstUpload)

        let readOnNAS = f.client.sha256Paths.filter { !$0.hasSuffix(ServerUploadPath.partSuffix) }
        #expect(Set(readOnNAS) == ["Backup/iPhone/Trip/P1000.HEIC", "Backup/iPhone/Trip/2019/P1001.HEIC", "Backup/iPhone/Trip/P1002.HEIC"])
        #expect(readOnNAS.count == 3)
        let rows = try await f.database.reader.read { db in try BackupLedgerEntry.order(Column("itemKey")).fetchAll(db) }
        #expect(rows.map(\.outcome) == [.duplicate, .duplicate, .uploaded])
        #expect(rows[0].remotePath == "Backup/iPhone/Trip/P1000.HEIC")
        #expect(rows[1].remotePath == "Backup/iPhone/Trip/2019/P1001.HEIC")
        #expect(f.client.uploadCount == 1)
    }

    /// AC-33: `X.HEIC` at the destination is 3,145,728 bytes, as are two
    /// photos with other contents. Both go up; `X.HEIC` is read to hash it
    /// exactly once — the second photo and the next run use the kept hash,
    /// which waits to be written to the shared index.
    @Test func sameSizeDifferentContentIsHashedOnce() async throws {
        var f = try BackupFixture(photos: 0)
        let size = 3_145_728
        let (a, da) = BackupFixture.item(0, name: "IMG_0.HEIC", bytes: size)
        let (b, db) = BackupFixture.item(1, name: "IMG_1.HEIC", bytes: size)
        f.source.replace([a, b])
        f.contents = da.merging(db) { $1 }
        let x = Data(repeating: 0xAB, count: size)
        f.client.put("Backup/iPhone/X.HEIC", x)

        let result = await f.runner().run()

        #expect(result.stop == .finished)
        #expect(f.client.uploadCount == 2)
        #expect(f.client.sha256Paths.filter { $0 == "Backup/iPhone/X.HEIC" }.count == 1)
        let known = try f.store.destinationFiles(jobId: f.job.id, sha256: BackupFixture.sha(x))
        #expect(known.map(\.path) == ["X.HEIC"])
        #expect(known.first?.needsPublish == true)

        let (c, dc) = BackupFixture.item(2, name: "IMG_2.HEIC", bytes: size)
        f.source.add([c])
        f.contents.merge(dc) { $1 }
        _ = await f.runner().run()
        #expect(f.client.sha256Paths.filter { $0 == "Backup/iPhone/X.HEIC" }.count == 1)
    }

    /// FS-22.05 §3: the tree is listed again only once it is a day old — a
    /// file someone adds by hand is seen by the next daily check.
    @Test func scanRepeatsAfterADay() async throws {
        let f = try BackupFixture(photos: 1)
        _ = await f.runner().run()
        #expect(try f.store.destinationFileCount(jobId: f.job.id) == 1)

        f.client.put("Backup/iPhone/Hand/IMG_X.JPG", Data(repeating: 3, count: 50))
        let (second, _) = BackupFixture.item(1, name: "IMG_1.HEIC")
        f.source.add([second])
        var f2 = f
        f2.contents.merge(BackupFixture.item(1, name: "IMG_1.HEIC").1) { $1 }
        let soon = await f2.runner().run()
        #expect(soon.treeListedAt == nil)
        #expect(try f.store.destinationFileCount(jobId: f.job.id) == 2)

        var state = try f.store.state(jobId: f.job.id)
        state.lastTreeScanAt = Int(Date().timeIntervalSince1970) - 25 * 60 * 60
        try f.store.save(state)
        let (third, d3) = BackupFixture.item(2, name: "IMG_2.HEIC")
        f.source.add([third])
        f2.contents.merge(d3) { $1 }
        let later = await f2.runner().run()
        #expect(later.treeListedAt != nil)
        #expect(try f.store.destinationFileCount(jobId: f.job.id) == 4)
    }
}

/// Progress reports in the order the runner sent them.
private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [BackupProgress] = []
    var all: [BackupProgress] { lock.withLock { stored } }
    func append(_ progress: BackupProgress) { lock.withLock { stored.append(progress) } }
}
