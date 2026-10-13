import Foundation
import Observation

/// What the coordinator needs from the outside world, so tests can stand in
/// for the server, the network, the clock and Photos.
struct BackupEnvironment: Sendable {
    /// A runner for one pass of `job` — gated on its Wi‑Fi, charging and
    /// free-space settings; nil when its connection is gone.
    var makeRunner: @MainActor @Sendable (BackupJob, _ retriesExhausted: Bool, _ onProgress: @escaping @Sendable (BackupProgress) -> Void) -> BackupRunner?
    /// Whether Photos changed since `token`, and the token to keep. An
    /// unreadable or expired token reports a change — the run then compares
    /// the whole source with the ledger (FS-22.02 §1).
    var photosChange: @Sendable (Data?) -> (changed: Bool, token: Data?)
    /// How long library changes are gathered before a run (FS-22.02 §1).
    var settle: Duration = .seconds(5)
    /// Monitors of the backup's own whose changes wake waiting jobs; nil in
    /// tests.
    var network: NetworkMonitor?
    var power: PowerMonitor?
}

/// Keeps every backup watching its source (FS-22.02): turns library changes,
/// the app coming forward, the 5-minute tick, network changes and the
/// buttons into runs, one job at a time, and owns each job's status line.
@MainActor @Observable
final class BackupCoordinator {
    private let store: BackupStore
    let environment: BackupEnvironment

    private(set) var jobs: [BackupJob] = []
    private(set) var states: [String: BackupJobState] = [:]
    /// Live numbers of the job running now, and the last numbers of others.
    private(set) var progress: [String: BackupProgress] = [:]
    private(set) var runningJobId: String?
    /// Items backed up per job — the "4,118 items" of the status line.
    private(set) var backedUpItems: [String: Int] = [:]
    /// Bytes per second of the run going now, for "about N min left".
    private(set) var bytesPerSecond: [String: Double] = [:]
    @ObservationIgnored private var runStartedAt: Date?
    /// A run the user started — iOS 26 may let it go on after they leave
    /// (FS-22.02 §3). Set by the background service.
    @ObservationIgnored var onUserStart: ((String) -> Void)?
    /// The job list was read again — the upload extension's config follows it.
    @ObservationIgnored var onJobsReloaded: (([BackupJob]) -> Void)?
    /// Keep Screen On before iOS 26 (FS-22.02 §3); nil in tests.
    @ObservationIgnored var screen: (any ScreenHolding)?
    /// True before iOS 26, where Keep Screen On applies; tests set it.
    @ObservationIgnored var usesKeepScreenOn: Bool = {
        if #available(iOS 26.0, *) { false } else { true }
    }()
    @ObservationIgnored private var isHoldingScreen = false
    /// The 5-minute tick for folder and server sources.
    @ObservationIgnored var tickTask: Task<Void, Never>?

    @ObservationIgnored private var queue: [(id: String, retriesExhausted: Bool)] = []
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var current: Task<BackupRunResult, Never>?
    @ObservationIgnored private var stopReason: BackupJobState.Status?
    @ObservationIgnored private var settling: Task<Void, Never>?

    init(store: BackupStore, environment: BackupEnvironment) {
        self.store = store
        self.environment = environment
        reload()
    }

    func reload() {
        // A job whose FS-19 source was removed goes with it (FS-22.03 §1).
        try? store.removeJobsWithoutSource()
        jobs = (try? store.jobs()) ?? []
        var states: [String: BackupJobState] = [:]
        for job in jobs { states[job.id] = (try? store.state(jobId: job.id)) ?? BackupJobState(jobId: job.id) }
        self.states = states
        var counts: [String: Int] = [:]
        for job in jobs { counts[job.id] = (try? store.handledItemCount(jobId: job.id)) ?? 0 }
        backedUpItems = counts
        onJobsReloaded?(jobs)
    }

    /// The jobs list changed (added, edited, deleted): pick it up and let a
    /// new job start at once.
    func jobsChanged(start jobId: String? = nil) {
        reload()
        if let jobId {
            enqueue([jobId])
            onUserStart?(jobId)
        }
    }

