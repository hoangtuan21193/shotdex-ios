import Foundation
import Observation
import os

/// The common-photos runs this Mac carries out (FS-19.08 §6–8): each in a
/// task kept here, its progress published for the run window, the sidebar
/// foot and Activity (T11b) to read. Pause cancels the task — the runner
/// leaves the run paused in the database — and Resume runs it again from
/// there; Stop ends it for good. The Mac stays awake while any runs.
@MainActor
@Observable
final class MacCommonPhotosRuns {
    /// One run as the windows show it.
    struct Entry: Identifiable, Equatable {
        /// Read again from the store when the run starts and ends
        /// (`canResume`, `csvPath` change under it).
        var run: CommonPhotosRun
        var progress = CommonPhotosRunner.Progress()
        var isRunning = false
        /// Why it stopped short or could not start; nil while running or
        /// once finished.
        var problem: String?
        /// Sources of other connections that could not be rescanned after
        /// the run; the run finished regardless (FS-19.08 §6).
        var warnings: [String] = []
        /// The run's state in the store, read when it starts, on each photo
        /// done and when it ends.
        var state: CommonPhotosRun.State
        /// Pause was pressed: the run is paused, not interrupted.
        var isPausedByUser = false
        /// Going in the other process (the helper): not interrupted, though
        /// this launch has no task for it (user 2026-11-08).
        var isRunningElsewhere = false
        /// Bytes per second over the last half minute, for "about 3 h left".
        var bytesPerSecond: Double?
        var id: String { run.id }

        init(run: CommonPhotosRun) {
            self.run = run
            state = run.state
        }

        var isFinished: Bool { state == .finished }
        /// Found for a Move set by Keep gathering; waits for Move N….
        var isReady: Bool { state == .ready }
        var isStopped: Bool { state == .stopped }
        /// Every photo done; the CSV, history and rescan are being written.
        var isFinishing: Bool { state == .finishing }
        /// Over without the user choosing: a lost connection, a quit, a crash.
        var isInterrupted: Bool { !isRunning && !isFinished && !isStopped && !isPausedByUser && !isReady }

        /// Photos done (or the one being worked on) of all — the one count the
        /// window, the foot and Activity show.
        var position: Int { min(progress.doneCount + (isRunning && !isFinishing ? 1 : 0), progress.totalCount) }

        /// How far, by bytes, or by photos when the sizes are not known.
        var fraction: Double {
            if progress.totalBytes > 0 { return min(1, Double(progress.doneBytes) / Double(progress.totalBytes)) }
            return progress.totalCount > 0 ? Double(progress.doneCount) / Double(progress.totalCount) : 0
        }

        var secondsLeft: Double? {
            guard isRunning, let bytesPerSecond, bytesPerSecond > 0 else { return nil }
            return Double(max(0, progress.totalBytes - progress.doneBytes)) / bytesPerSecond
        }
    }

    /// A second run that would work on the same files as one going.
    struct Overlaps: Error, LocalizedError {
        var errorDescription: String? {
            String(localized: "Another run is working in these folders on this server. Wait for it to finish, then try again.",
                   comment: "Common photos: a second run over the same folders")
        }
    }

    struct ConnectionGone: Error, LocalizedError {
        var errorDescription: String? {
            String(localized: "The connection for this run was deleted.", comment: "Common photos: the run's connection is gone")
        }
    }

    struct RescanFailed: Error, LocalizedError {
        let sourceName: String
        var errorDescription: String? {
            String(localized: "“\(sourceName)” couldn't be rescanned after the run. Resume tries again.",
                   comment: "Common photos: the rescan after a run did not finish")
        }
    }

    private(set) var entries: [String: Entry] = [:]
    /// The run the sidebar foot shows — going, else interrupted or paused —
    /// changed only when that answer changes, so the Library window does not
    /// redraw on every progress tick.
    private(set) var footRunId: String?
    /// Bumped when a run starts, ends or goes — not on progress — for views
    /// that only care which runs there are.
    private(set) var generation = 0
    /// Show in Browser asked for a folder of a connection; the Library
    /// window opens its source there and clears this.
    var browserRequest: (connectionId: String, path: String)?
    /// Run Again (FS-19.08 §6c) asked for a finished run's set; the Library
    /// window opens its source and the sheet on it, and clears this.
    var runAgainRequest: CommonPhotosRun?

    /// Move N… pressed in Activity: the run's window opens on its question.
    var moveAsked: String?
    /// Keep gathering's notice was clicked: the Library window opens this
    /// run's window, and clears it — only while fresh, so a click with no
    /// Library window open does not pop a window much later.
    var logRequest: (runId: String, at: Date)?

    enum MoveReadyOutcome: Equatable {
        case started
        /// A pass changed the list since the user saw it: ask again.
        case listChanged
        /// It cannot start (no connection, an overlapping run): it stays
        /// ready, and the entry says why.
        case refused
    }

