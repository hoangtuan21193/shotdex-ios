import Foundation
import GRDB
import Observation
import os

/// Runs the on-server check while ShotDex is in front (FS-19.07 §6, phase
/// 1): each time the app comes to the foreground, every server source is
/// listed again, then hashed — Backup's records first, then only files of a
/// size worth reading on each side — in batches, until nothing is left or
/// the app goes to the background. Every step writes as it goes, so the
/// next foreground picks up where this one stopped.
///
/// Each connection follows its Backup jobs' rules (`OnServerSchedule`);
/// iCloud downloads follow the strictest rules of every connection that has
/// a server source, since a download is only for a file one of them holds.
@MainActor
@Observable
final class OnServerCheck {
    nonisolated static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "OnServerCheck")
    /// The world the check runs in; closures, so tests need no server,
    /// library or network.
    struct Environment: Sendable {
        /// Server sources: id, name, connection.
        var serverSources: @Sendable () throws -> [(id: String, name: String, connectionId: String)]
        var jobRules: @Sendable (_ connectionId: String) throws -> [OnServerSchedule.JobRules]
        /// Waits for the first network report, then says whether the path
        /// is metered and whether the device is charging.
        var conditions: @Sendable () async -> (isExpensivePath: Bool, isCharging: Bool)
        /// Lists the source again; false when its server did not answer.
        var list: @Sendable (_ sourceId: String) async -> Bool
        var hashServer: @Sendable (_ sourceId: String, _ connectionId: String, _ now: Date) async throws -> ServerFileHashPass.Summary
        var hashPhotos: @Sendable (_ now: Date) async throws -> PhotosFileHashPass.Summary
        /// Calls back when the network or power changes — a server may be
        /// back, or Wi‑Fi may have come.
        var observeConditions: @Sendable (_ changed: @escaping @Sendable () -> Void) -> Void = { _ in }
        /// Folds server photos into the Photos items they are byte for byte
        /// (phase 2, display only); returns how many.
        var merge: @Sendable () async throws -> Int = { 0 }
        /// Pulls what the other devices on the same iCloud account hashed and
        /// fills the files it matches (FS-19.07 §12.3); returns how many.
        var adoptShared: @Sendable (_ now: Date) async -> Int = { _ in 0 }
        /// Queues and uploads what this device hashed, for the others.
        var publishShared: @Sendable (_ now: Date) async -> Void = { _ in }
    }

    private let environment: Environment
    private var task: Task<Void, Never>?

    /// Per server source: what its check waits for, nil while it runs or
    /// when it is done.
    private(set) var waits: [String: OnServerSchedule.Wait] = [:]
    /// What iCloud downloads wait for.
    private(set) var photosWait: OnServerSchedule.Wait?
    private(set) var isRunning = false
    /// When a pass last went through with nothing left to do.
    private(set) var finishedAt: Date?
    /// Bumped after each batch, so a screen showing progress reads again.
    private(set) var generation = 0 {
        didSet { onBatch?() }
    }
    /// Runs after each batch — the grid's glyph reads presence again.
    @ObservationIgnored var onBatch: (@MainActor () -> Void)?

    /// Between a foreground and the next background.
    private var isInFront = false

    init(environment: Environment) {
        self.environment = environment
        environment.observeConditions { [weak self] in
            Task { @MainActor in self?.conditionsChanged() }
        }
    }

    /// The scene came to the foreground: a pass starts unless one runs.
    func appBecameActive() {
        isInFront = true
        start()
    }

    /// Wi‑Fi or power came, or the network is back: a server that was not
    /// reachable may answer now. Only while the app is in front.
    func conditionsChanged() {
        guard isInFront else { return }
        start()
    }

    private func start() {
        guard task == nil else { return }
        isRunning = true
        task = Task { [weak self] in
            await self?.run()
            self?.isRunning = false
            self?.task = nil
        }
    }

    /// The scene went to the background: the foreground pass stops here;
    /// the system's background slot takes over when it grants one.
    func appDidEnterBackground() {
        isInFront = false
        task?.cancel()
    }

    /// A pass in the system's background time (FS-19.07 §6, phase 2): the
    /// caller cancels the task when iOS says time is up, and the pass
    /// stops between batches with everything written.
    func startBackground() -> Task<Void, Never> {
        if let task { return task }
        isRunning = true
        let started = Task { [weak self] in
            await self?.run()
            self?.isRunning = false
            self?.task = nil
        }
        task = started
        return started
    }

    /// Shows a pass another process runs — the Mac helper (FS-19.07 §11):
    /// its waits and finish time, then a new generation so screens read
    /// progress again.
    func showRemote(waits: [String: OnServerSchedule.Wait], photosWait: OnServerSchedule.Wait?,
                    finishedAt: Date?, isRunning: Bool) {
        self.waits = waits
        self.photosWait = photosWait
        self.finishedAt = finishedAt
        self.isRunning = isRunning
        generation &+= 1
    }

    /// Some server source, or iCloud downloads, still has work or waits.
    var hasWorkLeft: Bool { finishedAt == nil || !waits.isEmpty || photosWait != nil }

    /// Files hashed by the last pass, server and Photos side — what the
    /// background slot reports (spike S3).
    private(set) var lastPassHashed = (server: 0, photos: 0)

    /// One pass; also what tests call.
    func run(now: @escaping @Sendable () -> Date = { Date() }) async {
        // One start time for the whole pass: a file that fails is tried
        // again on the next pass, not in the next round of this one.
        let start = now()
        let sources = (try? environment.serverSources()) ?? []
        guard !sources.isEmpty else {
            waits = [:]
            photosWait = nil
            return
        }
        let (isExpensive, isCharging) = await environment.conditions()
        var openSources: [(id: String, connectionId: String)] = []
        var allRules: [OnServerSchedule.JobRules] = []
        var newWaits: [String: OnServerSchedule.Wait] = [:]
        for source in sources {
            let jobs = (try? environment.jobRules(source.connectionId)) ?? []
            allRules.append(OnServerSchedule.rules(of: jobs))
            if let wait = OnServerSchedule.wait(for: jobs, isExpensivePath: isExpensive, isCharging: isCharging) {
                newWaits[source.id] = wait
                continue
            }
            guard !Task.isCancelled else { break }
            if await environment.list(source.id) {
                openSources.append((source.id, source.connectionId))
            } else {
                newWaits[source.id] = .unreachable(source.name)
            }
        }
        waits = newWaits
        photosWait = OnServerSchedule.wait(for: allRules, isExpensivePath: isExpensive, isCharging: isCharging)
        generation &+= 1

        lastPassHashed = (0, 0)
        // Hashes the other devices worked out come first: what they read is
        // not read here (§12.3).
        if !Task.isCancelled, await environment.adoptShared(start) > 0 { generation &+= 1 }
        // Batches until a round does nothing: a Photos hash can make a
        // server file worth reading, and the other way round.
        while !Task.isCancelled {
            var didWork = false
            for source in openSources where waits[source.id] == nil {
                guard !Task.isCancelled else { break }
                guard let summary = try? await environment.hashServer(source.id, source.connectionId, start) else { continue }
                if summary.stoppedBy != nil, let name = sources.first(where: { $0.id == source.id })?.name {
                    waits[source.id] = .unreachable(name)
                }
                lastPassHashed.server += summary.seeded + summary.fromLedger + summary.hashed
                didWork = didWork || summary.seeded + summary.fromLedger + summary.hashed + summary.failed > 0
            }
            if photosWait == nil, !Task.isCancelled, let summary = try? await environment.hashPhotos(start) {
                if summary.waitingForSpace { photosWait = .space }
                lastPassHashed.photos += summary.adopted + summary.seeded + summary.hashed
                didWork = didWork || summary.listed + summary.seeded + summary.hashed + summary.failed > 0
            }
            generation &+= 1
            guard didWork else { break }
        }
        if !Task.isCancelled, (try? await environment.merge()) ?? 0 > 0 {
            generation &+= 1
        }
        if !Task.isCancelled { await environment.publishShared(start) }
        if Task.isCancelled {
            for source in openSources where waits[source.id] == nil { waits[source.id] = .openApp }
            if photosWait == nil { photosWait = .openApp }
        } else if waits.isEmpty, photosWait == nil {
            finishedAt = now()
        }
    }
}

