import Foundation
import Observation
import ServiceManagement

/// Who runs Backup on the Mac (FS-22.06 §2: one runner at a time). With Keep
/// Working After Quit on and the helper allowed, the helper runs every job
/// and the app sends it commands and shows what it publishes; otherwise the
/// app runs the jobs itself while it is open.
@MainActor
@Observable
final class MacBackupControl {
    private let coordinator: BackupCoordinator
    private let photoLibrary: PhotoLibraryService
    /// The helper's state as macOS reports it, for Settings and the footer.
    private(set) var agentStatus: SMAppService.Status = .notRegistered
    @ObservationIgnored private var runsLocally = false
    @ObservationIgnored private var hasStarted = false

    init(coordinator: BackupCoordinator, photoLibrary: PhotoLibraryService) {
        self.coordinator = coordinator
        self.photoLibrary = photoLibrary
    }

    /// True when the helper runs the jobs — the footer then says they keep
    /// going after Quit.
    var usesAgent: Bool { !runsLocally && agentStatus == .enabled }

    func appStarted() {
        guard !hasStarted else { return }
        hasStarted = true
        coordinator.reload()
        MacAgentLink.observe(MacAgentLink.agentChanged) { [weak self] in self?.agentChanged() }
        decide()
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
        let hasWork = !coordinator.jobs.isEmpty
        MacAgentLink.ensureAgent(hasWork: hasWork)
        agentStatus = MacAgentLink.service.status
        let local = !(MacAgentLink.keepsWorkingAfterQuit && agentStatus == .enabled)
        guard local != runsLocally || !hasDecided else { return }
        hasDecided = true
        runsLocally = local
        if local {
            coordinator.startWatching(photoLibrary: photoLibrary)
            coordinator.appBecameActive()
        } else {
            coordinator.tickTask?.cancel()
            agentChanged()
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

    /// The helper wrote: read the jobs' states again and show its run.
    private func agentChanged() {
        guard usesAgent else { return }
        coordinator.reload()
        let run = MacAgentLink.currentRun()
        coordinator.showRemoteRun(jobId: run?.jobId, progress: run?.progress, bytesPerSecond: run?.bytesPerSecond)
    }
}
