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
}
