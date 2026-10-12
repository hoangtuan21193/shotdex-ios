import Foundation
import Testing
@testable import ShotDex

extension BackupRunnerTests {
    /// AC-15: a photo whose iCloud download fails is recorded `failed` and
    /// tried on each of the next runs until 3 attempts; the 4th run skips it
    /// and it is listed as not copied; Retry tries exactly that file again.
    @Test func failedItemRetriedThreeTimesThenListed() async throws {
        let f = try BackupFixture(photos: 3)
        let exporter = FlakyAssetExporter(base: FakeAssetExporter(contents: f.contents), failing: ["A1": 3])

        for run in 1...3 {
            let result = await f.runner(exporter: exporter).run()
            #expect(result.stop == .finished)
            #expect(result.progress.failed == 1, "run \(run)")
        }
        let failed = try f.store.failedEntries(jobId: f.job.id)
        #expect(failed.count == 1)
        #expect(failed.first?.itemKey == "A1")
        #expect(failed.first?.attempts == 3)
        #expect(failed.first?.lastError?.isEmpty == false)

        let exportsBefore = exporter.exportCount
        let fourth = await f.runner(exporter: exporter).run()
        #expect(fourth.progress.total == 0)
        #expect(exporter.exportCount == exportsBefore)

        let retry = await f.runner(exporter: exporter, retriesExhausted: true).run()
        #expect(retry.progress.total == 1)
        #expect(exporter.exportCount == exportsBefore + 1)
        #expect(try f.store.failedEntries(jobId: f.job.id).isEmpty)
        #expect(f.remoteFiles["Backup/iPhone/IMG_1.HEIC"] != nil)
    }
}
