import AppKit
import Foundation
import IOKit.ps

/// The helper (FS-22.06 §2): this executable started by launchd with
/// `--agent`. No window, no Dock icon, no menu bar. Runs every Backup job
/// from the shared database, takes the app's commands, publishes the run in
/// flight, keeps the Mac awake while copying, pauses for sleep, and quits
/// once there is no job left. It also runs the On Server check (FS-19.07
/// §11): at start, when the app comes forward, after wake, and every 30
/// minutes — the Mac has no "came forward" while the app is quit.
@MainActor
final class MacAgent {
    private let dependencies: MacDependencies
    private var coordinator: BackupCoordinator { dependencies.backupCoordinator }
    private var check: OnServerCheck { dependencies.onServerCheck }
    private var lastOnServer = MacAgentLink.OnServerState()
    private var relist: Timer?
    /// The app came forward while a pass ran: list again once it ends, so a
    /// server that just came back is not left waiting 30 minutes.
    private var relistsAfterPass = false
    /// FS-19.07 §11: how often the helper lists the servers again.
    static let relistInterval: TimeInterval = 30 * 60
    private var awake: NSObjectProtocol?
    private var lastRun: MacAgentLink.Run?
    private var tick: Timer?

    private init() {
        dependencies = MacDependencies.live()
    }

    static func run() -> Never {
        MainActor.assumeIsolated {
            let agent = MacAgent()
            agent.start()
            // Kept alive by the main run loop below.
            objc_setAssociatedObject(NSApplication.shared, &MacAgent.key, agent, .OBJC_ASSOCIATION_RETAIN)
        }
        RunLoop.main.run()
        exit(0)
    }

    private static var key = 0

    private func start() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        coordinator.reload()
        guard hasWork else { exit(0) }
        MacAgentLink.beat()
        MacAgentLink.observe(MacAgentLink.commandsPosted) { [weak self] in self?.drainCommands() }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.coordinator.systemWillStop()
                self?.check.appDidEnterBackground()
            }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                _ = self?.coordinator.appBecameActive()
                self?.check.appBecameActive()
            }
        }
        #if DEBUG
        MacAgentProbe.log.notice("agent started; jobs \(self.coordinator.jobs.count); photos \(String(describing: self.dependencies.photoLibrary.authorizationState))")
        #endif
        coordinator.startWatching(photoLibrary: dependencies.photoLibrary)
        coordinator.appBecameActive()
        check.onBatch = { [weak self] in self?.publishOnServer() }
        check.appBecameActive()
        relist = Timer.scheduledTimer(withTimeInterval: Self.relistInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkOnServer() }
        }
        drainCommands()
        tick = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.publish() }
        }
    }

    private func drainCommands() {
        for command in MacAgentLink.takeCommands() {
            switch command.action {
            case .pause: command.jobId.map(coordinator.pause)
            case .resume: command.jobId.map(coordinator.resume)
            case .backUpNow: command.jobId.map(coordinator.backUpNow)
            case .retry: command.jobId.map(coordinator.retry)
            case .jobsChanged: coordinator.jobsChanged()
            case .start: coordinator.jobsChanged(start: command.jobId)
            case .checkOnServer: checkOnServer()
            }
        }
        quitIfIdle()
        MacAgentLink.publish(lastRun)
    }

    private func checkOnServer() {
        guard MacAgentLink.hasOnServerWork(dependencies.database) else {
            // The last server source went: stop between batches.
            check.appDidEnterBackground()
            return
        }
        if check.isRunning { relistsAfterPass = true } else { check.appBecameActive() }
    }

    /// Backup jobs, or a server source for the On Server check.
    private var hasWork: Bool {
        !coordinator.jobs.isEmpty || MacAgentLink.hasOnServerWork(dependencies.database)
    }

    private func quitIfIdle() {
        if coordinator.jobs.isEmpty, coordinator.isIdle, !check.isRunning, !hasWork {
            MacAgentLink.publish(nil)
            exit(0)
        }
    }

    #if DEBUG
    private var lastProgressLog = Date.distantPast

    /// At most every 30 s while a pass runs: how far the check has got.
    private func logCheckProgress() {
        guard check.isRunning, Date().timeIntervalSince(lastProgressLog) >= 30 else { return }
        lastProgressLog = Date()
        let queries = OnServerProgressQueries(database: dependencies.database)
        let sources = (try? SourceStore(database: dependencies.database).serverConnections().keys.sorted()) ?? []
        let counts = sources.compactMap { try? queries.progress(sourceId: $0, folder: nil) }.map { "\($0.checked)/\($0.total)" }
        MacAgentProbe.log.notice("agent on server pass: checked \(counts.joined(separator: ", "), privacy: .public)")
    }
    #endif

    /// The check's waits and finish time, for the app's progress line.
    private func publishOnServer() {
        let state = MacAgentLink.OnServerState(waits: check.waits, photosWait: check.photosWait,
                                               finishedAt: check.finishedAt, isRunning: check.isRunning)
        guard state != lastOnServer else { return }
        lastOnServer = state
        MacAgentLink.publish(state)
        #if DEBUG
        MacAgentProbe.log.notice("agent on server: running \(state.isRunning), waits \(String(describing: state.waits), privacy: .public), photos \(String(describing: state.photosWait), privacy: .public), finished \(String(describing: state.finishedAt), privacy: .public)")
        #endif
    }

    /// Twice a second: the heartbeat, the run in flight when it changed, and
    /// the awake assertion while a job runs (FS-22.06 §4).
    private func publish() {
        MacAgentLink.beat()
        let run = coordinator.runningJobId.map { id in
            MacAgentLink.Run(jobId: id, progress: coordinator.progress[id] ?? BackupProgress(),
                             bytesPerSecond: coordinator.bytesPerSecond[id])
        }
        if run != lastRun {
            lastRun = run
            MacAgentLink.publish(run)
        }
        holdAwake(run != nil && MacKeepAwake.current.applies)
        // A pass's end bumps no batch; catch isRunning going false here.
        publishOnServer()
        if relistsAfterPass, !check.isRunning {
            relistsAfterPass = false
            check.appBecameActive()
        }
        #if DEBUG
        logCheckProgress()
        #endif
        quitIfIdle()
    }

    private func holdAwake(_ hold: Bool) {
        if hold, awake == nil {
            awake = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                          reason: "Backing up photos to a server")
        } else if !hold, let activity = awake {
            ProcessInfo.processInfo.endActivity(activity)
            awake = nil
        }
    }
}

/// Keep Mac Awake While Copying (FS-22.06 §5.4): Never · On Power Adapter
/// (default) · Always.
enum MacKeepAwake: String, CaseIterable {
    case never, onPowerAdapter, always

    private static let key = "keepMacAwakeWhileCopying"

    static var current: MacKeepAwake {
        get { MacAgentLink.defaults.string(forKey: key).flatMap(MacKeepAwake.init(rawValue:)) ?? .onPowerAdapter }
        set { MacAgentLink.defaults.set(newValue.rawValue, forKey: key) }
    }

    /// On the adapter — or a desktop, which has no battery at all.
    static var isOnPowerAdapter: Bool {
        let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let source = info.flatMap { IOPSGetProvidingPowerSourceType($0)?.takeUnretainedValue() as String? }
        return source != kIOPSBatteryPowerValue
    }

    var applies: Bool {
        switch self {
        case .never: false
        case .always: true
        case .onPowerAdapter: Self.isOnPowerAdapter
        }
    }
}
