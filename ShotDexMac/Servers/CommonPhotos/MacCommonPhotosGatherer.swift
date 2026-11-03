import Foundation
import Network
import os

/// Keep gathering on the Mac (FS-19.08 §6c): every 15 minutes, each set
/// that is on gets one pass — the helper's job, or the app's while the
/// helper is not running jobs. A Copy set's photos are copied at once, a
/// Move set's wait to be moved, and a run the server cut off goes on.
///
/// The app and the helper share the database: a set's pass is claimed
/// there (`CommonPhotosClaims`), so only one process looks at a set at a
/// time, and the run it starts is claimed the same way by its runner.
/// One pass at a time here; a set asked twice is gathered once.
@MainActor
final class MacCommonPhotosGatherer {
    /// FS-19.08 §6c, user 2026-11-03.
    static let interval: TimeInterval = 15 * 60
    private static let log = Logger(subsystem: "com.hoangtuan.shotdex", category: "commonPhotos")

    private let database: AppDatabase
    private let servers: FileServerStore
    private let runs: MacCommonPhotosRuns
    private let makeClient: (FileServer) -> any RemoteFileClient
    /// Whether this process gathers now: the app asks the helper first.
    var isOn: () -> Bool = { true }
    /// A pass or its run changed what Activity shows.
    var onChange: () -> Void = {}

    private var timer: Timer?
    private var queue: [String] = []
    private(set) var isBusy = false
    private let path = NWPathMonitor()
    private var isExpensivePath = false
    /// No pass before the network is known: a metered one must not pass
    /// for Wi‑Fi in the first second.
    private var knowsPath = false
    private var gathersOncePathKnown = false

    init(database: AppDatabase, servers: FileServerStore, runs: MacCommonPhotosRuns,
         makeClient: @escaping (FileServer) -> any RemoteFileClient) {
        self.database = database
        self.servers = servers
        self.runs = runs
        self.makeClient = makeClient
        path.pathUpdateHandler = { [weak self] path in
            let expensive = path.isExpensive || path.isConstrained
            Task { @MainActor in
                guard let self else { return }
                self.isExpensivePath = expensive
                self.knowsPath = true
                if self.gathersOncePathKnown {
                    self.gathersOncePathKnown = false
                    self.gatherAll()
                }
            }
        }
        path.start(queue: .main)
    }

    private var watches: CommonPhotosWatchStore { CommonPhotosWatchStore(database: database) }

    /// A set is on: the helper's reason to keep running.
    static func hasWork(_ database: AppDatabase) -> Bool {
        ((try? CommonPhotosWatchStore(database: database).watches()) ?? []).contains(where: \.isOn)
    }

    /// The 15-minute timer, and a pass now.
    /// Started again (a set turned on): a pass now, the timer as it was.
    func start() {
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.gatherAll() }
            }
        }
        gatherAll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Every set that is on.
    func gatherAll() {
        guard isOn() else { return }
        guard knowsPath else { return gathersOncePathKnown = true }
        enqueue(((try? watches.watches()) ?? []).filter(\.isOn).map(\.id))
    }

    /// Run Now (Activity): this set, before the timer.
    func gatherNow(watchId: String) {
        enqueue([watchId])
    }

    private func enqueue(_ ids: [String]) {
        for id in ids where !queue.contains(id) { queue.append(id) }
        guard !isBusy else { return }
        isBusy = true
        Task {
            while !queue.isEmpty {
                let id = queue.removeFirst()
                await gather(watchId: id)
            }
            isBusy = false
            onChange()
        }
    }

    private func gather(watchId: String) async {
        guard let watch = (try? watches.watch(id: watchId)) ?? nil, watch.isOn else { return }
        // The other process has this set now.
        let claims = CommonPhotosClaims(database: database)
        guard claims.claim(.watch, id: watch.id) else { return }
        let renewal = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                try? await Task.sleep(for: CommonPhotosClaims.renewEvery)
                if !Task.isCancelled { _ = claims.renew(.watch, id: watch.id) }
            }
        }
        defer {
            renewal.cancel()
            claims.release(.watch, id: watch.id)
        }
        let server = (try? servers.fetch(id: watch.connectionId)) ?? nil
        let pass = CommonPhotosGatherPass(
            database: database,
            connection: { [makeClient] _ in server.map { (makeClient($0), $0.name) } },
            conditions: { [weak self] in (self?.isExpensivePath ?? false, MacKeepAwake.isOnPowerAdapter) })
        var gather = CommonPhotosAutoGather(database: database, pass: pass)
        gather.readyToMove = { count, destination, runId in
            MacCommonPhotosNotices.readyToMove(count: count, destination: destination, runId: runId)
        }
        let result = await gather.gather(watch)
        Self.log.notice("gather pass \(watch.id, privacy: .public): \(String(describing: result.outcome), privacy: .public)")
        onChange()
        // A Copy set's run of the day, or a run the server cut off; a Move
        // set's photos wait for the user (§6c).
        let runsNow: Bool = switch result.outcome {
        case .resumes: true
        case .found: watch.action == .copy
        default: false
        }
        guard runsNow, let runId = result.runId, let server else { return }
        let end = await runs.runToEnd(runId: runId)
        // The other process runs it: its outcome is reported there.
        guard !end.elsewhere else { return }
        gather.ran(watch, runId: runId, connectionName: server.name, error: end.error, byUser: end.byUser)
        Self.log.notice("gather run \(runId, privacy: .public) ended: \(end.error.map { String(describing: $0) } ?? "done", privacy: .public)")
        onChange()
    }
}
