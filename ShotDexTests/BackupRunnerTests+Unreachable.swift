import Foundation
import Testing
@testable import ShotDex

extension BackupRunnerTests {
    /// AC-14: the server drops during file 5 of 10 — files 1–4 are in the
    /// ledger, file 5 is not and leaves no part file; the run stops as
    /// unreachable; Retry copies 5–10.
    @Test func unreachableThenRetry() async throws {
        let f = try BackupFixture(photos: 10)
        f.client.dropConnectionOnUpload = 5

        let stopped = await f.runner().run()
        #expect(stopped.stop == .blocked(.unreachable))
        #expect(try f.store.handledCount(jobId: f.job.id) == 4)
        #expect(f.partFiles.isEmpty)
        #expect(f.remoteFiles["Backup/iPhone/IMG_4.HEIC"] == nil)

        let retried = await f.runner().run()
        #expect(retried.stop == .finished)
        #expect(retried.progress.total == 6)
        #expect(f.remoteFiles.count == 10)
    }
}
