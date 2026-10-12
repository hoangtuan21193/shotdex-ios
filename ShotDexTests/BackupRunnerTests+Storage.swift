import Foundation
import Testing
@testable import ShotDex

extension BackupRunnerTests {
    /// Never fill the device: each original sits in the work folder only
    /// until it is checked on the server, a killed run's leftovers are
    /// cleared, and a file that would leave under 2 GB free waits.
    @Test func originalsNeverPileUpOnDevice() async throws {
        let f = try BackupFixture(photos: 5)
        try FileManager.default.createDirectory(at: f.workDirectory, withIntermediateDirectories: true)
        try Data(count: 1_000).write(to: f.workDirectory.appendingPathComponent("left-by-killed-run.HEIC"))

        let seen = LockedMax()
        let work = f.workDirectory
        let result = await f.runner(onProgress: { _ in
            let files = (FileManager.default.enumerator(at: work, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []).filter { !$0.hasDirectoryPath }
            seen.record(files.count)
        }).run()

        #expect(result.stop == .finished)
        #expect(seen.max <= 1)
        let left = (FileManager.default.enumerator(at: work, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []).filter { !$0.hasDirectoryPath }
        #expect(left.isEmpty)
    }

    @Test func waitsWhenTheNextFileWouldFillTheDevice() async throws {
        let f = try BackupFixture(photos: 3)
        let low = await f.runner(freeBytes: { BackupRunner.minimumFreeBytes + 1_000 }).run()
        #expect(low.stop == .blocked(.waitingForStorage))
        #expect(f.client.uploadCount == 0)
        let enough = await f.runner(freeBytes: { BackupRunner.minimumFreeBytes * 2 }).run()
        #expect(enough.stop == .finished)
    }
}

final class LockedMax: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var max: Int { lock.withLock { value } }
    func record(_ n: Int) { lock.withLock { value = Swift.max(value, n) } }
}
