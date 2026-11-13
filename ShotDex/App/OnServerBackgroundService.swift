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
    static let continuedIdentifier = "com.hoangtuan.shotdex.onserver.continued"
    private static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "on-server-background")

    private let check: OnServerCheck
    /// Whether any Backup job of a server source's connection waits for power.
    private let needsPower: @MainActor () -> Bool

    /// Runs at the end of each background pass, inside the same slot — Keep
    /// in Photos catches up with what the pass found (FS-06.12 §4).
    var afterPass: (@MainActor () async -> Void)?

    /// Checked out of total over every server source, for the system's
    /// progress UI; nil while unknown.
    var fraction: (@MainActor () async -> Double?)?
    /// A continued task is asked for or running now.
    private var hasContinuedTask = false

    init(check: OnServerCheck, needsPower: @escaping @MainActor () -> Bool) {
        self.check = check
        self.needsPower = needsPower
        check.onForegroundPassStart = { [weak self] in self?.passStarted() }
    }

    /// A foreground pass with work left (user 2026-11-11: "it has to check
    /// in the background too"): on iOS 26 it asks to go on after the app
    /// leaves, with the system's own progress UI, as Backup does. Refused
    /// or before iOS 26, the background stops the pass and the processing
    /// slot below takes over when iOS grants one.
    private func passStarted() {
        guard #available(iOS 26.0, *), !hasContinuedTask else { return }
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.continuedIdentifier,
            title: String(localized: "Checking photos on your server", comment: "System progress title for the on-server check"),
            subtitle: String(localized: "Starting…", comment: "System progress subtitle before the on-server check has counts")
        )
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
            hasContinuedTask = true
            check.keepsRunningInBackground = true
            OnServerTrace.log("continued task accepted")
        } catch {
            OnServerTrace.log("continued task refused: \(error.localizedDescription)")
        }
    }

    @available(iOS 26.0, *)
    private func runContinued(_ task: BGContinuedProcessingTask) {
        OnServerTrace.log("continued task running")
        let check = check
        task.expirationHandler = {
            Task { @MainActor in check.stopInBackground() }
        }
        task.progress.totalUnitCount = 1_000
        let updates = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if let fraction = await self?.fraction?() {
                    task.progress.completedUnitCount = Int64(fraction * 1_000)
                    task.updateTitle(task.title, subtitle: String(
                        localized: "\(Int(fraction * 100))% checked", comment: "System progress subtitle for the on-server check"))
                }
                try? await Task.sleep(for: .seconds(15))
            }
        }
        Task { @MainActor in
            await check.waitForPass()
            updates.cancel()
            hasContinuedTask = false
            check.keepsRunningInBackground = false
            OnServerTrace.log("continued task done · work left \(check.hasWorkLeft)")
            task.setTaskCompleted(success: !check.hasWorkLeft)
            if check.hasWorkLeft { appDidEnterBackground() }
        }
    }

    /// Before launch finishes (BGTaskScheduler rule) — see `ShotDexApp.init`.
    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: .main) { task in
            MainActor.assumeIsolated { self.run(task) }
        }
        if #available(iOS 26.0, *) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.continuedIdentifier, using: .main) { task in
                MainActor.assumeIsolated {
                    guard let continued = task as? BGContinuedProcessingTask else {
                        task.setTaskCompleted(success: false)
                        return
                    }
                    self.runContinued(continued)
                }
            }
        }
    }

    func appDidEnterBackground() {
        guard check.hasWorkLeft, !hasContinuedTask else { return }
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
