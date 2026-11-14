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
        /// The random check on other devices' hashes (§12.4), reading only
        /// where the rules let this pass read — iCloud when `photos`, and
        /// these server sources. Returns the devices caught wrong.
        var audit: @Sendable (_ now: Date, _ photos: Bool, _ sources: Set<String>) async -> SharedHashAuditPass.Summary = { _, _, _ in .init() }
    }

    private let environment: Environment
    private var task: Task<Void, Never>?

    /// Per server source: what its check waits for, nil while it runs or
    /// when it is done.
    private(set) var waits: [String: OnServerSchedule.Wait] = [:]
    /// What iCloud downloads wait for.
    private(set) var photosWait: OnServerSchedule.Wait?
    private(set) var isRunning = false
    /// What a pass is doing now (user 2026-11-08: "stopped, and I can't see
    /// what the app is doing"), for Activity; nil between passes.
    enum Stage: String, Sendable { case listing, hashingServer, hashingPhotos, auditing, merging }
    private(set) var stage: Stage? {
        didSet { if stage != oldValue { onBatch?() } }
    }
    /// When a pass last went through with nothing left to do.
    private(set) var finishedAt: Date?
    /// Devices whose hashes the random check last caught wrong (§12.4) —
    /// their hashes were dropped and their files are read here. Cleared by
    /// a check that reads some of their files and finds them right.
    private(set) var caughtDevices: [String] = []
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
        OnServerTrace.log("app active (pass running: \(task != nil))")
        isInFront = true
        start()
    }

    /// iOS lets the pass go on after the app leaves the screen (a continued
    /// processing task, iOS 26): the background no longer stops it.
    var keepsRunningInBackground = false

    /// A foreground pass started with work left — where the continued task
    /// is asked for, while the app is still in front.
    @ObservationIgnored var onForegroundPassStart: (@MainActor () -> Void)?

    /// iOS ended the background time it gave the pass.
    func stopInBackground() {
        OnServerTrace.log("background time over — cancelling the pass")
        keepsRunningInBackground = false
        task?.cancel()
    }

    /// Waits for the pass going now, if any.
    func waitForPass() async {
        await task?.value
    }

    /// Wi‑Fi or power came, or the network is back: a server that was not
    /// reachable may answer now. Only while the app is in front.
    func conditionsChanged() {
        guard isInFront else { return }
        start()
    }

    private func start() {
        if let task {
            // A pass still winding down after a background: the foreground
            // that came meanwhile starts the next one when it ends, rather
            // than being dropped until the app is opened again. A pass that
            // is running on is left alone.
            if task.isCancelled { startsAgain = true }
            return
        }
        isRunning = true
        startsAgain = false
        if isInFront, hasWorkLeft { onForegroundPassStart?() }
        task = Task { [weak self] in
            await self?.run()
            guard let self else { return }
            self.isRunning = false
            self.stage = nil
            self.task = nil
            if self.startsAgain, self.isInFront { self.start() }
        }
    }

    /// A start asked for while a pass runs.
    private var startsAgain = false

    /// The scene went to the background: the foreground pass stops here;
    /// the system's background slot takes over when it grants one.
    func appDidEnterBackground() {
        isInFront = false
        guard !keepsRunningInBackground else {
            OnServerTrace.log("app to background — the pass goes on (continued task)")
            return
        }
        OnServerTrace.log("app to background — cancelling the pass")
        task?.cancel()
    }

    /// A pass in the system's background time (FS-19.07 §6, phase 2): the
    /// caller cancels the task when iOS says time is up, and the pass
    /// stops between batches with everything written.
    func startBackground() -> Task<Void, Never> {
        if let task { return task }
        isRunning = true
        startsAgain = false
        let started = Task { [weak self] in
            await self?.run()
            guard let self else { return }
            self.isRunning = false
            self.stage = nil
            self.task = nil
            if self.startsAgain, self.isInFront { self.start() }
        }
        task = started
        return started
    }

    /// Shows a pass another process runs — the Mac helper (FS-19.07 §11):
    /// its waits and finish time, then a new generation so screens read
    /// progress again.
    func showRemote(waits: [String: OnServerSchedule.Wait], photosWait: OnServerSchedule.Wait?,
                    finishedAt: Date?, isRunning: Bool, stage: Stage? = nil) {
        self.stage = stage
        self.waits = waits
        self.photosWait = photosWait
        self.finishedAt = finishedAt
        self.isRunning = isRunning
        generation &+= 1
    }

    #if DEBUG
    /// `-ShotDexHashMismatch`: the caught-device state, for screenshots.
    func showCaughtForDemo(_ devices: [String]) {
        caughtDevices = devices
        generation &+= 1
    }
    #endif

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
        lastPassHashed = (0, 0)
        let sources = (try? environment.serverSources()) ?? []
        OnServerTrace.log("══ pass starts · \(sources.count) server source(s)")
        defer {
            OnServerTrace.log("══ pass ends · cancelled \(Task.isCancelled) · waits \(waits.values.map { String(describing: $0) }) · photosWait \(photosWait.map { String(describing: $0) } ?? "none") · hashed server \(lastPassHashed.server) photos \(lastPassHashed.photos)")
        }
        guard !sources.isEmpty else {
            waits = [:]
            photosWait = nil
            return
        }
        let (isExpensive, isCharging) = await environment.conditions()
        OnServerTrace.log("conditions · expensive network \(isExpensive) · charging \(isCharging)")
        var openSources: [(id: String, connectionId: String)] = []
        var allRules: [OnServerSchedule.JobRules] = []
        var newWaits: [String: OnServerSchedule.Wait] = [:]
        let jobsBySource = sources.map { (try? environment.jobRules($0.connectionId)) ?? [] }
        // The Photos side needs no server: its originals are listed and
        // hashed while the servers are listed, not after (user 2026-11-08:
        // a share's listing took an hour and nothing else moved meanwhile).
        let photosRules = OnServerSchedule.wait(for: jobsBySource.map(OnServerSchedule.rules(of:)),
                                                isExpensivePath: isExpensive, isCharging: isCharging)
        let environment = self.environment
        // Set once every source is listed: the Photos side stops after the
        // batch in hand, and the rounds below take turns with the servers.
        // Without it the servers waited for every iCloud original first —
        // 56,000 photos on an iPad, days, and not one server file read
        // (user 2026-11-11).
        let listingDone = OSAllocatedUnfairLock(initialState: false)
        let refused = OSAllocatedUnfairLock(initialState: false)
        let photosMeanwhile: Task<Int, Never>? = photosRules == nil && !Task.isCancelled ? Task { [weak self] in
            var hashed = 0
            while !Task.isCancelled, !listingDone.withLock({ $0 }), let summary = try? await environment.hashPhotos(start) {
                hashed += summary.adopted + summary.seeded + summary.hashed
                // Screens read the counts again, as after any batch.
                self?.generation &+= 1
                if summary.iCloudRefusing { refused.withLock { $0 = true } }
                if summary.waitingForSpace || summary.iCloudRefusing
                    || summary.listed + summary.seeded + summary.hashed + summary.failed == 0 { break }
            }
            return hashed
        } : nil
        for (index, source) in sources.enumerated() {
            let jobs = jobsBySource[index]
            allRules.append(OnServerSchedule.rules(of: jobs))
            if let wait = OnServerSchedule.wait(for: jobs, isExpensivePath: isExpensive, isCharging: isCharging) {
                newWaits[source.id] = wait
                continue
            }
            guard !Task.isCancelled else { break }
            stage = .listing
            OnServerActivity.shared.begin(.listing(source: source.name))
            if await environment.list(source.id) {
                openSources.append((source.id, source.connectionId))
            } else {
                newWaits[source.id] = .unreachable(source.name)
            }
        }
        listingDone.withLock { $0 = true }
        // The download in hand is dropped, not waited for: on a slow iCloud
        // one original took 230 s (trace 2026-11-11), a batch hours. It is
        // asked for again in the rounds below.
        photosMeanwhile?.cancel()
        if let photosMeanwhile {
            // Cancelled with the pass: the batch in hand finishes first.
            let hashed = await withTaskCancellationHandler { await photosMeanwhile.value } onCancel: { photosMeanwhile.cancel() }
            lastPassHashed.photos += hashed
        }
        OnServerTrace.log("listing done · open sources \(openSources.count) of \(sources.count)")
        waits = newWaits
        photosWait = OnServerSchedule.wait(for: allRules, isExpensivePath: isExpensive, isCharging: isCharging)
        if photosWait == nil, refused.withLock({ $0 }) { photosWait = .iCloudRefusing }
        generation &+= 1

        // Hashes the other devices worked out come first: what they read is
        // not read here (§12.3).
        if !Task.isCancelled, await environment.adoptShared(start) > 0 { generation &+= 1 }
        await hashRounds(openSources: openSources, sources: sources, start: start)
        // The random check, once both sides are hashed (§12.4). A device
        // caught wrong leaves files unhashed: they are read here now.
        if !Task.isCancelled {
            stage = .auditing
            let open = Set(openSources.map(\.id).filter { waits[$0] == nil })
            let audit = await environment.audit(start, photosWait == nil, open)
            caughtDevices = Array(Set(caughtDevices).subtracting(audit.cleared).union(audit.caught)).sorted()
            if !audit.caught.isEmpty {
                generation &+= 1
                await hashRounds(openSources: openSources, sources: sources, start: start)
            }
        }
        if !Task.isCancelled { stage = .merging }
        if !Task.isCancelled, (try? await environment.merge()) ?? 0 > 0 {
            generation &+= 1
        }
        if !Task.isCancelled { await environment.publishShared(start) }
        stage = nil
        OnServerActivity.shared.clear()
        if Task.isCancelled {
            for source in openSources where waits[source.id] == nil { waits[source.id] = .openApp }
            if photosWait == nil { photosWait = .openApp }
        } else if waits.isEmpty, photosWait == nil {
            finishedAt = now()
        }
        if photosWait == .iCloudRefusing { scheduleRetry() }
    }

    /// How long the Photos side rests after iCloud refused a whole batch.
    static let iCloudRetry: Duration = .seconds(10 * 60)
    private var retry: Task<Void, Never>?

    /// A new pass once iCloud has had time, while the app is in front or a
    /// continued task holds the check.
    private func scheduleRetry() {
        retry?.cancel()
        retry = Task { [weak self] in
            try? await Task.sleep(for: Self.iCloudRetry)
            guard !Task.isCancelled, let self, self.isInFront || self.keepsRunningInBackground else { return }
            self.start()
        }
    }

    /// Batches until a round does nothing: a Photos hash can make a server
    /// file worth reading, and the other way round.
    private func hashRounds(openSources: [(id: String, connectionId: String)],
                            sources: [(id: String, name: String, connectionId: String)], start: Date) async {
        while !Task.isCancelled {
            var didWork = false
            for source in openSources where waits[source.id] == nil {
                guard !Task.isCancelled else { break }
                stage = .hashingServer
                guard let summary = try? await environment.hashServer(source.id, source.connectionId, start) else { continue }
                if summary.stoppedBy != nil, let name = sources.first(where: { $0.id == source.id })?.name {
                    waits[source.id] = .unreachable(name)
                }
                lastPassHashed.server += summary.seeded + summary.fromLedger + summary.hashed
                didWork = didWork || summary.seeded + summary.fromLedger + summary.hashed + summary.failed > 0
            }
            if photosWait == nil, !Task.isCancelled { stage = .hashingPhotos }
            if photosWait == nil, !Task.isCancelled, let summary = try? await environment.hashPhotos(start) {
                if summary.waitingForSpace { photosWait = .space }
                if summary.iCloudRefusing {
                    // Asking again at once only gets the same answer: rest.
                    OnServerTrace.log("iCloud refused a whole batch — the Photos side rests \(Int(Self.iCloudRetry.components.seconds / 60)) min")
                    photosWait = .iCloudRefusing
                }
                lastPassHashed.photos += summary.adopted + summary.seeded + summary.hashed
                didWork = didWork || summary.listed + summary.seeded + summary.hashed + summary.failed > 0
            }
            generation &+= 1
            guard didWork else { break }
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
                     gate: IndexInteractionGate? = nil,
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
                let listed = await OnServerTrace.timed("list server source", { (summary: ServerSourceIndexer.Summary?) in
                    summary.map { "· \($0)" } ?? "· no summary (another pass is listing, or it failed — see the ServerSourceRefresh log)"
                }) { await refresh.rescan(sourceId: sourceId) }
                if let summary = listed {
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
                return try await OnServerTrace.timed("server batch", { (summary: ServerFileHashPass.Summary) in
                    "· from Backup/Common \(summary.seeded) · from ledger \(summary.fromLedger) · read+hashed \(summary.hashed) · failed \(summary.failed) · published \(summary.published) · stopped by \(summary.stoppedBy.map { $0.localizedDescription } ?? "nothing")"
                }) {
                    try await pass.run(sourceId: sourceId, connectionId: connectionId, folder: server.folder, now: now)
                }
            },
            hashPhotos: { now in
                var pass = PhotosFileHashPass(store: store, listFiles: PhotosFileHashPass.liveLister())
                pass.hashesEverything = hashesEverything()
                // A photo open in the viewer gets the iCloud bandwidth: the
                // next original waits, as the index pass does (user
                // 2026-11-14: "opening a photo takes seconds").
                if let gate { pass.shouldYield = { gate.shouldPauseIndexing } }
                #if os(macOS)
                // A Mac library is usually on disk: four originals at once.
                pass.concurrentDownloads = 4
                let downloadLimit: Int? = nil
                #else
                // One at a time on iPhone and iPad (§4). Four at once was
                // tried (trace 2026-11-11): iCloud then failed 27 of 28 with
                // CloudPhotoLibraryErrorDomain 1006, where one at a time had
                // finished every file, slowly.
                // Short batches: the server's turn comes between them, and a
                // batch of 200 slow downloads kept it waiting for hours.
                let downloadLimit: Int? = 24
                #endif
                if let exchange, IndexShareService.sharesIndex {
                    pass.adoptListed = { copyIds, now in
                        do { return try await exchange.adoptPhotos(copyIds: copyIds, now: now) } catch {
                            OnServerCheck.logger.error("adopt listed: \(error.localizedDescription, privacy: .public)")
                            return 0
                        }
                    }
                }
                return try await OnServerTrace.timed("photos batch", { (summary: PhotosFileHashPass.Summary) in
                    "· listed \(summary.listed) · adopted \(summary.adopted) · from Backup \(summary.seeded) · downloaded+hashed \(summary.hashed) · failed \(summary.failed) · waiting for space \(summary.waitingForSpace)"
                }) {
                    try await pass.run(downloadLimit: downloadLimit, now: now)
                }
            },
            observeConditions: { changed in
                network.setPathChangeHandler { _, _ in changed() }
                power.setPowerChangeHandler { _, _ in changed() }
            },
            merge: {
                let merged = try await OnServerTrace.timed("merge", { (count: Int) in "· \(count)" }) {
                    try OnServerMergePass(database: database).run()
                }
                if merged > 0 { await listingChanged() }
                return merged
            },
            adoptShared: { now in
                guard let exchange, let indexShare, IndexShareService.sharesIndex else { return 0 }
                // Bounded: a slow or offline iCloud must not hold up hashing;
                // what lands later is taken on the next pass.
                await OnServerTrace.timed("iCloud pull of shared hashes") { await indexShare.pull(waitingAtMost: .seconds(10)) }
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
                await OnServerTrace.timed("iCloud push of own hashes") { await indexShare.push(batches: 5) }
            },
            audit: { now, photos, openSources in
                let photosPass = PhotosFileHashPass(store: store, listFiles: PhotosFileHashPass.liveLister())
                var pass = SharedHashAuditPass(store: store) { file in
                    do {
                        if file.kind == "photos" {
                            guard photos, let assetId = file.assetId else { return nil }
                            return try await photosPass.hashOne(assetId: assetId, fileKey: file.fileKey, size: file.size)
                        }
                        guard let sourceId = file.sourceId, openSources.contains(sourceId), let connectionId = file.connectionId,
                              let path = file.relativePath, let server = try servers.fetch(id: connectionId) else { return nil }
                        let client = LockedRemoteFileClient(
                            RemoteFileClientFactory.make(for: server, password: servers.password(for: server.id) ?? ""),
                            lock: connectionLock, connectionId: server.id, priority: .normal)
                        // Always closed, and never held long: a NAS that stops
                        // answering mid-read must not hold up the pass.
                        let sha = try? await withConnectTimeout(host: server.host, seconds: 180) {
                            try await client.connect()
                            return try await client.sha256(of: ServerUploadPath.join(server.folder, path), progress: { _ in })
                        }
                        await client.disconnect()
                        return sha
                    } catch {
                        // Unreadable now is not wrong: skipped, as the rules say.
                        return nil
                    }
                }
                pass.photos = photos
                pass.sources = openSources
                do { return try await OnServerTrace.timed("random audit") { try await pass.run(now: now) } } catch {
                    if !(error is CancellationError) {
                        OnServerCheck.logger.error("audit: \(error.localizedDescription, privacy: .public)")
                    }
                    return .init()
                }
            }
        )
    }
}