    // MARK: - Triggers

    /// The app came forward or launched: every job compares its source now.
    /// A Photos job whose change token says nothing changed since its last
    /// finished run is skipped. Asking Photos about the token happens off the
    /// main thread — on a busy Photos daemon it blocks, and on the main
    /// thread that froze the app at launch. The returned task ends once the
    /// jobs are queued.
    @discardableResult
    func appBecameActive() -> Task<Void, Never> {
        reload()
        let checks: [(id: String, token: Data?, needsCheck: Bool)] = jobs.map { job in
            guard job.sourceId == PhotoLibrarySource.id, let state = states[job.id], state.status == .watching,
                  state.hasFinishedFirstRun else { return (job.id, nil, false) }
            return (job.id, state.changeToken, true)
        }
        let photosChange = environment.photosChange
        return Task { [weak self] in
            var ids: [String] = []
            for check in checks {
                guard check.needsCheck else { ids.append(check.id); continue }
                let token = check.token
                let changed = await Task.detached(priority: .userInitiated) { photosChange(token).changed }.value
                if changed { ids.append(check.id) }
            }
            self?.enqueue(ids)
        }
    }

    /// Photos reported a change: gather for a few seconds, then run the
    /// Photos jobs.
    func photoLibraryDidChange() {
        settling?.cancel()
        settling = Task { [weak self, settle = environment.settle] in
            try? await Task.sleep(for: settle)
            guard !Task.isCancelled, let self else { return }
            self.enqueue(self.jobs.filter { $0.sourceId == PhotoLibrarySource.id }.map(\.id))
        }
    }

    /// The 5-minute tick and the Backup screen appearing: folder and server
    /// sources have no change events (FS-22.02 §1).
    func sourcesTick() {
        enqueue(jobs.filter { $0.sourceId != PhotoLibrarySource.id }.map(\.id))
    }

    /// Wi‑Fi came back, charging started: jobs waiting on it run.
    func conditionsChanged() {
        enqueue(states.values.filter { [.waitingForWiFi, .waitingToCharge, .waitingForStorage, .unreachable].contains($0.status) }.map(\.jobId))
    }

    /// Back Up Now — compares the whole source even when nothing changed.
    func backUpNow(_ jobId: String) {
        clearPause(jobId)
        enqueue([jobId])
        onUserStart?(jobId)
    }

    /// Retry: also tries files past the attempt limit, and a server that
    /// was out of reach.
    func retry(_ jobId: String) {
        clearPause(jobId)
        enqueue([jobId], retriesExhausted: true)
        onUserStart?(jobId)
    }

    /// Pause: stops the file in flight and stops watching until Resume
    /// (FS-22.02 §4).
    func pause(_ jobId: String) {
        queue.removeAll { $0.id == jobId }
        update(jobId) { $0.status = .pausedByUser }
        if runningJobId == jobId {
            stopReason = .pausedByUser
            current?.cancel()
        }
    }

    func resume(_ jobId: String) {
        clearPause(jobId)
        enqueue([jobId])
        onUserStart?(jobId)
    }

    /// iOS is ending the background time: stop where we are; the job keeps
    /// watching and the next run picks up (FS-22.02 §4).
    func systemWillStop() {
        guard runningJobId != nil else { return }
        stopReason = .pausedBySystem
        current?.cancel()
    }

    /// Settles once the queue is empty — tests and background tasks wait on it.
    func waitUntilIdle() async {
        while let loop { await loop.value }
    }

    var isIdle: Bool { loop == nil }

    // MARK: - Running

    /// Keep Screen On switched while a run goes.
    func keepScreenOnChanged(_ jobId: String, on: Bool) {
        if let index = jobs.firstIndex(where: { $0.id == jobId }) { jobs[index].settings.keepsScreenOn = on }
        if runningJobId == jobId { holdScreen(usesKeepScreenOn && on) }
    }

    private func holdScreen(_ hold: Bool) {
        guard hold != isHoldingScreen else { return }
        isHoldingScreen = hold
        if hold { screen?.beginHold() } else { screen?.endHold() }
    }

