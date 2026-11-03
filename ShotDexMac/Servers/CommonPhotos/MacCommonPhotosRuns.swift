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
        /// Bytes per second over the last half minute, for "about 3 h left".
        var bytesPerSecond: Double?
        var id: String { run.id }

        init(run: CommonPhotosRun) {
            self.run = run
            state = run.state
        }

        var isFinished: Bool { state == .finished }
        var isStopped: Bool { state == .stopped }
        /// Every photo done; the CSV, history and rescan are being written.
        var isFinishing: Bool { state == .finishing }
        /// Over without the user choosing: a lost connection, a quit, a crash.
        var isInterrupted: Bool { !isRunning && !isFinished && !isStopped && !isPausedByUser }

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

    var isAnyRunning: Bool { !tasks.isEmpty }

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
            guard entry.isRunning, let other = try? servers.fetch(id: entry.run.connectionId),
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
        guard let server = (try? servers.fetch(id: run.connectionId)) ?? nil else {
            var entry = entries[runId] ?? Entry(run: run)
            entry.problem = String(localized: "The connection for this run was deleted.", comment: "Common photos: the run's connection is gone")
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
        let runner = CommonPhotosRunner(client: client, store: store, workDirectory: Self.workDirectory(runId),
                                        freeBytes: { Self.freeBytes() }, afterRun: afterRun(runId: runId, server: server))
        keepAwake()
        // Progress hops to the main actor in order: each carries a number,
        // and one older than what is shown — or after the run ended — is dropped.
        let sequence = OSAllocatedUnfairLock(initialState: 0)
        tasks[runId] = Task { [weak self] in
            var outcome: Result<Void, Error>
            do {
                // The runner never connects: it is handed a session.
                try await client.connect()
                try await runner.run(runId) { progress in
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
        tasks[runId]?.cancel()
    }

    /// Quit with runs going: every one paused; `done` once all have stopped.
    func pauseAll(then done: @escaping () -> Void) {
        guard !tasks.isEmpty else { return done() }
        onAllPaused = done
        for runId in tasks.keys { pause(runId: runId) }
    }

    /// Whether Stop may end the run now: never while it is `finishing` (the
    /// store says so before the entry does), never once it is over.
    func canStop(runId: String) -> Bool {
        guard let state = (try? store.run(id: runId))??.state else { return false }
        return state != .finishing && state != .finished && state != .stopped
    }

    /// Stop: what is done stays done, nothing more is copied, and the run
    /// cannot be resumed. Refused while `finishing` — the CSV, the history
    /// and the rescan are owed for what moved.
    func stop(runId: String) {
        guard canStop(runId: runId) else { return }
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
        tasks[runId] == nil && !CommonPhotosRunner.isActive(runId: runId, in: database)
            && ((try? store.run(id: runId))??.state).map { $0 != .finished } ?? false
    }

    /// Discard: the run and its log go; nothing on the server changes.
    @discardableResult
    func discard(runId: String) -> Bool {
        guard canDiscard(runId: runId) else { return false }
        try? store.discard(runId: runId)
        entries[runId] = nil
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

    /// A window closed: a run that is over need not stay in memory.
    func release(runId: String) {
        guard let entry = entries[runId], !entry.isRunning, entry.isFinished || entry.isStopped else { return }
        entries[runId] = nil
        refreshFoot()
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

    /// The foot's run: one going, else the newest interrupted or paused.
    private func refreshFoot() {
        let going = entries.values.filter(\.isRunning).min { $0.run.createdAt < $1.run.createdAt }?.id
        let waiting = going == nil
            ? ((try? store.unfinishedRuns()) ?? []).first { $0.canResume && tasks[$0.id] == nil }?.id
            : nil
        let next = going ?? waiting
        if next != footRunId { footRunId = next }
        generation += 1
        if let next, entries[next] == nil, let run = (try? store.run(id: next)) ?? nil {
            var entry = Entry(run: run)
            entry.progress = Self.progress((try? store.items(runId: next)) ?? [])
            entries[next] = entry
        }
    }

    private func finished(_ runId: String, _ outcome: Result<Void, Error>, cancelled: Bool) {
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
                letSleep()
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
        let servers = servers
        let refresh = refresh
        return { [weak self] run, changes in
            let owner = self
            try ServerFileHistory(database: database).move(changes.map { (from: $0.from, to: $0.to) }, on: server)
            let store = SourceStore(database: database)
            let names = Dictionary(uniqueKeysWithValues: try store.sources().map { ($0.id, $0.name) })
            let sources = try store.serverConnections().compactMap { sourceId, connectionId in
                (try? servers.fetch(id: connectionId)).flatMap { $0 }.map { CommonPhotosSources.Source(sourceId: sourceId, connection: $0) }
            }.sorted { $0.sourceId < $1.sourceId }
            let targets = CommonPhotosSources.toRescan(paths: run.folders + [run.destination], on: server, sources: sources)
            var warnings: [String] = []
            for sourceId in targets {
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
    /// Copy: "120 copied. The other 160 haven't been copied." Move: "120
    /// moved — their other copies were removed. 1 is partway — some of its
    /// copies are still in place. The other 159 haven't been touched."
    static func whatIsDone(_ items: [CommonPhotosItem], run: CommonPhotosRun) -> String {
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
        return run.action == .move
            ? String(localized: "Move to “\(destination)” interrupted at \(done.formatted()) of \(total.formatted())",
                     comment: "Common photos: a Move left half done")
            : String(localized: "Copy to “\(destination)” interrupted at \(done.formatted()) of \(total.formatted())",
                     comment: "Common photos: a Copy left half done")
    }
}