    /// Move N… said yes in the run's window (FS-19.08 §6c): the ready run
    /// becomes a run, started as a resumed one. What would stop it from
    /// starting is checked first, so a refusal leaves it ready.
    @discardableResult
    func moveReady(runId: String, asOf: Int, moving: Set<String>? = nil) -> MoveReadyOutcome {
        guard let run = (try? store.run(id: runId)) ?? nil, run.state == .ready else { return .listChanged }
        var problem: String?
        if let server = (try? servers.fetch(id: run.connectionId)) ?? nil {
            if overlapsARunGoing(run, on: server) { problem = Overlaps().errorDescription }
        } else {
            problem = String(localized: "The connection for this run was deleted.", comment: "Common photos: the run's connection is gone")
        }
        if let problem {
            var entry = entries[runId] ?? Entry(run: run)
            entry.problem = problem
            entries[runId] = entry
            return .refused
        }
        guard (try? store.confirmReady(runId: runId, asOf: asOf, moving: moving)) == true else { return .listChanged }
        resume(runId: runId)
        return .started
    }

    /// How a run Keep gathering started came to an end (FS-19.08 §6c).
    struct RunEnd {
        /// Nil: every photo done.
        var error: (any Error)?
        /// Paused or stopped by the user, or the app quitting.
        var byUser: Bool
        /// Not run here at all: the other process has it. Nothing to report.
        var elsewhere = false
    }

    @ObservationIgnored private var endWaiters: [String: [CheckedContinuation<RunEnd, Never>]] = [:]

    /// Starts (resumes) `runId` and waits for it to end — Keep gathering's
    /// run of the day, or one the server cut off. A run that could not
    /// start says why, as a server-side refusal: the next pass tries again.
    func runToEnd(runId: String) async -> RunEnd {
        if CommonPhotosRunner.isActive(runId: runId, in: database) { return RunEnd(error: nil, byUser: false, elsewhere: true) }
        resume(runId: runId)
        guard tasks[runId] != nil else {
            let problem = entries[runId]?.problem ?? String(localized: "This run could not start.", comment: "Common photos: Keep gathering could not start its run")
            return RunEnd(error: RemoteFileError.other(problem), byUser: false)
        }
        return await withCheckedContinuation { endWaiters[runId, default: []].append($0) }
    }

    /// Another process (the helper, or the app) changed common-photos runs
    /// or sets: what is shown is read again.
    func storeChanged() { refreshFoot() }

    /// Run Again from Activity or a run's window.
    func runAgain(runId: String) {
        guard let run = (try? store.run(id: runId)) ?? nil, !run.isUndo, run.isReadable else { return }
        runAgainRequest = run
    }

    @ObservationIgnored private let database: AppDatabase
    @ObservationIgnored private let servers: FileServerStore
    @ObservationIgnored private let refresh: ServerSourceRefresh
    @ObservationIgnored private let makeClient: (FileServer) -> any RemoteFileClient
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var activity: NSObjectProtocol?
    /// Stop was pressed while the task ran: once it ends, the run is stopped.
    @ObservationIgnored private var stopRequested: Set<String> = []
    /// Runs this launch started, resumed or opened: the banner is for the others.
    @ObservationIgnored private(set) var seenThisLaunch: Set<String> = []
    @ObservationIgnored private var shownProgress: [String: (number: Int, at: ContinuousClock.Instant)] = [:]
    @ObservationIgnored private var rateSamples: [String: [(at: ContinuousClock.Instant, bytes: Int64)]] = [:]
    /// Quit asked while a run goes: answered once every task has paused.
    @ObservationIgnored var onAllPaused: (() -> Void)?
    private static let log = Logger(subsystem: "com.hoangtuan.shotdex", category: "commonPhotos")

    init(database: AppDatabase, servers: FileServerStore, refresh: ServerSourceRefresh,
         makeClient: @escaping (FileServer) -> any RemoteFileClient) {
        self.database = database
        self.servers = servers
        self.refresh = refresh
        self.makeClient = makeClient
        refreshFoot()
    }

    var store: CommonPhotosStore { CommonPhotosStore(database: database) }

    var isAnyRunning: Bool { !tasks.isEmpty || !restoreTasks.isEmpty }

    // MARK: Restore File Info… (FS-19.08 §6e)

    /// One run's Restore File Info…, as its window shows it.
    struct Restore: Equatable {
        var progress = CommonPhotosInfoRestorer.Progress()
        var isRunning = true
        /// Stop was pressed: it ends after the row being worked on.
        var isStopping = false
        /// Stopped by the user before the last row.
        var wasStopped = false
        var problem: String?
    }

    /// By run id; kept after it ends so the window can say what it did.
    private(set) var restores: [String: Restore] = [:]
    @ObservationIgnored private var restoreTasks: [String: Task<Void, Never>] = [:]

    func isRestoring(runId: String) -> Bool { restoreTasks[runId] != nil }