    private func clearPause(_ jobId: String) {
        guard let state = states[jobId], state.status == .pausedByUser || state.status == .pausedBySystem else { return }
        update(jobId) { $0.status = .watching }
    }

    private func enqueue(_ ids: [String], retriesExhausted: Bool = false) {
        for id in ids where states[id]?.status != .pausedByUser {
            if let index = queue.firstIndex(where: { $0.id == id }) {
                if retriesExhausted { queue[index].retriesExhausted = true }
            } else if runningJobId != id || retriesExhausted {
                queue.append((id, retriesExhausted))
            }
        }
        guard loop == nil, !queue.isEmpty else { return }
        loop = Task { [weak self] in
            await self?.drain()
            self?.loop = nil
        }
    }

    private func drain() async {
        while !queue.isEmpty {
            let next = queue.removeFirst()
            guard let job = jobs.first(where: { $0.id == next.id }) ?? (try? store.job(id: next.id)) else { continue }
            await run(job, retriesExhausted: next.retriesExhausted)
        }
    }

    private func run(_ job: BackupJob, retriesExhausted: Bool) async {
        let jobId = job.id
        let photosChange = environment.photosChange
        let token = job.sourceId == PhotoLibrarySource.id
            ? await Task.detached(priority: .userInitiated) { photosChange(nil).token }.value
            : nil
        guard let runner = environment.makeRunner(job, retriesExhausted, { [weak self] progress in
            Task { @MainActor in self?.receive(progress, jobId: jobId) }
        }) else {
            update(jobId) { $0.status = .unreachable }
            return
        }
        runningJobId = jobId
        holdScreen(usesKeepScreenOn && job.settings.keepsScreenOn)
        runStartedAt = Date()
        bytesPerSecond[jobId] = nil
        stopReason = nil
        let task = Task { await runner.run() }
        current = task
        let result = await task.value
        current = nil
        runningJobId = nil
        holdScreen(false)
        progress[jobId] = result.progress
        finish(jobId, result: result, token: token)
        backedUpItems[jobId] = (try? store.handledItemCount(jobId: jobId)) ?? backedUpItems[jobId]
    }

    private func receive(_ live: BackupProgress, jobId: String) {
        guard runningJobId == jobId else { return }
        // Hops are not FIFO: never let an older report overwrite a newer one.
        if let shown = progress[jobId], shown.total == live.total,
           (shown.done, shown.bytesDone) > (live.done, live.bytesDone) { return }
        progress[jobId] = live
        if let started = runStartedAt, live.bytesDone > 0 {
            let elapsed = Date().timeIntervalSince(started)
            if elapsed > 5 { bytesPerSecond[jobId] = Double(live.bytesDone) / elapsed }
        }
        if live.total > live.done, states[jobId]?.status != .uploading {
            update(jobId) { $0.status = .uploading }
        }
    }

    private func finish(_ jobId: String, result: BackupRunResult, token: Data?) {
        let now = Int(Date().timeIntervalSince1970)
        update(jobId) { state in
            // The runner wrote it; keep this cached copy from saving it back.
            if let listed = result.treeListedAt { state.lastTreeScanAt = listed }
            state.statusDone = result.progress.done
            state.statusTotal = result.progress.total
            switch result.stop {
            case .finished:
                state.status = .watching
                state.lastCheckedAt = Int(result.listedAt.timeIntervalSince1970)
                state.hasFinishedFirstRun = true
                if let token { state.changeToken = token }
            case .cancelled:
                state.status = stopReason ?? .pausedBySystem
            case .blocked(let status):
                state.status = status
                state.lastCheckedAt = now
            case .sourceUnavailable:
                state.status = .sourceOffline
            }
        }
        stopReason = nil
    }

    private func update(_ jobId: String, _ change: (inout BackupJobState) -> Void) {
        var state = states[jobId] ?? (try? store.state(jobId: jobId)) ?? BackupJobState(jobId: jobId)
        change(&state)
        states[jobId] = state
        try? store.save(state)
    }
}