/// A timed trace of the on-server check, for "what is it doing that takes
/// so long" (user 2026-11-11). Debug builds only: every line goes to the
/// unified log (category `OnServerTrace`) and to
/// `Library/Caches/onserver-trace.log` in the app's container, which
/// `xcrun devicectl device copy from` reads off a device. Sizes, counts and
/// seconds; a Photos file is named by its resource key.
enum OnServerTrace {
    private static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "OnServerTrace")
    private static let queue = DispatchQueue(label: "com.hoangtuan.shotdex.onserver-trace")
    private static let maximumBytes = 2 << 20

    static let isEnabled: Bool = {
        #if DEBUG
        return NSClassFromString("XCTestCase") == nil
        #else
        return false
        #endif
    }()

    static var fileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("onserver-trace.log")
    }

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let text = message()
        logger.notice("\(text, privacy: .public)")
        let line = "\(Date().formatted(.iso8601.time(includingFractionalSeconds: true).timeZone(separator: .omitted))) \(text)\n"
        queue.async {
            guard let url = fileURL, let data = line.data(using: .utf8) else { return }
            if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maximumBytes {
                // Keep the newer half.
                if let old = try? Data(contentsOf: url) { try? old.suffix(maximumBytes / 2).write(to: url) }
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }

    /// Runs `work`, then logs `name`, how long it took and what `describe` says of its result.
    @discardableResult
    static func timed<T>(_ name: String, _ describe: (T) -> String = { _ in "" }, _ work: () async throws -> T) async rethrows -> T {
        guard isEnabled else { return try await work() }
        let clock = ContinuousClock()
        let start = clock.now
        log("▶ \(name)")
        do {
            let value = try await work()
            log("◀ \(name) \(seconds(start.duration(to: clock.now)))s \(describe(value))")
            return value
        } catch {
            log("✗ \(name) \(seconds(start.duration(to: clock.now)))s \(error is CancellationError ? "cancelled" : error.localizedDescription)")
            throw error
        }
    }

    static func seconds(_ duration: Duration) -> String {
        String(format: "%.1f", Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
    }

    static func megabytes(_ bytes: Int64?) -> String {
        bytes.map { String(format: "%.1fMB", Double($0) / 1_048_576) } ?? "?MB"
    }
}
