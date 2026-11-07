import Foundation
import Observation
import ServiceManagement

/// Who runs Backup and the On Server check on the Mac (FS-22.06 §2,
/// FS-19.07 §11: one runner at a time). With Keep Working After Quit on and
/// the helper allowed, the helper runs every job and every check pass, and
/// the app sends it commands and shows what it publishes; otherwise the app
/// runs both itself while it is open.
@MainActor
@Observable
final class MacBackupControl {
    private let coordinator: BackupCoordinator
    private let photoLibrary: PhotoLibraryService
    private let onServerCheck: OnServerCheck
    private let database: AppDatabase
    /// The helper's state as macOS reports it, for Settings and the footer.
    private(set) var agentStatus: SMAppService.Status = .notRegistered
    @ObservationIgnored private var runsLocally = false
    @ObservationIgnored private var hasStarted = false

    init(coordinator: BackupCoordinator, photoLibrary: PhotoLibraryService, onServerCheck: OnServerCheck, database: AppDatabase) {
        self.coordinator = coordinator
        self.photoLibrary = photoLibrary
        self.onServerCheck = onServerCheck
        self.database = database
    }

    /// True when the helper runs the jobs — the footer then says they keep
    /// going after Quit.
    var usesAgent: Bool { !runsLocally && agentStatus == .enabled }

    func appStarted() {
        guard !hasStarted else { return }
        hasStarted = true
        coordinator.reload()
        MacAgentLink.observe(MacAgentLink.agentChanged) { [weak self] in self?.agentChanged() }
        MacAgentLink.observe(MacAgentLink.onServerChanged) { [weak self] in self?.agentCheckChanged() }
        decide()
        appBecameActive()
    }

    /// The app came forward: the servers are listed again (FS-19.07 §5) —
    /// by the helper when it runs the check, else here.
    func appBecameActive() {
        if usesAgent {
            MacAgentLink.post(.init(action: .checkOnServer))
        } else {
            onServerCheck.appBecameActive()
        }
    }

    /// The app came forward again (user 2026-11-08: the check should not
    /// wait for the next launch or the helper's half hour): a pass starts
    /// unless one runs. Nothing before the window has started the runner.
    func appCameForward() {
        guard hasStarted else { return }
        appBecameActive()
    }

    /// A server source was added or removed: the helper may now have work,
    /// or none.
    func sourcesChanged() {
        decide()
        appBecameActive()
    }

    /// Settings › Keep Working After Quit.
    func setKeepsWorkingAfterQuit(_ on: Bool) {
        MacAgentLink.keepsWorkingAfterQuit = on
        if on {
            decide()
        } else {
            Task {
                try? await MacAgentLink.service.unregister()
                self.decide()
            }
        }
    }

    /// Read the helper's state again — Settings opening, or the app coming
    /// back from System Settings › Login Items.
    func refreshAgentStatus() {
        #if DEBUG
        if let forced = MacDemoLibrary.agentStatus {
            agentStatus = forced
            return
        }
        #endif
        if hasStarted { decide() } else { agentStatus = MacAgentLink.service.status }
    }

    func pause(_ id: String) { send(.pause, id) { $0.pause(id) } }
    func resume(_ id: String) { send(.resume, id) { $0.resume(id) } }
    func backUpNow(_ id: String) { send(.backUpNow, id) { $0.backUpNow(id) } }
    func retry(_ id: String) { send(.retry, id) { $0.retry(id) } }

    /// A job was added, edited or deleted; `start` begins a new one at once.
    func jobsChanged(start: String? = nil) {
        coordinator.reload()
        decide()
        if usesAgent {
            MacAgentLink.post(.init(action: start == nil ? .jobsChanged : .start, jobId: start))
        } else {
            coordinator.jobsChanged(start: start)
        }
    }

    // MARK: -

    /// Picks the runner: register the helper when there is work and the
    /// user wants it; fall back to the app when macOS says no.
    private func decide() {
        let hasWork = !coordinator.jobs.isEmpty || MacAgentLink.hasOnServerWork(database)
            || MacCommonPhotosGatherer.hasWork(database)
        MacAgentLink.ensureAgent(hasWork: hasWork)
        agentStatus = MacAgentLink.service.status
        let local = !(MacAgentLink.keepsWorkingAfterQuit && agentStatus == .enabled)
        guard local != runsLocally || !hasDecided else { return }
        hasDecided = true
        runsLocally = local
        if local {
            coordinator.startWatching(photoLibrary: photoLibrary)
            coordinator.appBecameActive()
            onServerCheck.appBecameActive()
        } else {
            coordinator.tickTask?.cancel()
            // The helper takes the check over; a pass here stops between
            // batches with everything written.
            onServerCheck.appDidEnterBackground()
            agentChanged()
            agentCheckChanged()
        }
    }

    @ObservationIgnored private var hasDecided = false

    private func send(_ action: MacAgentLink.Action, _ id: String, locally: (BackupCoordinator) -> Void) {
        if usesAgent {
            MacAgentLink.post(.init(action: action, jobId: id))
        } else {
            locally(coordinator)
        }
    }

    /// The helper's check moved on: show its waits; the counts come from
    /// the shared database when the screen reads again.
    private func agentCheckChanged() {
        guard usesAgent else { return }
        let state = MacAgentLink.currentOnServer()
        onServerCheck.showRemote(waits: state.waits, photosWait: state.photosWait,
                                 finishedAt: state.finishedAt, isRunning: state.isRunning)
    }

    /// The helper wrote: read the jobs' states again and show its run.
    private func agentChanged() {
        guard usesAgent else { return }
        coordinator.reload()
        let run = MacAgentLink.currentRun()
        coordinator.showRemoteRun(jobId: run?.jobId, progress: run?.progress, bytesPerSecond: run?.bytesPerSecond)
    }
}
