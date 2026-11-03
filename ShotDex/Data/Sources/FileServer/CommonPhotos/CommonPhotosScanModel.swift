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
    var destination: String?
    var action = CommonPhotosRun.Action.copy
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
    var canRun: Bool { phase == .done && problem == nil && !photos.isEmpty }

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

    func scan() {
        guard canScan else { return }
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
    }

    private func runScan() async {
        let folders = folders
        let scanId = UUID()
        self.scanId = scanId
        phase = .listing
        preview = nil
        photos = []
        listedFiles = 0
        checkedFiles = 0
        bytesLeft = 0
        // Ten updates a second at most: a big file's hash reports often.
        let lastUpdate = OSAllocatedUnfairLock(initialState: ContinuousClock.now - .seconds(1))
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
            fileCounts = Dictionary(uniqueKeysWithValues: zip(folders, listing.files.map(\.count)))
            // What size and name say, shown at once; the heads refine it.
            let firstLook = CommonPhotosMatcher.preview(listing.files)
            preview = firstLook
            bytesLeft = firstLook.candidateBytes
            phase = .checking
            let groups = CommonPhotosMatcher.sizeGroups(listing.files)
            let keys = try await scanner.captureKeys(for: groups, folders: folders)
            try Task.checkCancellation()
            let preview = CommonPhotosMatcher.preview(listing.files, captureKeys: keys)
            self.preview = preview
            let known = await knownHashes(preview, folders: folders)
            let found = try await CommonPhotosVerifier(client: watched).verify(preview, folders: folders, knownHashes: known, found: { [weak self] batch in
                Task { @MainActor in
                    guard let self, self.scanId == scanId, self.phase == .checking else { return }
                    self.photos += batch
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
            photos = found
            checkedFiles = preview.candidateCount
            bytesLeft = 0
            phase = .done
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, self.scanId == scanId else { return }
            if (error as? RemoteFileError)?.stopsBatch == true { isConnected = false }
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
