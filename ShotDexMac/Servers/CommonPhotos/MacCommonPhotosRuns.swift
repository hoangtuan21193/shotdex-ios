import Foundation
import Observation
import os

/// The common-photos runs this Mac carries out (FS-19.08 §6–8): each in a
/// task kept here, its progress published for the run window and Activity
/// (T11) to read. Pause cancels the task — the runner leaves the run paused
/// in the database — and Resume runs it again from there. The Mac stays
/// awake while any runs.
@MainActor
@Observable
final class MacCommonPhotosRuns {
    /// One run as the windows show it.
    struct Entry: Identifiable, Equatable {
        let run: CommonPhotosRun
        var progress = CommonPhotosRunner.Progress()
        var isRunning = false
        /// Why it stopped short or could not start; nil while running or
        /// once finished.
        var problem: String?
        /// Sources of other connections that could not be rescanned after
        /// the run; the run finished regardless (FS-19.08 §6).
        var warnings: [String] = []
        var isFinished = false
        var id: String { run.id }
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

    @ObservationIgnored private let database: AppDatabase
    @ObservationIgnored private let servers: FileServerStore
    @ObservationIgnored private let refresh: ServerSourceRefresh
    @ObservationIgnored private let makeClient: (FileServer) -> any RemoteFileClient
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var activity: NSObjectProtocol?
    private static let log = Logger(subsystem: "com.hoangtuan.shotdex", category: "commonPhotos")

    init(database: AppDatabase, servers: FileServerStore, refresh: ServerSourceRefresh,
         makeClient: @escaping (FileServer) -> any RemoteFileClient) {
        self.database = database
        self.servers = servers
        self.refresh = refresh
        self.makeClient = makeClient
    }

    var store: CommonPhotosStore { CommonPhotosStore(database: database) }

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
        entry.isRunning = true
        entry.problem = nil
        entry.warnings = []
        entries[runId] = entry
        let client = makeClient(server)
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
    }

    @ObservationIgnored private var shownProgress: [String: Int] = [:]

    private func show(_ progress: CommonPhotosRunner.Progress, number: Int, runId: String) {
        guard entries[runId]?.isRunning == true, number > shownProgress[runId, default: 0] else { return }
        shownProgress[runId] = number
        entries[runId]?.progress = progress
    }

    /// Pause: the runner stops between steps and leaves the run paused.
    func pause(runId: String) {
        tasks[runId]?.cancel()
    }

    private func finished(_ runId: String, _ outcome: Result<Void, Error>, cancelled: Bool) {
        tasks[runId] = nil
        shownProgress[runId] = nil
        entries[runId]?.isRunning = false
        switch outcome {
        case .success:
            entries[runId]?.isFinished = true
            try? FileManager.default.removeItem(at: Self.workDirectory(runId))
        case .failure(let error):
            // A run going elsewhere in this app owns the work folder.
            if (error as? CommonPhotosRunner.Stop) == .alreadyRunning { break }
            if cancelled || error is CancellationError {
                entries[runId]?.problem = nil
            } else {
                entries[runId]?.problem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            try? FileManager.default.removeItem(at: Self.workDirectory(runId))
        }
        let state = (try? store.run(id: runId))??.state.rawValue ?? "gone"
        let statuses = ((try? store.items(runId: runId)) ?? []).map(\.status.rawValue)
        let counted = Dictionary(grouping: statuses, by: { $0 }).mapValues(\.count).sorted { $0.key < $1.key }
            .map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        Self.log.notice("common photos run \(runId, privacy: .public) ended: \(state, privacy: .public); items \(counted, privacy: .public); problem \(self.entries[runId]?.problem ?? "none", privacy: .public)")
        if tasks.isEmpty { letSleep() }
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