    /// Sets the first folder's dates and flags on the run's copies that do
    /// not have them (`positions`: the selected rows); nothing is copied.
    /// Refused, with the reason shown, while the run, an undo of it or the
    /// helper has it.
    func restoreFileInfo(runId: String, positions: Set<Int>? = nil) {
        guard restoreTasks[runId] == nil, let run = (try? store.run(id: runId)) ?? nil else { return }
        let busy = String(localized: "This run is busy — wait for it, or its undo, to finish, then try again.",
                          comment: "Common photos: Restore File Info refused while the run or its undo goes")
        guard tasks[runId] == nil, ((try? store.undoRuns(of: runId)) ?? []).allSatisfy({ tasks[$0.id] == nil }) else {
            restores[runId] = Restore(isRunning: false, problem: busy)
            return
        }
        guard let server = (try? servers.fetch(id: run.connectionId)) ?? nil else {
            restores[runId] = Restore(isRunning: false, problem: String(localized: "The connection for this run was deleted.",
                                                                        comment: "Common photos: the run's connection is gone"))
            return
        }
        restores[runId] = Restore()
        var client = makeClient(server)
        #if DEBUG
        client = MacDemoLibrary.commonPhotosRunClient(client, forRestore: true)
        #endif
        let restorer = CommonPhotosInfoRestorer(client: client, store: store)
        keepAwake()
        // Progress hops to the main actor in order; an older one is dropped.
        let sequence = OSAllocatedUnfairLock(initialState: 0)
        restoreTasks[runId] = Task { [weak self] in
            var problem: String?
            let last = OSAllocatedUnfairLock(initialState: CommonPhotosInfoRestorer.Progress())
            do {
                try await client.connect()
                try await restorer.run(runId, positions: positions) { progress in
                    let number = sequence.withLock { value in
                        value += 1
                        return value
                    }
                    Task { @MainActor in
                        guard let self, sequence.withLock({ $0 }) == number, self.restoreTasks[runId] != nil else { return }
                        self.restores[runId]?.progress = progress
                    }
                    last.withLock { $0 = progress }
                }
            } catch is CancellationError {
            } catch CommonPhotosInfoRestorer.Refusal.busy {
                problem = busy
            } catch {
                problem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            await client.disconnect()
            let final = last.withLock { $0 }
            let stopped = Task.isCancelled && final.done < final.total
            await MainActor.run {
                guard let self else { return }
                self.restoreTasks[runId] = nil
                self.restores[runId]?.progress = final
                self.restores[runId]?.isRunning = false
                self.restores[runId]?.isStopping = false
                self.restores[runId]?.wasStopped = stopped
                self.restores[runId]?.problem = problem
                if self.tasks.isEmpty, self.restoreTasks.isEmpty { self.letSleep() }
                self.storeChanged()
            }
        }
    }

    /// Stops after the row being worked on; what is done stays done.
    func stopRestore(runId: String) {
        guard let task = restoreTasks[runId] else { return }
        restores[runId]?.isStopping = true
        task.cancel()
    }

    /// A new run from the sheet: refused when a run going on the same
    /// server works in an overlapping folder; written, then started.
    func start(_ run: CommonPhotosRun, items: [CommonPhotosItem]) throws {
        if let server = try servers.fetch(id: run.connectionId), overlapsARunGoing(run, on: server) { throw Overlaps() }
        try store.start(run, items: items)
        entries[run.id] = Entry(run: run)
        resume(runId: run.id)
    }

    private func overlapsARunGoing(_ run: CommonPhotosRun, on server: FileServer) -> Bool {
        let paths = run.folders + [run.destination]
        return entries.values.contains { entry in
            guard entry.isRunning, entry.id != run.id, let other = try? servers.fetch(id: entry.run.connectionId),
                  ServerIdentity.sameFiles(other, server) else { return false }
            let otherPaths = entry.run.folders + [entry.run.destination]
            return paths.contains { path in
                otherPaths.contains { CommonPhotosSelection.contains(path, $0) || CommonPhotosSelection.contains($0, path) }
            }
        }
    }

    func resume(runId: String) {
        guard tasks[runId] == nil else { return }
        seenThisLaunch.insert(runId)
        guard let run = (try? store.run(id: runId)) ?? nil else {
            entries[runId]?.problem = String(localized: "This run is no longer saved.", comment: "Common photos: resume of a discarded run")
            return
        }
        // Ready to move (§6c): only Move N…, which confirms first, starts it.
        guard run.state != .ready else { return }
        // Going in the other process (the helper, or the app): not twice.
        guard !CommonPhotosRunner.isActive(runId: runId, in: database) else {
            var entry = entries[runId] ?? Entry(run: run)
            entry.problem = String(localized: "This run is going in ShotDex’s helper. Wait for it to finish.",
                                   comment: "Common photos: the run is already going in the other process")
            entries[runId] = entry
            return
        }
        guard let server = (try? servers.fetch(id: run.connectionId)) ?? nil else {
            var entry = entries[runId] ?? Entry(run: run)
            entry.problem = String(localized: "The connection for this run was deleted.", comment: "Common photos: the run's connection is gone")
            entries[runId] = entry
            return
        }
        // As at the start: never two runs over the same folders at once.
        if overlapsARunGoing(run, on: server) {
            var entry = entries[runId] ?? Entry(run: run)
            entry.problem = Overlaps().errorDescription
            entries[runId] = entry
            return
        }
        var entry = entries[runId] ?? Entry(run: run)
        entry.run = run
        entry.state = .running
        entry.isRunning = true
        entry.isPausedByUser = false
        entry.problem = nil
        entry.warnings = []
        entry.bytesPerSecond = nil
        entries[runId] = entry
        rateSamples[runId] = []
        var client = makeClient(server)
        #if DEBUG
        client = MacDemoLibrary.commonPhotosRunClient(client)
        #endif
        // An undo run goes through the undoer, a gathering run through the
        // runner; both leave the run paused on a stop.
        let work: @Sendable (@escaping @Sendable (CommonPhotosRunner.Progress) -> Void) async throws -> Void
        if run.isUndo {
            let undoer = CommonPhotosUndoer(client: client, store: store, workDirectory: Self.workDirectory(runId),
                                            freeBytes: { Self.freeBytes() }, afterUndo: afterUndo(runId: runId, server: server))
            work = { try await undoer.run(runId, progress: $0) }
        } else {
            let runner = CommonPhotosRunner(client: client, store: store, workDirectory: Self.workDirectory(runId),
                                            freeBytes: { Self.freeBytes() }, afterRun: afterRun(runId: runId, server: server))
            work = { try await runner.run(runId, progress: $0) }
        }
        keepAwake()
        // Progress hops to the main actor in order: each carries a number,
        // and one older than what is shown — or after the run ended — is dropped.
        let sequence = OSAllocatedUnfairLock(initialState: 0)
        tasks[runId] = Task { [weak self] in
            var outcome: Result<Void, Error>
            do {
                // The runner never connects: it is handed a session.
                try await client.connect()
                try await work { progress in
                    let number = sequence.withLock { value in
                        value += 1
                        return value
                    }
                    Task { @MainActor in self?.show(progress, number: number, runId: runId) }
                }
                outcome = .success(())
            } catch {
                outcome = .failure(error)
            }
            await client.disconnect()
            self?.finished(runId, outcome, cancelled: Task.isCancelled)
        }
        refreshFoot()
    }

    /// Ten updates a second at most; a photo done always lands, and with it
    /// the store's state (`finishing` once the last is).
    private func show(_ progress: CommonPhotosRunner.Progress, number: Int, runId: String) {
        guard var entry = entries[runId], entry.isRunning else { return }
        let now = ContinuousClock.now
        let last = shownProgress[runId]
        guard number > (last?.number ?? 0) else { return }
        let photoDone = progress.doneCount != entry.progress.doneCount
        if let last, !photoDone, now - last.at < .milliseconds(100) { return }
        shownProgress[runId] = (number, now)
        var progress = progress
        // Between two photos the runner clears the name: the last one stays
        // up until the next lands, so the window's detail line does not
        // blink empty after every photo.
        if progress.currentName == nil, progress.doneCount < progress.totalCount {
            progress.currentName = entry.progress.currentName
            progress.currentStep = entry.progress.currentStep
        }
        entry.progress = progress
        var samples = (rateSamples[runId] ?? []).filter { now - $0.at < .seconds(30) }
        samples.append((now, progress.doneBytes))
        rateSamples[runId] = samples
        if let first = samples.first, now - first.at > .seconds(3) {
            let seconds = Double((now - first.at).components.seconds) + Double((now - first.at).components.attoseconds) / 1e18
            entry.bytesPerSecond = Double(progress.doneBytes - first.bytes) / seconds
        }
        if photoDone, let state = (try? store.run(id: runId))??.state { entry.state = state }
        entries[runId] = entry
    }

    /// Pause: the runner stops between steps and leaves the run paused.
    func pause(runId: String) {
        guard tasks[runId] != nil else { return }
        entries[runId]?.isPausedByUser = true
        // Keep gathering no longer carries it on: the user paused it (§6c).
        do { try CommonPhotosWatchStore(database: database).userTookOver(runId: runId) } catch {
            Self.log.error("Keep gathering may carry on a run the user took over: \(error.localizedDescription, privacy: .public)")
        }
        tasks[runId]?.cancel()
    }

    /// Quit with runs going: every one paused; `done` once all have stopped.
    func pauseAll(then done: @escaping () -> Void) {
        // A Restore File Info… stops after its row; what it set stays (§6e).
        for task in restoreTasks.values { task.cancel() }
        guard !tasks.isEmpty else { return done() }
        onAllPaused = done
        // A quit is not the user pausing a run: Keep gathering may carry on.
        for runId in tasks.keys {
            entries[runId]?.isPausedByUser = true
            tasks[runId]?.cancel()
        }
    }

    /// Whether Stop may end the run now: never while it is `finishing` (the
    /// store says so before the entry does), never once it is over.
    func canStop(runId: String) -> Bool {
        guard let state = (try? store.run(id: runId))??.state,
              !CommonPhotosClaims(database: database).isClaimedElsewhere(.run, id: runId) else { return false }
        return state != .finishing && state != .finished && state != .stopped && state != .ready
    }

    /// Stop: what is done stays done, nothing more is copied, and the run
    /// cannot be resumed. Refused while `finishing` — the CSV, the history
    /// and the rescan are owed for what moved.
    func stop(runId: String) {
        guard canStop(runId: runId) else { return }
        do { try CommonPhotosWatchStore(database: database).userTookOver(runId: runId) } catch {
            Self.log.error("Keep gathering may carry on a run the user took over: \(error.localizedDescription, privacy: .public)")
        }
        if let task = tasks[runId] {
            stopRequested.insert(runId)
            task.cancel()
        } else {
            try? store.markState(.stopped, runId: runId)
            entries[runId]?.state = .stopped
            refreshFoot()
        }
    }

    /// Whether Discard may forget the run: not while it runs, here or in
    /// another runner of this process.
    func canDiscard(runId: String) -> Bool {
        guard tasks[runId] == nil, restoreTasks[runId] == nil, !CommonPhotosRunner.isActive(runId: runId, in: database),
              let run = (try? store.run(id: runId)) ?? nil, run.state != .finished, run.state != .ready else { return false }
        // An undo owing its history and rescan finishes on Resume: discarded,
        // the history would keep pointing at the destination (§6b).
        return !(run.isUndo && run.state == .finishing)
    }

    /// Discard: the run and its log go; nothing on the server changes.
    @discardableResult
    func discard(runId: String) -> Bool {
        guard canDiscard(runId: runId) else { return false }
        try? store.discard(runId: runId)
        entries[runId] = nil
        restores[runId] = nil
        refreshFoot()
        return true
    }

    /// The entry for a run, read from the store when this launch has not
    /// seen it — the window opened from the banner or Activity.
    func entry(for runId: String) -> Entry? {
        seenThisLaunch.insert(runId)
        if let entry = entries[runId] { return entry }
        guard let run = (try? store.run(id: runId)) ?? nil else { return nil }
        var entry = Entry(run: run)
        entry.progress = Self.progress((try? store.items(runId: runId)) ?? [])
        entries[runId] = entry
        refreshFoot()
        return entry
    }

    /// Whether Remove from List may forget a run that is over (FS-19.08
    /// §6b): not while it or an undo of it goes.
    func canRemove(runId: String) -> Bool {
        guard tasks[runId] == nil, restoreTasks[runId] == nil, !CommonPhotosRunner.isActive(runId: runId, in: database),
              let run = (try? store.run(id: runId)) ?? nil, run.isOver || run.state == .ready else { return false }
        let undos = run.isUndo ? [] : ((try? store.undoRuns(of: runId)) ?? [])
        return undos.allSatisfy { $0.isOver && tasks[$0.id] == nil }
    }

    /// Remove from List and Remove Finished from List: each run that is over
    /// goes with its log and its undo runs; nothing on the server changes.
    /// Afterwards it can no longer be undone.
    func remove(runIds: [String]) {
        var removed = false
        for runId in runIds where canRemove(runId: runId) {
            // A ready run loses only what it had not moved (§6c).
            if (try? store.run(id: runId))??.state == .ready {
                try? store.dropReady(runId: runId)
                entries[runId] = nil
                restores[runId] = nil
                removed = true
                continue
            }
            let undos = (try? store.undoRuns(of: runId)) ?? []
            try? store.discard(runId: runId)
            entries[runId] = nil
            restores[runId] = nil
            for undo in undos { entries[undo.id] = nil }
            removed = true
        }
        if removed { refreshFoot() }
    }

    /// The runs Activity lists that this launch holds in memory; the store's
    /// unfinished and kept finished runs are added off the main actor.
    var activityKnownRunIds: [String] { Array(entries.keys) }

    /// A window closed: a run that is over need not stay in memory —
    /// Activity lists it from the store.
    func release(runId: String) {
        guard let entry = entries[runId], !entry.isRunning, entry.isFinished || entry.isStopped else { return }
        entries[runId] = nil
        refreshFoot()
    }

    // MARK: Undo (FS-19.08 §6b)

    /// Whether the run's log offers Undo: a run that is over, not itself an
    /// undo, with photos it put in place and no undo of it still to finish.
    func canUndo(runId: String) -> Bool {
        guard tasks[runId] == nil, restoreTasks[runId] == nil, let run = (try? store.run(id: runId)) ?? nil,
              !run.isUndo, run.isOver, run.isReadable else { return false }
        guard ((try? store.undoRuns(of: runId)) ?? []).allSatisfy(\.isOver) else { return false }
        return (try? store.hasUndoableRows(runId: runId)) ?? false
    }

    /// `canUndo`, its three reads off the main actor (hang report 2026-11-08).
    func canUndoAsync(runId: String) async -> Bool {
        guard tasks[runId] == nil, restoreTasks[runId] == nil else { return false }
        let store = self.store
        return await Task.detached(priority: .userInitiated) {
            guard let run = (try? store.run(id: runId)) ?? nil, !run.isUndo, run.isOver, run.isReadable,
                  ((try? store.undoRuns(of: runId)) ?? []).allSatisfy(\.isOver) else { return false }
            return (try? store.hasUndoableRows(runId: runId)) ?? false
        }.value
    }

    /// Undo Copy… / Undo Move… and Undo Selected…: an undo run over the
    /// chosen photos (every one when nil), started at once. Refused like a
    /// new run when one going works in the same folders. Returns its id.
    @discardableResult
    func startUndo(of runId: String, positions: Set<Int>? = nil) throws -> String {
        guard let original = try store.run(id: runId) else { throw CommonPhotosStore.RunMissing(runId: runId) }
        // Nothing written for a connection that is gone: the undo could never run.
        guard let server = try servers.fetch(id: original.connectionId) else { throw ConnectionGone() }
        if overlapsARunGoing(original, on: server) { throw Overlaps() }
        // Restore File Info… writes the same rows: one at a time (§6e).
        if restoreTasks[runId] != nil { throw Overlaps() }
        let undo = try store.startUndo(of: runId, positions: positions)
        entries[undo.id] = Entry(run: undo)
        resume(runId: undo.id)
        return undo.id
    }

    private static func progress(_ items: [CommonPhotosItem]) -> CommonPhotosRunner.Progress {
        CommonPhotosRunner.Progress(doneCount: items.filter(\.isDone).count, totalCount: items.count,
                                    doneBytes: items.filter(\.isDone).reduce(0) { $0 + $1.size },
                                    totalBytes: items.reduce(0) { $0 + $1.size })
    }

    /// Runs a quit or a crash left half done on a connection in an earlier
    /// launch, with how far they got — the browser's banner (FS-19.08 §7).
    func leftOver(connectionId: String) -> [(run: CommonPhotosRun, items: [CommonPhotosItem])] {
        ((try? store.unfinishedRuns()) ?? [])
            .filter { $0.connectionId == connectionId && !seenThisLaunch.contains($0.id) && tasks[$0.id] == nil
                && !CommonPhotosRunner.isActive(runId: $0.id, in: database) }
            .map { ($0, (try? store.items(runId: $0.id)) ?? []) }
    }

    /// Runs left with every photo done — a quit or a pause during Finish —
    /// owe only their log and a rescan: done at launch, with no question
    /// (user 2026-11-08: "Interrupted" came back at every launch). A run
    /// with photos still to move waits for Resume, as before.
    func finishOwedRuns() {
        let store = self.store
        let database = self.database
        Task {
            let owed = await Task.detached(priority: .utility) { () -> [String] in
                ((try? store.unfinishedRuns()) ?? []).filter { run in
                    guard run.canResume, !CommonPhotosRunner.isActive(runId: run.id, in: database) else { return false }
                    if run.state == .finishing { return true }
                    let items = (try? store.items(runId: run.id)) ?? []
                    return !items.isEmpty && items.allSatisfy(\.isDone)
                }.map(\.id)
            }.value
            for id in owed where tasks[id] == nil { resume(runId: id) }
        }
    }

    /// The foot's run: one going, else the newest interrupted or paused.
    private func refreshFoot() {
        let going = entries.values.filter(\.isRunning).min { $0.run.createdAt < $1.run.createdAt }?.id
        let waiting = going == nil
            ? ((try? store.unfinishedRuns()) ?? []).first { $0.canResume && tasks[$0.id] == nil }?.id
            : nil
        let next = going ?? waiting
        if next != footRunId { footRunId = next }
        generation += 1
        // Not going here: what the store says now — the helper may have
        // moved it on or be running it (a stale entry kept "Interrupted").
        if let next, tasks[next] == nil, let run = (try? store.run(id: next)) ?? nil {
            var entry = entries[next] ?? Entry(run: run)
            entry.run = run
            entry.state = run.state
            entry.progress = Self.progress((try? store.items(runId: next)) ?? [])
            entry.isRunningElsewhere = CommonPhotosRunner.isActive(runId: next, in: database)
            entries[next] = entry
        }
    }

    private func finished(_ runId: String, _ outcome: Result<Void, Error>, cancelled: Bool) {
        // Read before the stop below clears what the user asked.
        let byUser = (entries[runId]?.isPausedByUser ?? false) || stopRequested.contains(runId)
        if let waiters = endWaiters.removeValue(forKey: runId) {
            let end: RunEnd
            switch outcome {
            case .success: end = RunEnd(error: nil, byUser: false)
            case .failure(let error): end = RunEnd(error: cancelled && !byUser ? CancellationError() : error, byUser: byUser)
            }
            for waiter in waiters { waiter.resume(returning: end) }
        }
        tasks[runId] = nil
        shownProgress[runId] = nil
        rateSamples[runId] = nil
        entries[runId]?.isRunning = false
        entries[runId]?.bytesPerSecond = nil
        // Stop is permanent, but never while the CSV, history and rescan are
        // owed (`finishing`), and never over a run that finished meanwhile.
        if stopRequested.remove(runId) != nil, let state = (try? store.run(id: runId))??.state,
           state != .finished, state != .finishing {
            try? store.markState(.stopped, runId: runId)
            entries[runId]?.isPausedByUser = false
        }
        defer {
            if let run = (try? store.run(id: runId)) ?? nil {
                entries[runId]?.run = run
                entries[runId]?.state = run.state
                entries[runId]?.progress = Self.progress((try? store.items(runId: runId)) ?? [])
            }
            refreshFoot()
            if tasks.isEmpty {
                if restoreTasks.isEmpty { letSleep() }
                let done = onAllPaused
                onAllPaused = nil
                done?()
            }
        }
        switch outcome {
        case .success:
            try? FileManager.default.removeItem(at: Self.workDirectory(runId))
        case .failure(let error):
            // A run going elsewhere in this app owns the work folder.
            if (error as? CommonPhotosRunner.Stop) == .alreadyRunning { break }
            if cancelled || error is CancellationError {
                entries[runId]?.problem = nil
            } else {
                entries[runId]?.isPausedByUser = false
                entries[runId]?.problem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            try? FileManager.default.removeItem(at: Self.workDirectory(runId))
        }
        let state = (try? store.run(id: runId))??.state.rawValue ?? "gone"
        let statuses = ((try? store.items(runId: runId)) ?? []).map(\.status.rawValue)
        let counted = Dictionary(grouping: statuses, by: { $0 }).mapValues(\.count).sorted { $0.key < $1.key }
            .map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        Self.log.notice("common photos run \(runId, privacy: .public) ended: \(state, privacy: .public); items \(counted, privacy: .public); problem \(self.entries[runId]?.problem ?? "none", privacy: .public)")
    }

    /// After the last photo and the CSV (FS-19.08 §6): the upload, download
    /// and Backup histories follow every copy that moved, in one write; then
    /// every source holding a run folder or the destination, or held by
    /// one, is rescanned — waiting out a pass that began before the moves.
    /// A source of this run's connection that cannot be rescanned throws, so
    /// the run stays `finishing` for Resume; one of another connection only
    /// warns.
    private func afterRun(runId: String, server: FileServer) -> @Sendable (CommonPhotosRun, [CommonPhotosLog.HistoryChange]) async throws -> Void {
        let database = database
        let rescan = rescanAfter(runId: runId, server: server, othersOnly: true)
        let log = Self.log
        return { [weak self] run, changes in
            // Recorded in the same write: an undo puts each row back
            // where it was (FS-19.08 §6b).
            try ServerFileHistory(database: database).move(changes.map { (from: $0.from, to: $0.to) }, on: server) { db, rows in
                try CommonPhotosStore.recordHistoryMoves(db, runId: run.id, rows: rows)
            }
            // The index follows the run's own rows — no rescan of the share
            // (user 2026-11-08: "why rescan WIN?"). What changed there outside
            // ShotDex is found by the next periodic read.
            let items = try CommonPhotosStore(database: database).items(runId: run.id)
            let stamp = Int(Date().timeIntervalSince1970)
            let summary = try await database.writer.write { db in
                try CommonPhotosIndexFollow.apply(db, items: items, connectionId: server.id, folder: server.folder, at: stamp)
            }
            log.notice("common photos: index followed \(summary.moved) moved, \(summary.copied) copied, \(summary.missing) gone")
            await self?.indexFollowed?()
            // Sources of other connections reaching the same files are still read again.
            try await rescan(run)
        }
    }

    /// The index changed without a read: screens showing a source read it again.
    @ObservationIgnored var indexFollowed: (@MainActor () -> Void)?

    /// After an undo's last row and its CSV (FS-19.08 §6b): the history
    /// rows the Move moved go back to each copy written back, then the same
    /// rescan as after a run.
    private func afterUndo(runId: String, server: FileServer) -> @Sendable (CommonPhotosRun, Set<String>) async throws -> Void {
        let database = database
        let rescan = rescanAfter(runId: runId, server: server)
        return { run, restored in
            if let originalId = run.undoOf {
                try CommonPhotosStore(database: database).restoreHistory(runId: originalId, restored: restored,
                                                                         history: ServerFileHistory(database: database))
            }
            try await rescan(run)
        }
    }

    /// Every source holding a run folder or the destination, or held by one,
    /// rescanned — waiting out a pass that began before the changes. A
    /// source of the run's connection that cannot be rescanned throws, so
    /// the run stays `finishing` for Resume; one of another connection only
    /// warns.
    private func rescanAfter(runId: String, server: FileServer, othersOnly: Bool = false) -> @Sendable (CommonPhotosRun) async throws -> Void {
        let database = database
        let servers = servers
        let refresh = refresh
        return { [weak self] run in
            let owner = self
            let store = SourceStore(database: database)
            let names = Dictionary(uniqueKeysWithValues: try store.sources().map { ($0.id, $0.name) })
            let sources = try store.serverConnections().compactMap { sourceId, connectionId in
                (try? servers.fetch(id: connectionId)).flatMap { $0 }.map { CommonPhotosSources.Source(sourceId: sourceId, connection: $0) }
            }.sorted { $0.sourceId < $1.sourceId }
            let targets = CommonPhotosSources.toRescan(paths: run.folders + [run.destination], on: server, sources: sources)
            var warnings: [String] = []
            // After a run, the run's own connection is followed from its rows.
            for sourceId in targets where !othersOnly || sources.first(where: { $0.sourceId == sourceId })?.connection.id != server.id {
                let summary = await refresh.rescan(sourceId: sourceId, fresh: true)
                try Task.checkCancellation()
                let ownConnection = sources.first { $0.sourceId == sourceId }?.connection.id == server.id
                let name = names[sourceId] ?? sourceId
                let failure: Error? = if let stop = summary?.stoppedBy { stop }
                    else if summary?.disconnected == true { RemoteFileError.connectionLost }
                    else if summary == nil { RescanFailed(sourceName: name) }
                    else { nil }
                guard let failure else { continue }
                if ownConnection { throw failure }
                warnings.append(String(localized: "“\(name)” wasn't rescanned; it updates the next time it's rescanned.",
                                       comment: "Common photos: another connection's source could not be rescanned after a run"))
            }
            if !warnings.isEmpty {
                let found = warnings
                await owner?.setWarnings(found, runId: runId)
            }
        }
    }

    private func setWarnings(_ warnings: [String], runId: String) {
        entries[runId]?.warnings = warnings
    }

    // MARK: This Mac

    /// One photo at a time sits here between download and upload; the app's
    /// caches, never the user's folders.
    private static func workDirectory(_ runId: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CommonPhotos", isDirectory: true)
            .appendingPathComponent(runId, isDirectory: true)
    }

    nonisolated private static func freeBytes() -> Int64? {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return (try? caches.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }

    private func keepAwake() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                         reason: "Copying common photos on a server")
    }

    private func letSleep() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }
}

