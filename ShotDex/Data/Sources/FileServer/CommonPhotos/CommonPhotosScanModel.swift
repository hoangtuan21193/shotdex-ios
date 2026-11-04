import Foundation
import GRDB
import Observation
import os

/// What the Find Common Photos sheet holds (FS-19.08 §4–5, board
/// `MAC_CommonPhotos`): the folders and where the common photos go, Copy or
/// Move, and the scan — the listing, the size and Likely sort that orders
/// the reads, then the SHA-256 check that makes each photo Same (§6d: only
/// Same photos are rows). The sheet draws this; the
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

    /// One row of the results: a photo proven Same (§6d — rows still being
    /// checked are only counted, never listed).
    struct Row: Identifiable, Equatable {
        let id: String
        let name: String
        /// Folder and subfolder in each folder, "Tuan/2025/06 · Vo/from-tuan",
        /// and "as <name>" where the name differs from the first.
        let paths: String
        /// Every copy's whole path below its folder, for the tooltip.
        let fullPaths: String
        let size: Int64
        /// What it becomes in the destination (§6d); nil until the
        /// destination is chosen and listed.
        let landing: CommonPhotosDestinationPlan.Landing?
        /// Every copy in the source folders — what a Move removes.
        let copies: Int
        let sha256: String
        /// Checked: the run takes it (§6d). Unchecked: left out.
        let isIncluded: Bool
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
            // Another set, another Left Out (§6d).
            loadLeftOut()
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
    /// Lists the destination and works out each photo's landing (§6d).
    private var planTask: Task<Void, Never>?
    /// A plan is being worked out (the destination listed, a few files read).
    private(set) var isPlanning = false
    /// Each Same photo's landing, by row id; empty until planned.
    private(set) var landings: [String: CommonPhotosDestinationPlan.Landing] = [:]
    /// Destination SHA-256 read for a plan, by lowercased path, while its
    /// size and write time hold: a flip back to a destination reads nothing again.
    private var destinationHashes: [String: (size: Int64, modified: Date, sha256: String)] = [:]
    /// What the set's runs put in the destination (`Gathered.placed`): the
    /// plan takes those bytes as known, so a rescan reads nothing (AC-159).
    private var placedInDestination: [String: CommonPhotosStore.Placed] = [:]
    /// The helper's pass (`scanToEnd`) shows no rows: it plans nothing.
    private var plansDestination = true
    /// Results are being cut to the destination chosen: not runnable yet.
    private(set) var isCutting = false
    private(set) var phase = Phase.idle
    private(set) var preview: CommonPhotosMatcher.Preview?
    private(set) var photos: [CommonPhoto] = []
    /// Files listed so far, while listing.
    private(set) var listedFiles = 0
    /// First-folder candidates the verifier has decided; Checking and Not
    /// checked are counted from it.
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
        // Another set: its own Left Out; what was unchecked was of the old one.
        leftOutPending = [:]
        loadLeftOut()
    }

    func remove(folder: String) {
        folders.removeAll { $0 == folder }
        resetScan()
        leftOutPending = [:]
        loadLeftOut()
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
        // Rows already in the destination still run on a Copy (recorded as
        // there, a missing sidecar added — §6), though the button leaves them
        // out of its count.
        phase == .done && !isCutting && problem == nil && !includedPhotos.isEmpty && !(action == .move && scannedTrustingCache)
    }

    /// Photos the user left out, by SHA-256 (§6d): the run never touches them.
    /// Stored for the set (`CommonPhotosLeftOutStore`) once it has a
    /// destination; before that, kept here and stored when one is chosen.
    private(set) var leftOut: Set<String> = []
    /// Left out by an earlier sheet: listed under Left Out, not as rows.
    private(set) var leftOutBefore: Set<String> = []
    /// The set's Left Out list, as stored.
    private(set) var leftOutEntries: [CommonPhotosLeftOutStore.Entry] = []
    /// Unchecked with no destination yet: no set to store them in.
    private var leftOutPending: [String: CommonPhotosLeftOutStore.Photo] = [:]

    /// The set the sheet gathers, once it has a destination.
    var setKey: String? {
        destination.map { CommonPhotosIncremental.setKey(connectionId: connectionId, folders: folders, destination: $0) }
    }

    private var leftOutStore: CommonPhotosLeftOutStore? { database.map(CommonPhotosLeftOutStore.init) }

    /// Checks or unchecks rows; ids from `rows`. Unchecked is stored for the
    /// set at once: every later scan, Run Again and Keep gathering skips it.
    func setIncluded(_ included: Bool, rows ids: Set<String>) {
        let chosen = rows.filter { ids.contains($0.id) }
        let shas = Set(chosen.map(\.sha256))
        if included {
            leftOut.subtract(shas)
            shas.forEach { leftOutPending[$0] = nil }
            if let setKey { record { try $0.include(shas, setKey: setKey) } }
        } else {
            leftOut.formUnion(shas)
            let photos = chosen.map { CommonPhotosLeftOutStore.Photo(sha256: $0.sha256, name: $0.name, size: $0.size) }
            if let setKey {
                record { try $0.leaveOut(photos, setKey: setKey, connectionId: connectionId) }
            } else {
                photos.forEach { leftOutPending[$0.sha256] = $0 }
            }
        }
        reloadLeftOutEntries()
    }

    /// Include from the Left Out list: back as a row, checked, from the
    /// next scan on (and now, when this scan found it).
    func include(_ entries: Set<String>) {
        leftOut.subtract(entries)
        leftOutBefore.subtract(entries)
        if let setKey { record { try $0.include(entries, setKey: setKey) } }
        reloadLeftOutEntries()
        // Found by this scan: a row again, with its place in the plan.
        if phase == .done, photos.contains(where: { entries.contains($0.sha256) }) { replan() }
    }

    /// The set's stored Left Out, as the scan begins or the destination
    /// changes; what was unchecked before a destination is stored now.
    private func loadLeftOut() {
        guard let setKey, let store = leftOutStore else {
            // No set: only what was unchecked in this sheet stays out.
            leftOut = Set(leftOutPending.keys)
            leftOutBefore = []
            leftOutEntries = []
            return
        }
        let pending = Array(leftOutPending.values)
        // Kept until stored: a failed write leaves them pending for the next set.
        if record({ try $0.leaveOut(pending, setKey: setKey, connectionId: connectionId) }) { leftOutPending = [:] }
        let stored = Set(((try? store.entries(setKey: setKey)) ?? []).map(\.sha256))
        // Pending ones that could not be stored still stay out in this sheet.
        leftOut = stored.union(leftOutPending.keys)
        leftOutBefore = stored.subtracting(pending.map(\.sha256))
        reloadLeftOutEntries()
    }

    private func reloadLeftOutEntries() {
        guard let setKey, let store = leftOutStore else { leftOutEntries = []; return }
        // Unchecked in this sheet: still a row; the list holds the earlier ones.
        let found = Set(photos.map(\.sha256))
        leftOutEntries = ((try? store.entries(setKey: setKey)) ?? []).filter { entry in
            leftOutBefore.contains(entry.sha256) || !found.contains(entry.sha256)
        }
    }

    /// A write to the Left Out table; a failure is logged, the choice still
    /// holds in this sheet.
    @discardableResult
    private func record(_ write: (CommonPhotosLeftOutStore) throws -> Void) -> Bool {
        guard let store = leftOutStore else { return false }
        do {
            try write(store)
            return true
        } catch {
            Self.logger.error("left out not stored: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// The Same photos the run takes.
    var includedPhotos: [CommonPhoto] { photos.filter { !leftOut.contains($0.sha256) } }

    /// Every Same photo this scan proved, listed or left out before — what
    /// "confirmed so far" counts against the candidates.
    var confirmedCount: Int { photos.count }

    /// The Same photos listed as rows: not those left out by an earlier sheet.
    private var listed: [CommonPhoto] { photos.filter { !leftOutBefore.contains($0.sha256) } }

    /// Whether some source shows what lands in the destination.
    var isDestinationIndexed: Bool {
        guard let destination, let connection = sources.first?.connection else { return true }
        return CommonPhotosSources.isIndexed(destination, on: connection, sources: sources)
    }

    // MARK: Counts

    /// Same rows (Left Out from before not counted: they are listed apart).
    var sameCount: Int { listed.count }

    /// First-folder candidates still to decide.
    var candidateCount: Int { preview?.candidateCount ?? 0 }

    var checkingCount: Int { isScanning ? max(0, candidateCount - checkedFiles) : 0 }

    /// First-folder candidates a failed scan never reached.
    var notCheckedCount: Int { failure != nil ? max(0, candidateCount - checkedFiles) : 0 }

    var sameBytes: Int64 { listed.reduce(Int64(0)) { $0 + $1.size } }

    /// What the run button counts (§6d): a Copy skips the photos already in
    /// the destination; a Move still takes every copy out of the folders.
    var runCount: Int { runnable.filter { !leftOut.contains($0.sha256) }.count }

    /// Rows the user can check or uncheck: a Copy skips what is already in
    /// the destination, so those rows are not choices on a Copy.
    var selectableCount: Int { runnable.count }

    /// Bytes of what the run writes or moves.
    var runBytes: Int64 { runnable.filter { !leftOut.contains($0.sha256) }.reduce(Int64(0)) { $0 + $1.size } }

    private var runnable: [CommonPhoto] {
        guard action == .copy else { return listed }
        return listed.filter { photo in
            if case .alreadyThere? = landings[Self.rowId(photo.files[0][0])] { false } else { true }
        }
    }

    /// Same photos whose bytes the destination already holds (§6d).
    var alreadyThereCount: Int {
        landings.values.filter { if case .alreadyThere = $0 { true } else { false } }.count
    }

    /// The Same photos, in the order found (§6d: Same only).
    var rows: [Row] {
        guard preview != nil else { return [] }
        return listed.map { photo in
            row(photo.files.map { $0[0] }, size: photo.size, copies: photo.files.joined().count, sha256: photo.sha256)
        }
    }

    private static func rowId(_ first: CommonPhotosFile) -> String { "\(first.folder)/\(first.relativePath)" }

    /// The Same photo behind a row (§6d: what Compare shows).
    func photo(forRow id: String) -> CommonPhoto? {
        photos.first { Self.rowId($0.files[0][0]) == id }
    }

    private func row(_ files: [CommonPhotosFile], size: Int64, copies: Int, sha256: String) -> Row {
        let first = files[0]
        let paths = files.map { file -> String in
            var place = ServerUploadPath.join(ServerUploadPath.lastComponent(of: folders[file.folder]), file.subfolder)
            if file.comparableName != first.comparableName { place += " as " + file.name }
            return place
        }
        let fullPaths = files.map { ServerUploadPath.join(ServerUploadPath.lastComponent(of: folders[$0.folder]), $0.relativePath) }
        let id = Self.rowId(first)
        return Row(id: id, name: first.name, paths: paths.joined(separator: " · "),
                   fullPaths: fullPaths.joined(separator: "\n"), size: size, landing: landings[id], copies: copies,
                   sha256: sha256, isIncluded: !leftOut.contains(sha256),
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
        plansDestination = false
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
        planTask?.cancel()
        planTask = nil
        landings = [:]
        isPlanning = false
        placedInDestination = [:]
    }

    private func runScan() async {
        let folders = folders
        let scanId = UUID()
        self.scanId = scanId
        // A cut or plan of the last results means nothing to this scan.
        cutTask?.cancel()
        cutTask = nil
        isCutting = false
        planTask?.cancel()
        landings = [:]
        isPlanning = false
        loadLeftOut()
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
        // What the verifier decided and found, kept off the main actor: a
        // failure can land before the callbacks' hops do (§6d: the list and
        // "Not checked" must hold every group decided).
        let decided = OSAllocatedUnfairLock(initialState: 0)
        let foundSoFar = OSAllocatedUnfairLock(initialState: [CommonPhoto]())
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
            placedInDestination = gathered.placed
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
                let fresh = CommonPhotosIncremental.newPhotos(batch, folders: folders, seen: seen)
                foundSoFar.withLock { $0 += fresh }
                Task { @MainActor in
                    guard let self, self.scanId == scanId, self.phase == .checking else { return }
                    self.photos += fresh
                }
            }, progress: { [weak self] state in
                decided.withLock { $0 = max($0, state.checkedFiles) }
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
            // A newer scan took over (one not run through scanTask cannot be cancelled).
            guard self.scanId == scanId else { return }
            // The callbacks hop to the main actor; the result is the truth.
            allPhotos = found
            photos = CommonPhotosIncremental.newPhotos(found, folders: folders, seen: gathered.seen)
            checkedFiles = preview.candidateCount
            bytesLeft = 0
            phase = .done
            // A destination chosen while it scanned: cut to it now.
            if destination != scannedFor {
                // Changed while it listed, after the listing was cut for the
                // old set: this set's photos were never read — scan again.
                if listingWasCut {
                    resetScan()
                    notice = .otherDestination
                    return
                }
                recut()
            } else {
                replan()
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, self.scanId == scanId else { return }
            if (error as? RemoteFileError)?.stopsBatch == true { isConnected = false }
            photos = foundSoFar.withLock { $0 }
            checkedFiles = max(checkedFiles, decided.withLock { $0 })
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
        // The old destination's plan must not show beside the new one.
        planTask?.cancel()
        planTask = nil
        landings = [:]
        isPlanning = false
        cutTask = Task { [weak self] in
            guard let self else { return }
            let gathered = scansEverything ? .init() : ((try? await gathered(folders: folders, destination: destination)) ?? .init())
            guard !Task.isCancelled, self.scanId == scanId, self.destination == destination else { return }
            photos = CommonPhotosIncremental.newPhotos(allPhotos, folders: folders, seen: gathered.seen)
            lastGathered = gathered.lastAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            alreadyGathered = gathered.photoCount
            placedInDestination = gathered.placed
            isCutting = false
            replan()
        }
    }

    /// Lists the destination and works out what each Same photo becomes
    /// there (§6d), reading only the files a landing hangs on — same name
    /// and size as a photo. A destination that cannot be listed leaves the
    /// rows without a plan; the run names them anyway.
    private func replan() {
        reloadLeftOutEntries()
        planTask?.cancel()
        landings = [:]
        isPlanning = false
        // The rows only: a photo left out before claims no name in the plan.
        let photos = listed
        guard plansDestination, let destination, !photos.isEmpty else { return }
        let scanId = scanId
        isPlanning = true
        planTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.scanId == scanId, self.destination == destination, !Task.isCancelled { self.isPlanning = false } }
            guard let entries = try? await destinationEntries(destination) else { return }
            let planned = photos.map {
                CommonPhotosDestinationPlan.Photo(name: $0.files[0][0].name, size: $0.size, sha256: $0.sha256)
            }
            let key = { (name: String) in ServerUploadPath.join(destination, name).lowercased() }
            var existing = entries.map { entry in
                let known = self.destinationHashes[key(entry.name)]
                let holds = known != nil && known?.size == entry.size && entry.modified != nil && known?.modified == entry.modified
                let placed = self.placedInDestination[entry.name.lowercased()].flatMap { $0.size == entry.size ? $0.sha256 : nil }
                return CommonPhotosDestinationPlan.Existing(name: entry.name, size: entry.size,
                                                            sha256: holds ? known?.sha256 : placed)
            }
            let modified = Dictionary(entries.map { ($0.name, $0.modified) }, uniquingKeysWith: { first, _ in first })
            // A file that would decide a row but could not be read: that row
            // gets no plan rather than a guess the run would contradict.
            var unread = Set<String>()
            for there in CommonPhotosDestinationPlan.toHash(planned, in: existing) {
                // Unread, it stays a name taken by other bytes: the plan
                // shows the next free name, the run checks again.
                let sha: String
                do {
                    sha = try await client.sha256(of: ServerUploadPath.join(destination, there.name), progress: { _ in })
                    try Task.checkCancellation()
                } catch is CancellationError {
                    return
                } catch {
                    if Task.isCancelled { return }
                    unread.insert(there.name.lowercased())
                    continue
                }
                if let index = existing.firstIndex(where: { $0.name == there.name }) { existing[index].sha256 = sha }
                if let date = modified[there.name] ?? nil { destinationHashes[key(there.name)] = (there.size, date, sha) }
            }
            guard !Task.isCancelled, self.scanId == scanId, self.destination == destination else { return }
            let landings = CommonPhotosDestinationPlan.landings(planned, in: existing)
            var byRow: [String: CommonPhotosDestinationPlan.Landing] = [:]
            for (index, landing) in landings.enumerated() where !unread.contains(planned[index].name.lowercased()) {
                let id = Self.rowId(photos[index].files[0][0])
                if byRow[id] == nil { byRow[id] = landing }
            }
            self.landings = byRow
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
            // A cancelled caller (the sheet closed) never reconnects.
            try Task.checkCancellation()
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
        let items = CommonPhotosRunner.items(for: includedPhotos, runId: run.id, folders: folders,
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
