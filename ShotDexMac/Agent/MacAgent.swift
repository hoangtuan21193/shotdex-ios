import AppKit
import Foundation
import IOKit.ps

/// The helper (FS-22.06 §2): this executable started by launchd with
/// `--agent`. No window, no Dock icon, no menu bar. Runs every Backup job
/// from the shared database, takes the app's commands, publishes the run in
/// flight, keeps the Mac awake while copying, pauses for sleep, and quits
/// once there is no job left.
@MainActor
final class MacAgent {
    private let dependencies: MacDependencies
    private var coordinator: BackupCoordinator { dependencies.backupCoordinator }
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
        guard !coordinator.jobs.isEmpty else { exit(0) }
        MacAgentLink.beat()
        MacAgentLink.observe(MacAgentLink.commandsPosted) { [weak self] in self?.drainCommands() }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.coordinator.systemWillStop() }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.coordinator.appBecameActive() }
        }
        #if DEBUG
        MacAgentProbe.log.notice("agent started; jobs \(self.coordinator.jobs.count); photos \(String(describing: self.dependencies.photoLibrary.authorizationState))")
        #endif
        coordinator.startWatching(photoLibrary: dependencies.photoLibrary)
        coordinator.appBecameActive()
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
            }
        }
        if coordinator.jobs.isEmpty, coordinator.isIdle {
            MacAgentLink.publish(nil)
            exit(0)
        }
        MacAgentLink.publish(lastRun)
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
