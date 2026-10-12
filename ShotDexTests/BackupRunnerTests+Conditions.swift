import Foundation
import Testing
@testable import ShotDex

extension BackupRunnerTests {
    /// AC-13: with Only on Wi‑Fi on and the device on cellular, 12 new items
    /// push 0 bytes and the run reports Waiting for Wi‑Fi with 12 left; on
    /// Wi‑Fi the next run copies them.
    @Test func waitsForWiFi() async throws {
        let f = try BackupFixture(photos: 12)
        let network = NetworkSwitch(onWiFi: false)
        let gate: @Sendable () async -> BackupJobState.Status? = { network.onWiFi ? nil : .waitingForWiFi }

        let waiting = await f.runner(gate: gate).run()
        #expect(waiting.stop == .blocked(.waitingForWiFi))
        #expect(waiting.progress.total == 12)
        #expect(waiting.progress.done == 0)
        #expect(f.client.uploadCount == 0)

        network.onWiFi = true
        let copied = await f.runner(gate: gate).run()
        #expect(copied.stop == .finished)
        #expect(f.remoteFiles.count == 12)
    }
}

final class NetworkSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var _onWiFi: Bool
    init(onWiFi: Bool) { _onWiFi = onWiFi }
    var onWiFi: Bool {
        get { lock.withLock { _onWiFi } }
        set { lock.withLock { _onWiFi = newValue } }
    }
}