extension OnServerCheck.Environment {
    /// The real world: the FS-19 server sources, their connections' Backup
    /// jobs, the device's network and power, and the two hash passes. Every
    /// server call goes through the connection's lock, behind Backup.
    /// `listingChanged` runs when a listing found new or changed photos.
    /// `hashesEverything` (the Mac with Share Index Across Devices on,
    /// FS-19.07 §12.1): every Photos and server file is hashed, for the
    /// other devices, not only the candidates of a size.
    static func live(database: AppDatabase, servers: FileServerStore, refresh: ServerSourceRefresh,
                     connectionLock: ConnectionLock, hashesEverything: @escaping @Sendable () -> Bool,
                     indexShare: IndexShareService? = nil,
                     listingChanged: @escaping @Sendable () async -> Void) -> Self {
        // Monitors of its own: the shared ones have a single handler slot.
        let network = NetworkMonitor()
        let power = PowerMonitor()
        let store = CopyFileStore(database: database)
        // FS-19.07 §12.3: only while the index is shared across devices.
        let exchange = indexShare.map { _ in
            SharedHashExchange(database: database, device: BackupDeviceIdentity.current(),
                               cloudIds: { IndexShareService.cloudIdentifiers(for: $0) })
        }
        return Self(
            serverSources: {
                try database.reader.read { db in
                    try Row.fetchAll(db, sql: """
                        SELECT id, name, connectionId FROM sources WHERE kind = 'server' AND connectionId IS NOT NULL
                        ORDER BY createdAt, id
                        """).map { (id: $0["id"], name: $0["name"], connectionId: $0["connectionId"]) }
                }
            },
            jobRules: { connectionId in
                try BackupStore(database: database).jobs().filter { $0.connectionId == connectionId }.map {
                    OnServerSchedule.JobRules(onlyOnWiFi: $0.settings.onlyOnWiFi, onlyWhileCharging: $0.settings.onlyWhileCharging)
                }
            },
            conditions: {
                await network.awaitInitialPath()
                return (network.isExpensivePath, power.isCharging)
            },
            list: { sourceId in
                if let summary = await refresh.rescan(sourceId: sourceId) {
                    if summary.photos > 0 { await listingChanged() }
                    return !summary.disconnected && summary.stoppedBy == nil
                }
                // Another trigger is listing it right now, or it has no
                // connection: go by what the last listing found.
                return (try? SourceStore(database: database).status(sourceId: sourceId)) == .online
            },
            hashServer: { sourceId, connectionId, now in
                guard let server = try? servers.fetch(id: connectionId) else { return .init() }
                let client = LockedRemoteFileClient(RemoteFileClientFactory.make(for: server, password: servers.password(for: server.id) ?? ""),
                                                    lock: connectionLock, connectionId: server.id, priority: .normal)
                var pass = ServerFileHashPass(store: store, client: client)
                pass.hashesEverything = hashesEverything()
                // The ledger on the NAS (FS-19.07 §12.2): every device reads
                // it and writes what it hashed.
                pass.deviceId = BackupDeviceIdentity.current()
                return try await pass.run(sourceId: sourceId, connectionId: connectionId, folder: server.folder, now: now)
            },
            hashPhotos: { now in
                var pass = PhotosFileHashPass(store: store, listFiles: PhotosFileHashPass.liveLister())
                pass.hashesEverything = hashesEverything()
                if let exchange, IndexShareService.sharesIndex {
                    pass.adoptListed = { copyIds, now in
                        do { return try await exchange.adoptPhotos(copyIds: copyIds, now: now) } catch {
                            OnServerCheck.logger.error("adopt listed: \(error.localizedDescription, privacy: .public)")
                            return 0
                        }
                    }
                }
                return try await pass.run(now: now)
            },
            observeConditions: { changed in
                network.setPathChangeHandler { _, _ in changed() }
                power.setPowerChangeHandler { _, _ in changed() }
            },
            merge: {
                let merged = try OnServerMergePass(database: database).run()
                if merged > 0 { await listingChanged() }
                return merged
            },
            adoptShared: { now in
                guard let exchange, let indexShare, IndexShareService.sharesIndex else { return 0 }
                // Bounded: a slow or offline iCloud must not hold up hashing;
                // what lands later is taken on the next pass.
                await indexShare.pull(waitingAtMost: .seconds(10))
                guard !Task.isCancelled else { return 0 }
                do { return try await exchange.adopt(now: now) } catch {
                    OnServerCheck.logger.error("adopt: \(error.localizedDescription, privacy: .public)")
                    return 0
                }
            },
            publishShared: { now in
                guard let exchange, let indexShare, IndexShareService.sharesIndex else { return }
                do { try await exchange.recordOwn(now: now) } catch {
                    OnServerCheck.logger.error("record own hashes: \(error.localizedDescription, privacy: .public)")
                }
                // A few batches a pass; the rest go up on the next one.
                await indexShare.push(batches: 5)
            }
        )
    }
}
