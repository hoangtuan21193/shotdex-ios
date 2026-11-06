import BackgroundTasks
import Foundation
import os

/// The on-server check's background time (FS-19.07 §6, phase 2): its own
/// processing task — not Backup's — asked for each time the app leaves the
/// screen with work left. Network always; power only when a Backup job of
/// a server source's connection says Only While Charging. When iOS ends
/// the slot, the pass stops between batches with everything written.
@MainActor
final class OnServerBackgroundService {
    static let identifier = "com.hoangtuan.shotdex.onserver"
    private static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "on-server-background")

    private let check: OnServerCheck
    /// Whether any Backup job of a server source's connection waits for power.
    private let needsPower: @MainActor () -> Bool

    /// Runs at the end of each background pass, inside the same slot — Keep
    /// in Photos catches up with what the pass found (FS-06.12 §4).
    var afterPass: (@MainActor () async -> Void)?

    init(check: OnServerCheck, needsPower: @escaping @MainActor () -> Bool) {
        self.check = check
        self.needsPower = needsPower
    }

    /// Before launch finishes (BGTaskScheduler rule) — see `ShotDexApp.init`.
    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: .main) { task in
            MainActor.assumeIsolated { self.run(task) }
        }
    }

    func appDidEnterBackground() {
        guard check.hasWorkLeft else { return }
        let request = BGProcessingTaskRequest(identifier: Self.identifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = needsPower()
        try? BGTaskScheduler.shared.submit(request)
    }

    private func run(_ task: BGTask) {
        let started = Date()
        let pass = check.startBackground()
        var finished = false
        let finish: @MainActor (Bool) -> Void = { success in
            guard !finished else { return }
            finished = true
            task.setTaskCompleted(success: success)
        }
        var work: Task<Void, Never>?
        task.expirationHandler = {
            Task { @MainActor in
                pass.cancel()
                work?.cancel()
                self.report(started: started, expired: true)
                finish(false)
            }
        }
        // `register(… using: .main)`: the expiration handler and this task run
        // on the main queue after `run` returns, so `work` is set by then.
        work = Task { @MainActor in
            await pass.value
            // Ended by iOS: the expiration handler already reported and finished.
            guard !Task.isCancelled else { return }
            if !finished { await afterPass?() }
            report(started: started, expired: false)
            if check.hasWorkLeft { appDidEnterBackground() }
            finish(true)
        }
    }

    /// One line per slot: how long, how much — the numbers spike S3 reads.
    private func report(started: Date, expired: Bool) {
        let line = String(format: "S3 background slot %.0f s, %@, hashed server %d, photos %d", Date().timeIntervalSince(started),
                          expired ? "ended by iOS" : "finished", check.lastPassHashed.server, check.lastPassHashed.photos)
        Self.logger.notice("\(line, privacy: .public)")
        #if DEBUG
        OnServerSpike.record(line)
        #endif
    }
}