/// What a common-photos run has done, in the words every surface uses
/// (FS-19.08 §7): the window, the Stop question, Discard, the banner.
enum MacCommonPhotosWords {
    /// The Move question's message (§4, §6b), in the sheet and on a ready run.
    static func moveMessage(folders: [String], destination: String) -> String {
        let names = folders.map { ServerUploadPath.lastComponent(of: $0) }.formatted(.list(type: .and))
        return String(localized: "Each photo is copied to “\(destination)” and verified, then removed from \(names). The server has no Trash; you can undo the run from Activity.",
                      comment: "Mac common photos: Move confirmation message")
    }

    /// Copy: "120 copied. The other 160 haven't been copied." Move: "120
    /// moved — their other copies were removed. 1 is partway — some of its
    /// copies are still in place. The other 159 haven't been touched."
    static func whatIsDone(_ items: [CommonPhotosItem], run: CommonPhotosRun) -> String {
        if run.isUndo {
            // "120 taken back. The other 158 haven't been touched."
            let undone = items.filter { $0.status == .undone }.count
            let untouched = items.filter { !$0.isDone }.count
            return String(localized: "\(undone.formatted()) taken back.", comment: "Common photos: what an undo has done so far") + " "
                + (untouched == 1
                   ? String(localized: "The other one hasn't been touched.", comment: "Common photos: undo, one photo not reached")
                   : String(localized: "The other \(untouched.formatted()) haven't been touched.", comment: "Common photos: undo, photos not reached"))
        }
        let moved = items.filter { $0.status == .moved }.count
        let copied = items.filter { $0.status == .copied }.count
        // Renamed into the destination, or being: its other copies are not
        // all removed yet. Resume checks it and finishes it.
        let partway = items.filter { $0.status == .placed || $0.status == .moving }.count
        let untouched = items.filter { $0.status == .pending || ($0.status == .copying && run.action == .copy) }.count
        guard run.action == .move else {
            return String(localized: "\(copied.formatted()) copied.", comment: "Common photos: what a Copy run has done so far") + " "
                + (untouched == 1
                   ? String(localized: "The other one hasn't been copied.", comment: "Common photos: Copy run, one photo not reached")
                   : String(localized: "The other \(untouched.formatted()) haven't been copied.", comment: "Common photos: Copy run, photos not reached"))
        }
        var parts = [String(localized: "\(moved.formatted()) moved — their other copies were removed.",
                            comment: "Common photos: what a Move run has done so far")]
        if partway > 0 {
            parts.append(partway == 1
                         ? String(localized: "1 is partway — some of its copies are still in place.",
                                  comment: "Common photos: Move run, one photo moved but its other copies not all removed")
                         : String(localized: "\(partway.formatted()) are partway — some of their copies are still in place.",
                                  comment: "Common photos: Move run, photos moved but their other copies not all removed"))
        }
        if untouched > 0 {
            parts.append(untouched == 1
                         ? String(localized: "The other one hasn't been touched.", comment: "Common photos: Move run, one photo not reached")
                         : String(localized: "The other \(untouched.formatted()) haven't been touched.", comment: "Common photos: Move run, photos not reached"))
        }
        return parts.joined(separator: " ")
    }

    /// "Move to “Shared” interrupted at 120 of 280".
    static func interrupted(_ run: CommonPhotosRun, done: Int, total: Int) -> String {
        let destination = ServerUploadPath.lastComponent(of: run.destination)
        if run.isUndo {
            return String(localized: "Undo of common photos in “\(destination)” stopped at \(done.formatted()) of \(total.formatted())",
                          comment: "Common photos: an undo left half done")
        }
        return run.action == .move
            ? String(localized: "Move to “\(destination)” interrupted at \(done.formatted()) of \(total.formatted())",
                     comment: "Common photos: a Move left half done")
            : String(localized: "Copy to “\(destination)” interrupted at \(done.formatted()) of \(total.formatted())",
                     comment: "Common photos: a Copy left half done")
    }
}
