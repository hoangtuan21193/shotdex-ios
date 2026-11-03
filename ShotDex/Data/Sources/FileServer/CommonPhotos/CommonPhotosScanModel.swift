import Foundation
import GRDB
import Observation
import os

/// What the Find Common Photos sheet holds (FS-19.08 §4–5, board
/// `MAC_CommonPhotos`): the folders and where the common photos go, Copy or
/// Move, and the scan — the listing, the Likely the same preview, then the
/// SHA-256 check that makes each photo Same. The sheet draws this; the
/// engine (`CommonPhotosScanner`, `CommonPhotosMatcher`,
/// `CommonPhotosVerifier`, `CommonPhotosRunner.items`) does the work.
/// Every path is a server path; `client` is the connection's, behind its
/// lock.
@MainActor
@Observable
final class CommonPhotosScanModel {
    nonisolated static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "CommonPhotos")
    enum Phase: Equatable {
        case idle
        case listing
        case checking
        case done
        /// The scan stopped on an error; what it had found stays on screen.
        case failed(String)
    }

    /// Why the run button is dimmed, in the words the sheet shows.
    enum Problem: Equatable {
        case selection(CommonPhotosSelection.Problem)
        case noDestination
    }

    /// One row of the results: a photo of the first folder that can still be
    /// common, and where it stands.
    struct Row: Identifiable, Equatable {
        enum Status: Equatable {
            case checking, likely, same
            /// The scan failed before reaching it.
            case notChecked
        }

        let id: String
        let name: String
        /// Folder and subfolder in each folder, "Tuan/2025/06 · Vo/from-tuan",
        /// and "as <name>" where the name differs from the first.
        let paths: String
        /// Every copy's whole path below its folder, for the tooltip.
        let fullPaths: String
        let size: Int64
        let status: Status
        /// The first folder's copy, for its thumbnail.
        let serverPath: String
    }

    let connectionId: String
    let sourceId: String
    private(set) var folders: [String]
    /// Photos and videos in each folder, once listed.
    private(set) var fileCounts: [String: Int] = [:]
    var destination: String? {
        didSet {
            guard destination != oldValue else { return }
            // A scan whose listing was cut for another set never read what
            // this set needs: scan again. Otherwise the results are cut
            // again from the whole of them, now or when the scan ends
            // (FS-19.08 §6c).
            if listingWasCut {
                resetScan()
                notice = .otherDestination
            } else if phase == .done { recut() }
        }
    }
    var action = CommonPhotosRun.Action.copy {
        didSet {
            // A Copy scan took earlier hashes on trust (FS-19.08 §6c); a
            // Move deletes on them, so it scans again.
            if action == .move, scannedTrustingCache, phase != .idle {
                resetScan()
                notice = .moveChecksAgain
            }
        }
    }
    /// The server's error the last scan stopped on, for the helper to tell a
    /// folder gone from a server away (FS-19.08 §6c).
    private(set) var failureError: RemoteFileError?
    /// Saving what the last scan read, so the helper can wait for it.
    private var saving: Task<Void, Never>?
    /// The scan shown took every known hash on trust (a Copy scan).
    private var scannedTrustingCache = false
    /// Scan Everything (FS-19.08 §6c): check every photo, not only the new
    /// ones, even when the set gathered before.
    /// The results shown came from Scan Everything (FS-19.08 §6c): every
    /// common photo, none cut out. One scan's choice; the next Scan checks
    /// only new photos again.
    private(set) var scansEverything = false
    /// When this set last gathered, once a scan looked; nil for a set that
    /// never did — every photo is checked then.
    private(set) var lastGathered: Date?
    /// How many photos the set gathered that are still in the destination
    /// — the ones the results leave out.
    private(set) var alreadyGathered = 0
    /// Why the last results went (FS-19.08 §6c): said where they were.
    enum Notice: Equatable { case moveChecksAgain, otherDestination }
    private(set) var notice: Notice?
    /// The scan read only the sizes new to its set (its destination was
    /// known when it listed).
    private var listingWasCut = false
    /// What the scan found before the photos the set already gathered were
    /// taken out, so another destination can cut it again.
    private var allPhotos: [CommonPhoto] = []
    private var cutTask: Task<Void, Never>?
    /// Results are being cut to the destination chosen: not runnable yet.
    private(set) var isCutting = false
    private(set) var phase = Phase.idle
    private(set) var preview: CommonPhotosMatcher.Preview?
    private(set) var photos: [CommonPhoto] = []
    /// Files listed so far, while listing.
    private(set) var listedFiles = 0
    /// First-folder candidates the verifier has decided; the rows follow this.
    private(set) var checkedFiles = 0
    /// Bytes still to read, refreshed at most ten times a second.
    private(set) var bytesLeft: Int64 = 0
    @ObservationIgnored private(set) var listing: CommonPhotosScanner.Listing?

    @ObservationIgnored private let client: any RemoteFileClient
    @ObservationIgnored private let database: AppDatabase?
    @ObservationIgnored private let sources: [CommonPhotosSources.Source]
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    /// The scan the callbacks belong to: a late one from a scan cancelled
    /// or finished changes nothing.
    @ObservationIgnored private var scanId = UUID()
    @ObservationIgnored private var isConnected = false
    /// For a screenshot of the scan half done; the sheet never sets it.
    @ObservationIgnored var groupDelay: Duration?

    /// `sources` are the server sources on the same files, for the SHA-256
    /// the index already took (`copy_files`) — a file listed again with the
    /// same size and write time is not read twice.
    init(connectionId: String, sourceId: String, folders: [String], client: any RemoteFileClient,
         database: AppDatabase? = nil, sources: [CommonPhotosSources.Source] = []) {
        self.connectionId = connectionId
        self.sourceId = sourceId
        self.folders = Self.unique(folders.map(ServerUploadPath.normalizedFolder))
        self.client = client
        self.database = database
        self.sources = sources
    }

    // MARK: Folders and destination

    func add(folder: String) {
        let folder = ServerUploadPath.normalizedFolder(folder)
        guard !folders.contains(where: { $0.lowercased() == folder.lowercased() }) else { return }
        folders.append(folder)
        resetScan()
    }

    func remove(folder: String) {
        folders.removeAll { $0 == folder }
        resetScan()
    }

    /// The first thing that stops a run, or nil (FS-19.08 §4).
    var problem: Problem? {
        if let problem = CommonPhotosSelection.problem(folders: folders, destination: destination) { return .selection(problem) }
        return destination == nil ? .noDestination : nil
    }

    /// Scan needs the folders only; where they go can be chosen meanwhile.
    var canScan: Bool {
        !isScanning && CommonPhotosSelection.problem(folders: folders, destination: nil) == nil
    }

    var isScanning: Bool { phase == .listing || phase == .checking }

    var failure: String? {
        if case .failed(let message) = phase { message } else { nil }
    }

    /// A destination is set and Same photos are found: Copy N / Move N.
    /// Never a Move on a scan that took earlier hashes on trust.
    var canRun: Bool {
        phase == .done && !isCutting && problem == nil && !photos.isEmpty && !(action == .move && scannedTrustingCache)
    }

    /// Whether some source shows what lands in the destination.
    var isDestinationIndexed: Bool {
        guard let destination, let connection = sources.first?.connection else { return true }
        return CommonPhotosSources.isIndexed(destination, on: connection, sources: sources)
    }

    // MARK: Counts

    var sameCount: Int { photos.count }

    /// First-folder candidates still to decide.
    var candidateCount: Int { preview?.candidateCount ?? 0 }

    var checkingCount: Int { isScanning ? max(0, candidateCount - checkedFiles) : 0 }

    var sameBytes: Int64 { photos.reduce(Int64(0)) { $0 + $1.size } }

    /// Same first, in the order found, then what is still being checked —
    /// or, after a failure, was never reached.
    var rows: [Row] {
        guard let preview else { return [] }
        var rows = photos.map { photo in
            row(photo.files.map { $0[0] }, size: photo.size, status: .same)
        }
        guard phase != .done else { return rows }
        let same = Set(photos.flatMap { $0.files[0] })
        let stopped = failure != nil
        for group in undecidedGroups(preview) {
            for file in group.files[0] where !same.contains(file) {
                let status: Row.Status = stopped ? .notChecked : (preview.likely.contains(file) ? .likely : .checking)
                rows.append(row([file], size: file.size, status: status))
            }
        }
        return rows
    }

    /// The groups the verifier has not reached, in its order: groups holding
    /// a Likely file first (`CommonPhotosVerifier.verify`).
    private func undecidedGroups(_ preview: CommonPhotosMatcher.Preview) -> [CommonPhotosMatcher.SizeGroup] {
        let holdsLikely = { (group: CommonPhotosMatcher.SizeGroup) in group.files.joined().contains(where: preview.likely.contains) }
        let ordered = preview.groups.filter(holdsLikely) + preview.groups.filter { !holdsLikely($0) }
        var checked = checkedFiles
        return ordered.drop { group in
            guard checked >= group.files[0].count else { return false }
            checked -= group.files[0].count
            return true
        }.map { $0 }
    }

    private func row(_ files: [CommonPhotosFile], size: Int64, status: Row.Status) -> Row {
        let first = files[0]
        let paths = files.map { file -> String in
            var place = ServerUploadPath.join(ServerUploadPath.lastComponent(of: folders[file.folder]), file.subfolder)
            if file.comparableName != first.comparableName { place += " as " + file.name }
            return place
        }
        let fullPaths = files.map { ServerUploadPath.join(ServerUploadPath.lastComponent(of: folders[$0.folder]), $0.relativePath) }
        return Row(id: "\(first.folder)/\(first.relativePath)", name: first.name, paths: paths.joined(separator: " · "),
                   fullPaths: fullPaths.joined(separator: "\n"), size: size, status: status,
                   serverPath: ServerUploadPath.join(folders[first.folder], first.relativePath))
    }

    // MARK: Scan

    /// Scan Everything (FS-19.08 §6c): every common photo, gathered or not.
    func scanEverything() {
        scan(everything: true)
    }

    func scan() {
        scan(everything: false)
    }

    /// One scan of only the new photos, to its end — the helper's pass
    /// (FS-19.08 §6c), with no sheet to watch it. What it read is saved
    /// before it returns.
    func scanToEnd() async {
        guard canScan else { return }
        scansEverything = false
        failureError = nil
        phase = .listing
        await runScan()
        await saving?.value
    }

    /// The helper connected the client already (to check the folders): the
    /// scan uses that session rather than logging in again.
    func adoptConnection() {
        isConnected = true
    }

    private func scan(everything: Bool) {
        guard canScan else { return }
        scansEverything = everything
        // Listing from the press on: results of the scan before are gone.
        phase = .listing
        scanTask?.cancel()
        scanTask = Task { await runScan() }
    }

    /// Stop: the scan ends where it is and what it found is dropped.
    func cancelScan() {
        if isScanning { resetScan() }
    }

    /// The sheet closed: the scan stops and the session ends.
    func close() async {
        resetScan()
        if isConnected {
            isConnected = false
            await client.disconnect()
        }
    }

    private func resetScan() {
        scanTask?.cancel()
        scanTask = nil
        scanId = UUID()
        phase = .idle
        preview = nil
        photos = []
        listing = nil
        fileCounts = [:]
        listedFiles = 0
        checkedFiles = 0
        bytesLeft = 0
        scannedTrustingCache = false
        scansEverything = false
        lastGathered = nil
        alreadyGathered = 0
        notice = nil
        listingWasCut = false
        allPhotos = []
        cutTask?.cancel()
        cutTask = nil
        isCutting = false
    }

    private func runScan() async {
        let folders = folders
        let scanId = UUID()
        self.scanId = scanId
        // A cut of the last results means nothing to this scan.
        cutTask?.cancel()
        cutTask = nil
        isCutting = false
        phase = .listing
        preview = nil
        photos = []
        listedFiles = 0
        checkedFiles = 0
        bytesLeft = 0
        // Ten updates a second at most: a big file's hash reports often.
        let lastUpdate = OSAllocatedUnfairLock(initialState: ContinuousClock.now - .seconds(1))
        let trustsCache = action == .copy
        // Set before any read: switching to Move mid-scan drops this scan.
        scannedTrustingCache = trustsCache
        // What this scan reads, kept for the next one (FS-19.08 §6c) —
        // saved even when the scan stops partway.
        let read = OSAllocatedUnfairLock(initialState: [CommonPhotosFile: String]())
        let readKeys = OSAllocatedUnfairLock(initialState: [CommonPhotosFile: String]())
        defer {
            remember(hashes: read.withLock { $0 }, keys: readKeys.withLock { $0 }, folders: folders)
        }
        do {
            if !isConnected {
                try await client.connect()
                isConnected = true
            }
            let watched = WatchedClient(base: client, delay: groupDelay) { [weak self] count in
                Task { @MainActor in
                    guard let self, self.scanId == scanId, self.phase == .listing else { return }
                    self.listedFiles += count
                }
            }
            let scanner = CommonPhotosScanner(client: watched)
            let listing = try await scanner.list(folders)
            try Task.checkCancellation()
            self.listing = listing
            // Forgotten before anything new is saved, so a save never
            // brings back a file the listing no longer has.
            await forget(notIn: listing, folders: folders)
            fileCounts = Dictionary(uniqueKeysWithValues: zip(folders, listing.files.map(\.count)))
            // Only new photos, when the set gathered before (§6c).
            let scannedFor = destination
            let gathered = scansEverything ? .init() : try await gathered(folders: folders, destination: scannedFor)
            // Stopped or replaced while the destination was listed: this
            // scan is no longer the one shown.
            try Task.checkCancellation()
            guard self.scanId == scanId else { return }
            lastGathered = gathered.lastAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            alreadyGathered = gathered.photoCount
            notice = nil
            listingWasCut = !gathered.seen.isEmpty
            var checked = listing
            checked.files = CommonPhotosIncremental.listing(listing.files, folders: folders, seen: gathered.seen)
            let records = await scanRecords(checked, folders: folders)
            try Task.checkCancellation()
            // What size and name say, shown at once; the heads refine it.
            let firstLook = CommonPhotosMatcher.preview(checked.files)
            preview = firstLook
            bytesLeft = firstLook.candidateBytes
            phase = .checking
            let groups = CommonPhotosMatcher.sizeGroups(checked.files)
            let knownKeys = records.compactMapValues(\.captureKey).filter { !$0.value.isEmpty }
            let knownNone = Set(records.filter { $0.value.captureKey == "" }.keys)
            let keys = try await scanner.readCaptureKeys(for: groups, folders: folders, known: knownKeys, knownNone: knownNone,
                                                         read: { file, key in readKeys.withLock { $0[file] = key ?? "" } }).keys
            try Task.checkCancellation()
            let preview = CommonPhotosMatcher.preview(checked.files, captureKeys: keys)
            self.preview = preview
            // The index's hashes first, then what earlier scans read.
            let known = (await knownHashes(preview, folders: folders))
                .merging(records.compactMapValues(\.sha256), uniquingKeysWith: { index, _ in index })
            let seen = gathered.seen
            let found = try await CommonPhotosVerifier(client: watched).verify(
                preview, folders: folders, knownHashes: known, trustsCache: trustsCache,
                hashed: { batch in read.withLock { $0.merge(batch, uniquingKeysWith: { _, new in new }) } },
                found: { [weak self] batch in
                Task { @MainActor in
                    guard let self, self.scanId == scanId, self.phase == .checking else { return }
                    self.photos += CommonPhotosIncremental.newPhotos(batch, folders: folders, seen: seen)
                }
            }, progress: { [weak self] state in
                let now = ContinuousClock.now
                let isDue = lastUpdate.withLock { last in
                    guard now - last >= .milliseconds(100) else { return false }
                    last = now
                    return true
                }
                Task { @MainActor in
                    guard let self, self.scanId == scanId, self.phase == .checking else { return }
                    // A group decided always lands; the bytes only when due.
                    if state.checkedFiles > self.checkedFiles { self.checkedFiles = state.checkedFiles }
                    if isDue || state.checkedFiles == state.totalFiles { self.bytesLeft = state.bytesLeft }
                }
            })
            try Task.checkCancellation()
            // The callbacks hop to the main actor; the result is the truth.
            allPhotos = found
            photos = CommonPhotosIncremental.newPhotos(found, folders: folders, seen: gathered.seen)
            checkedFiles = preview.candidateCount
            bytesLeft = 0
            phase = .done
            // A destination chosen while it scanned: cut to it now.
            if !listingWasCut, destination != scannedFor { recut() }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, self.scanId == scanId else { return }
            if (error as? RemoteFileError)?.stopsBatch == true { isConnected = false }
            failureError = error as? RemoteFileError
            phase = .failed((error as? RemoteFileError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// SHA-256 the index took of these very files (same path, size, write
    /// time), by file; empty without a database. Only hashes the index
    /// computed itself (`origin = 'hashed'`): a hash seeded from Backup's
    /// ledger was matched on path and size alone.
    private func knownHashes(_ preview: CommonPhotosMatcher.Preview, folders: [String]) async -> [CommonPhotosFile: String] {
        guard let database, !sources.isEmpty else { return [:] }
        let candidates = preview.groups.flatMap { $0.files.joined() }.filter { $0.modified != nil }
        guard !candidates.isEmpty else { return [:] }
        let sources = sources
        let rows: [String: (size: Int64, modifiedAt: Int?, sha256: String)] = (try? await database.reader.read { db in
            var out: [String: (Int64, Int?, String)] = [:]
            for source in sources {
                let found = try GRDB.Row.fetchAll(db, sql: """
                    SELECT f.size, f.modifiedAt, f.sha256,
                           CASE f.fileKey WHEN 'companion' THEN c.pairedPath ELSE c.relativePath END AS path
                    FROM copy_files f JOIN photo_copies c ON c.id = f.copyId
                    WHERE c.sourceId = ? AND c.kind = 'server' AND c.missingSince IS NULL
                      AND f.sha256 IS NOT NULL AND f.origin = 'hashed'
                    """, arguments: [source.sourceId])
                for row in found {
                    guard let path: String = row["path"], let size: Int64 = row["size"] else { continue }
                    // The exact path: two names that differ only in case are
                    // two files on WebDAV and SFTP.
                    out[ServerUploadPath.join(ServerUploadPath.normalizedFolder(source.folder), path)] = (size, row["modifiedAt"], row["sha256"])
                }
            }
            return out
        }) ?? [:]
        var known: [CommonPhotosFile: String] = [:]
        for file in candidates {
            guard let row = rows[ServerUploadPath.join(folders[file.folder], file.relativePath)],
                  row.size == file.size, let modified = file.modified,
                  row.modifiedAt == Int(modified.timeIntervalSince1970) else { continue }
            known[file] = row.sha256
        }
        return known
    }

    // MARK: What earlier scans read (FS-19.08 §6c)

    private var scanRecordStore: CommonPhotosScanRecords? { database.map(CommonPhotosScanRecords.init) }

    private func path(of file: CommonPhotosFile, folders: [String]) -> String {
        ServerUploadPath.join(folders[file.folder], file.relativePath)
    }

    /// The whole results cut to what the current destination's set has not
    /// gathered — every photo again for one that never did, or for Scan
    /// Everything. The latest choice wins; until it lands, no run.
    private func recut() {
        cutTask?.cancel()
        let scanId = scanId
        let folders = folders
        let destination = destination
        isCutting = true
        cutTask = Task { [weak self] in
            guard let self else { return }
            let gathered = scansEverything ? .init() : ((try? await gathered(folders: folders, destination: destination)) ?? .init())
            guard !Task.isCancelled, self.scanId == scanId, self.destination == destination else { return }
            photos = CommonPhotosIncremental.newPhotos(allPhotos, folders: folders, seen: gathered.seen)
            lastGathered = gathered.lastAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            alreadyGathered = gathered.photoCount
            isCutting = false
        }
    }

    /// What the set gathered before, against what its destination holds
    /// now: a photo whose copy left it is gathered again (§6c). A
    /// destination that cannot be listed counts nothing as gathered: better
    /// a photo checked twice than one left out (Copy skips the bytes already
    /// there). Cancellation goes through.
    private func gathered(folders: [String], destination: String?) async throws -> CommonPhotosStore.Gathered {
        guard let database, let destination else { return .init() }
        let store = CommonPhotosStore(database: database)
        let connectionId = connectionId
        guard let entries = try await destinationEntries(destination) else { return .init() }
        // A database that cannot say what was gathered fails the scan:
        // taking it as "nothing gathered" would gather everything again.
        return try await Task.detached {
            // The name → sizes map is built here, off the main actor.
            var present: [String: Set<Int64>] = [:]
            for entry in entries { present[entry.name.lowercased(), default: []].insert(entry.size) }
            return try store.gathered(connectionId: connectionId, folders: folders, destination: destination, inDestination: present)
        }.value
    }

    /// The destination's files. Empty when the folder is not there yet; one
    /// reconnect when the session went away while the sheet sat idle; nil
    /// when it still cannot be listed.
    private func destinationEntries(_ destination: String) async throws -> [RemoteEntry]? {
        for attempt in 0..<2 {
            do {
                if !isConnected {
                    try await client.connect()
                    isConnected = true
                }
                return try await client.entries(in: destination).filter { !$0.isDirectory }
            } catch RemoteFileError.folderMissing {
                return []
            } catch let error as RemoteFileError where error.stopsBatch && attempt == 0 {
                isConnected = false
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                Self.logger.notice("destination not listed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        return nil
    }

    /// Earlier scans' records of the listed files that still match them —
    /// same size and write time; a file with no write time has none.
    private func scanRecords(_ listing: CommonPhotosScanner.Listing, folders: [String]) async -> [CommonPhotosFile: CommonPhotosScanRecord] {
        guard let store = scanRecordStore else { return [:] }
        let files = listing.files.joined().filter { $0.modified != nil }
        let paths = files.map { path(of: $0, folders: folders) }
        let connectionId = connectionId
        let byPath = (try? await Task.detached { try store.records(connectionId: connectionId, paths: paths) }.value) ?? [:]
        var out: [CommonPhotosFile: CommonPhotosScanRecord] = [:]
        for (file, path) in zip(files, paths) {
            guard let record = byPath[path], let modified = file.modified, record.size == file.size,
                  record.modifiedAt == Int(modified.timeIntervalSince1970) else { continue }
            out[file] = record
        }
        return out
    }

    /// Saves what this scan read, for the next one — built and written off
    /// the main actor.
    private func remember(hashes: [CommonPhotosFile: String], keys: [CommonPhotosFile: String], folders: [String]) {
        guard let store = scanRecordStore, !hashes.isEmpty || !keys.isEmpty else { return }
        let connectionId = connectionId
        let previous = saving
        saving = Task.detached {
            await previous?.value
            var records: [String: CommonPhotosScanRecord] = [:]
            for file in Set(hashes.keys).union(keys.keys) {
                guard let modified = file.modified else { continue }
                let path = ServerUploadPath.join(folders[file.folder], file.relativePath)
                records[path] = CommonPhotosScanRecord(path: path, size: file.size, modifiedAt: Int(modified.timeIntervalSince1970),
                                                       sha256: hashes[file], captureKey: keys[file])
            }
            do { try store.save(connectionId: connectionId, Array(records.values)) } catch {
                Self.logger.error("scan records not saved: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Drops what earlier scans read of files these folders no longer hold.
    private func forget(notIn listing: CommonPhotosScanner.Listing, folders: [String]) async {
        guard let store = scanRecordStore else { return }
        let connectionId = connectionId
        let listed = zip(folders, listing.files).map { folder, files in
            (folder, Set(files.map { ServerUploadPath.join(folder, $0.relativePath) }))
        }
        await Task.detached {
            for (folder, paths) in listed {
                do { try store.prune(connectionId: connectionId, under: folder, keeping: paths) } catch {
                    Self.logger.error("scan records not pruned: \(error.localizedDescription, privacy: .public)")
                }
            }
        }.value
    }

    // MARK: Run

    /// The run and its items for `CommonPhotosStore.start`: one item per Same
    /// photo, sidecars and all. Nil until it can run.
    func makeRun() -> (run: CommonPhotosRun, items: [CommonPhotosItem])? {
        guard canRun, let destination, let listing else { return nil }
        let run = CommonPhotosRun(connectionId: connectionId, folders: folders, destination: destination, action: action)
        let items = CommonPhotosRunner.items(for: photos, runId: run.id, folders: folders,
                                             files: listing.files, sidecars: listing.sidecars)
        return (run, items)
    }

    private static func unique(_ folders: [String]) -> [String] {
        var seen = Set<String>()
        return folders.filter { seen.insert($0.lowercased()).inserted }
    }
}

/// The scan's client: counts the files each listing call returns (the
/// "Listing… N files" line) and, only for a screenshot of a scan half done,
/// waits before each read.
private final class WatchedClient: RemoteFileClient, @unchecked Sendable {
    let base: any RemoteFileClient
    let delay: Duration?
    let listed: @Sendable (Int) -> Void

    init(base: any RemoteFileClient, delay: Duration?, listed: @escaping @Sendable (Int) -> Void) {
        self.base = base
        self.delay = delay
        self.listed = listed
    }

    private func wait() async throws {
        if let delay { try await Task.sleep(for: delay) }
    }

    func connect() async throws { try await base.connect() }
    func disconnect() async { await base.disconnect() }
    func fileSize(at path: String) async throws -> Int64? { try await base.fileSize(at: path) }
    func directoryExists(_ path: String) async throws -> Bool { try await base.directoryExists(path) }
    func fileNames(in directory: String) async throws -> Set<String> { try await base.fileNames(in: directory) }
    func folderNames(in directory: String) async throws -> Set<String> { try await base.folderNames(in: directory) }
    func createDirectory(_ path: String) async throws { try await base.createDirectory(path) }
    func upload(_ localURL: URL, to path: String, progress: @escaping @Sendable (Int64) -> Void) async throws {
        try await base.upload(localURL, to: path, progress: progress)
    }
    func sha256(of path: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        try await wait()
        return try await base.sha256(of: path, progress: progress)
    }
    func entries(in directory: String) async throws -> [RemoteEntry] {
        let entries = try await base.entries(in: directory)
        listed(entries.filter { !$0.isDirectory }.count)
        return entries
    }
    func readRange(_ path: String, offset: Int64, length: Int) async throws -> Data {
        try await wait()
        return try await base.readRange(path, offset: offset, length: length)
    }
    func download(_ path: String, to localURL: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        try await base.download(path, to: localURL, progress: progress)
    }
    func move(_ source: String, to destination: String) async throws { try await base.move(source, to: destination) }
    func remove(_ path: String) async throws { try await base.remove(path) }
    func removeEmptyDirectory(_ path: String) async throws { try await base.removeEmptyDirectory(path) }
    func storageSpace(at path: String) async throws -> StorageSpace? { try await base.storageSpace(at: path) }
}
