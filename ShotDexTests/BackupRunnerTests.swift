import Foundation
import GRDB
import Testing
@testable import ShotDex

/// One pass of a backup job (FS-22.02 §1–§2) against an in-memory server.
@Suite @MainActor struct BackupRunnerTests {
    /// AC-7: 10 photos and 2 videos — 12 checked files at the destination,
    /// no part file left, 12 `uploaded` ledger rows with the source's hash.
    @Test func firstRunUploadsAndRecords() async throws {
        let f = try BackupFixture(photos: 10, videos: 2)
        let result = await f.runner().run()

        #expect(result.stop == .finished)
        #expect(result.progress.isFirstRun)
        #expect(result.progress.done == 12)
        #expect(f.remoteFiles.count == 12)
        #expect(f.partFiles.isEmpty)
        for (key, data) in f.contents {
            let name = String(key.split(separator: ":").last!)
            #expect(f.remoteFiles["Backup/iPhone/\(name)"] == data)
        }
        let rows = try await f.database.reader.read { db in try BackupLedgerEntry.fetchAll(db) }
        #expect(rows.count == 12)
        #expect(rows.allSatisfy { $0.outcome == .uploaded })
        for row in rows {
            #expect(row.sha256 == BackupFixture.sha(f.remoteFiles[row.remotePath!]!))
        }
        #expect(try ServerUploadStore(database: f.database).uploadedAssetIds().count == 12)

        // A second pass finds nothing left.
        let again = await f.runner().run()
        #expect(again.progress.total == 0)
        #expect(!again.progress.isFirstRun || again.progress.total == 0)
    }
}
