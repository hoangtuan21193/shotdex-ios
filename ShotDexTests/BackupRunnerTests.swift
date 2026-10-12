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

    /// AC-8: same name and size at the destination = found, nothing written;
    /// same name, other size = kept beside it as `(2)`; nothing is asked.
    @Test func nameAndSizeMatchIsFoundOtherwiseKeepBoth() async throws {
        var f = try BackupFixture(photos: 0)
        let (three, d3) = BackupFixture.item(3, name: "IMG_3.CR3")
        let (four, d4) = BackupFixture.item(4, name: "IMG_4.CR3")
        f.source.replace([three, four])
        f.contents = d3.merging(d4) { $1 }
        f.client.put("Backup/iPhone/IMG_3.CR3", Data(repeating: 1, count: 4_000))
        f.client.put("Backup/iPhone/IMG_4.CR3", Data(repeating: 2, count: 1_234))
        let uploadsBefore = f.client.uploadCount

        let result = await f.runner().run()

        #expect(result.stop == .finished)
        #expect(f.client.uploadCount == uploadsBefore + 1)
        #expect(f.remoteFiles["Backup/iPhone/IMG_3.CR3"] == Data(repeating: 1, count: 4_000))
        #expect(f.remoteFiles["Backup/iPhone/IMG_4.CR3"] == Data(repeating: 2, count: 1_234))
        #expect(f.remoteFiles["Backup/iPhone/IMG_4 (2).CR3"] == d4.values.first)
        let rows = try await f.database.reader.read { db in try BackupLedgerEntry.order(Column("itemKey")).fetchAll(db) }
        #expect(rows.map(\.outcome) == [.found, .uploaded])
        #expect(rows[0].sha256 == nil)
        #expect(rows[1].remotePath == "Backup/iPhone/IMG_4 (2).CR3")
    }

    /// AC-9: a run of 3,580 files stopped after file 812 resumes at 813 —
    /// the second run writes the remaining 2,768 files, plus at most the one
    /// it was on.
    @Test func resumesAfterKillWithoutRecopy() async throws {
        let f = try BackupFixture(photos: 3_580, bytes: 64)
        let box = BackupTaskBox()
        let runner = f.runner(onProgress: { progress in
            if progress.done == 812 { box.cancel() }
        })
        let first = Task { await runner.run() }
        box.set(first)
        let stopped = await first.value
        #expect(stopped.stop == .cancelled)
        let ledger = try f.store.handledCount(jobId: f.job.id)
        #expect(ledger == 812)

        let uploadsBefore = f.client.uploadCount
        let resumed = await f.runner().run()
        #expect(resumed.stop == .finished)
        #expect(!resumed.progress.isFirstRun)
        #expect(resumed.progress.total == 3_580 - 812)
        #expect((2_768...2_769).contains(f.client.uploadCount - uploadsBefore))
        #expect(f.remoteFiles.count == 3_580)
        #expect(f.partFiles.isEmpty)
    }
}

/// Lets a progress callback cancel the task that is running it.
final class BackupTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<BackupRunResult, Never>?
    private var cancelled = false

    func set(_ task: Task<BackupRunResult, Never>) {
        lock.withLock {
            self.task = task
            if cancelled { task.cancel() }
        }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            task?.cancel()
        }
    }
}
