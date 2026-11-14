import Foundation
import GRDB
import Observation

/// Every source the library reads, for Settings › Sources and the Sources
/// group in Collections (FS-19.01 §1, FS-19.01b §1).
@MainActor
@Observable
final class SourcesModel {
    struct Row: Identifiable, Equatable {
        let id: String
        let name: String
        let text: SourceRowText
    }

    private(set) var rows: [Row] = []
    /// A source being added or read: its row shows progress, Add waits.
    private(set) var readingSourceId: String?
    /// The read in progress, or one paused (FS-19.01 §4): the grid's banner,
    /// the row's ring and the sidebar foot. Nil when nothing is being read.
    private(set) var readProgress: SourceReadProgress? {
        didSet {
            let running = readProgress.map { !$0.isPaused && !$0.isDisconnected } ?? false
            if running != isReadRunning { isReadRunning = running }
            if (readProgress != nil) != hasReadProgress { hasReadProgress = readProgress != nil }
            let reading = readProgress.flatMap { $0.isPaused || $0.isDisconnected ? nil : $0.sourceId }
            if reading != readSourceId { readSourceId = reading }
        }
    }
    /// A read is shown at all (running, paused or cut off) — changes only
    /// when one starts or is let go.
    private(set) var hasReadProgress = false
    /// The source being read now (not paused): its sidebar row shows the ring.
    private(set) var readSourceId: String?
    /// A read is going (not paused): changes only at its start, pause and end,
    /// for views that must not redraw on every progress tick.
    private(set) var isReadRunning = false
    @ObservationIgnored private let readControl = SourceReadControl()
    /// Bumped after every read, so the grid and the tabs reload what changed.
    private(set) var readCount = 0
    /// Bumped when the grid's file-thumbnail index has been rebuilt off the
    /// main actor (launch), so the library redraws its server/folder tiles.
    private(set) var fileThumbnailsVersion = 0

    func fileThumbnailsReloaded() { fileThumbnailsVersion += 1 }
    /// Add, Remove… or Grant Access… did not go through; Settings says why.
    struct Failure: Equatable {
        var title: String
        var message: String

        static func error(_ message: String) -> Failure {
            Failure(title: String(localized: "Something Went Wrong", comment: "Sources: a step failed"), message: message)
        }
    }

    var failure: Failure?
    @ObservationIgnored private var isAdding = false

    @ObservationIgnored private let database: AppDatabase
    @ObservationIgnored private let runner: FolderSourceRunner
    @ObservationIgnored private let servers: ServerSourceRefresh
    @ObservationIgnored private let photoLibrary: PhotoLibraryService

    init(database: AppDatabase, runner: FolderSourceRunner, servers: ServerSourceRefresh, photoLibrary: PhotoLibraryService) {
        self.database = database
        self.runner = runner
        self.servers = servers
        self.photoLibrary = photoLibrary
    }

    /// Synchronous: the reads run on the caller. Tests only — on a 55k
    /// library the counts scan every copy, and the Collections tab called
    /// this on each appear, a hitch on every tab switch (iPad 2026-11-14).
    func load() {
        apply(Self.snapshot(database))
    }

    /// What screens call on appear: `reload()` in a task, one at a time; a
    /// request during a read runs once more after it.
    func refresh() {
        guard refreshTask == nil else {
            refreshesAgain = true
            return
        }
        refreshTask = Task {
            repeat {
                refreshesAgain = false
                await reload()
            } while refreshesAgain
            refreshTask = nil
        }
    }

    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshesAgain = false

    /// `load()` with the reads off the main actor — the read path runs it at a
    /// read's start and end, the moments a click is waiting (55k photos:
    /// counts and statuses scan every copy).
    func reload() async {
        let database = database
        apply(await Task.detached(priority: .userInitiated) { Self.snapshot(database) }.value)
    }

    private struct Snapshot: Sendable {
        var sources: [SourceStore.Source]
        var counts: [String: Int]
        var statuses: [String: (status: String?, lastRead: Int?, protocol: String?)]
    }

    nonisolated private static func snapshot(_ database: AppDatabase) -> Snapshot {
        let store = SourceStore(database: database)
        let statuses = (try? database.reader.read { db in
            Dictionary(uniqueKeysWithValues: try Row_.fetchAll(db, sql: """
                SELECT s.id, s.status, COALESCE(s.lastListedAt, (SELECT MAX(lastSeenAt) FROM photo_copies c WHERE c.sourceId = s.id)) AS lastRead,
                       (SELECT transferProtocol FROM file_servers f WHERE f.id = s.connectionId) AS protocol
                FROM sources s
                """).map { ($0["id"] as String, (status: $0["status"] as String?, lastRead: $0["lastRead"] as Int?,
                                                 protocol: $0["protocol"] as String?)) })
        }) ?? [:]
        return Snapshot(sources: (try? store.sources()) ?? [], counts: (try? store.photoCounts()) ?? [:], statuses: statuses)
    }

    private func apply(_ snapshot: Snapshot) {
        let sources = snapshot.sources, counts = snapshot.counts, statuses = snapshot.statuses
        let access = photoLibrary.authorizationState.title
        rows = sources.map { source in
            let info = statuses[source.id]
            let stored: SourceRowText.Status = switch info?.status {
            case "offline": .offline
            case "needsAccess": .needsAccess
            case "passwordRejected": .passwordRejected
            default: .online
            }
            let status: SourceRowText.Status = source.id == readingSourceId ? .reading(done: counts[source.id] ?? 0, total: 0) : stored
            let kind: SourceRowText.Kind = switch source.kind {
            case "photos": .photos
            case "drive": .drive
            case "server": .server(protocolName: info?.protocol.flatMap(FileServer.TransferProtocol.init(rawValue:))?.title ?? "SMB")
            default: Self.isICloudDrive(source.bookmark) ? .iCloudDrive : .onDevice
            }
            return Row(id: source.id, name: source.name, text: SourceRowText(
                kind: kind, status: status, count: counts[source.id] ?? 0,
                photosAccess: source.kind == "photos" ? access : nil,
                photosAccessIsFull: photoLibrary.authorizationState == .authorized,
                lastReadAt: source.kind == "photos" ? nil : info?.lastRead.map { Date(timeIntervalSince1970: TimeInterval($0)) }))
        }
    }

    /// Add Folder or Drive: the folder Files handed back is kept and read
    /// at once; its row shows the read going.
    func addFolder(_ url: URL, includesSubfolders: Bool, pairsRawAndJpeg: Bool) async {
        // One add or read at a time: two adds racing past the overlap check
        // would both insert, and a read refused would leave a row never read.
        guard readingSourceId == nil, !isAdding else {
            failure = Failure(title: String(localized: "Can’t Add This Folder", comment: "Sources: the folder overlaps a source"),
                              message: String(localized: "Wait for the current read to finish, then add the folder again.",
                                              comment: "Sources: add while a read runs"))
            return
        }
        isAdding = true
        defer { isAdding = false }
        // The same folder again, or one inside or around a source, is refused
        // (FS-19.01 §1, FS-18.04 §3 AC-73): every file would count twice.
        if let refusal = overlap(url) {
            failure = Failure(title: String(localized: "Can’t Add This Folder", comment: "Sources: the folder overlaps a source"),
                              message: refusal)
            return
        }
        let id: String
        do {
            id = try await runner.add(folder: url, includesSubfolders: includesSubfolders, pairsRawAndJpeg: pairsRawAndJpeg)
        } catch {
            failure = .error(String(localized: "ShotDex couldn’t read “\(url.lastPathComponent)”: \(error.localizedDescription)",
                                    comment: "Sources: adding a folder failed"))
            return
        }
        // A drive starts with what When a Drive Is Disconnected says (Mac Settings).
        if drivesWhenUnplugged == .hidePhotos,
           (try? SourceStore(database: database).sources())?.first(where: { $0.id == id })?.kind == "drive" {
            try? SourceStore(database: database).setWhenUnplugged(.hidePhotos, sourceId: id)
        }
        await read(sourceId: id, isAdding: true)
    }

    /// Pause on the read's banner: the file in hand finishes, what was read
    /// stays, and Resume reads only the rest (FS-19.01 §4).
    func pauseRead() {
        readControl.pause()
        // Paused at once on screen: the file in hand (a large RAW, a NAS)
        // may take seconds more, and Pause must not look broken meanwhile.
        if var progress = readProgress {
            progress.isPaused = true
            readProgress = progress
            Self.storePaused(progress)
        }
    }

    /// A paused read outlives the app (FS-19.01 §4): kept here, restored at
    /// launch, skipped by Read All until Resume.
    private static let pausedKey = "sources.pausedRead"

    private static func storePaused(_ progress: SourceReadProgress?) {
        if let progress, let data = try? JSONEncoder().encode(progress) {
            UserDefaults.standard.set(data, forKey: pausedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: pausedKey)
        }
    }

    /// The read paused before the last quit, shown paused again.
    func restorePausedRead() {
        guard readProgress == nil, let data = UserDefaults.standard.data(forKey: Self.pausedKey),
              var paused = try? JSONDecoder().decode(SourceReadProgress.self, from: data)
        else { return }
        paused.isPaused = true
        readProgress = paused
    }

    #if DEBUG
    /// The Mac demo's read in progress (board `MAC_SourceIndexing`): the
    /// banner and the foot without a real folder being read.
    func debugShowRead(_ progress: SourceReadProgress) {
        readProgress = progress
    }
    #endif

    /// Resume on a paused banner.
    func resumeRead() async {
        guard let paused = readProgress, paused.isPaused else { return }
        await read(sourceId: paused.sourceId, isAdding: paused.isAdding)
    }

    /// The close on the banner: a paused read is let go; one still running
    /// keeps its line in the sidebar foot.
    func dismissPausedRead() {
        if readProgress?.isPaused == true || readProgress?.isDisconnected == true {
            readProgress = nil
            Self.storePaused(nil)
        }
    }

    /// Mac Settings › Sources › When a Drive Is Disconnected (FS-19.01 §1):
    /// keep an unplugged drive's photos, marked offline, or hide them until it is back.
    var drivesWhenUnplugged: SourceStore.WhenUnplugged {
        UserDefaults.standard.string(forKey: SettingsKeys.whenDriveUnplugged).flatMap(SourceStore.WhenUnplugged.init(rawValue:))
            ?? .keepPhotos
    }

    /// Sets it for every drive there is and for drives added later.
    func setDrivesWhenUnplugged(_ choice: SourceStore.WhenUnplugged) {
        UserDefaults.standard.set(choice.rawValue, forKey: SettingsKeys.whenDriveUnplugged)
        let store = SourceStore(database: database)
        for source in (try? store.sources()) ?? [] where source.kind == "drive" {
            try? store.setWhenUnplugged(choice, sourceId: source.id)
        }
        readCount += 1
        refresh()
    }

    func read(sourceId: String, isAdding: Bool = false) async {
        // One read at a time: the runner refuses a second, and its nil must
        // not end the first one's progress on the row.
        guard readingSourceId == nil else { return }
        readingSourceId = sourceId
        let name = rows.first(where: { $0.id == sourceId })?.name
            ?? (try? SourceStore(database: database).sources())?.first(where: { $0.id == sourceId })?.name ?? ""
        // Resume carries on from the paused numbers, not from "0 of 0".
        if let paused = readProgress, paused.sourceId == sourceId, paused.isPaused || paused.isDisconnected {
            var resumed = paused
            resumed.isPaused = false
            resumed.isDisconnected = false
            readProgress = resumed
            Self.storePaused(nil)
        } else {
            readProgress = SourceReadProgress(sourceId: sourceId, sourceName: name, isAdding: isAdding)
        }
        readControl.reset()
        await reload()
        let control = readControl
        let summary = try? await runner.read(sourceId: sourceId, shouldContinue: { !control.isPaused }) { [weak self] done, total in
            guard control.shouldReport(done: done, total: total) else { return }
            Task { @MainActor in self?.readMoved(done: done, total: total, sourceId: sourceId) }
        }
        readingSourceId = nil
        // Paused: the banner stays with Resume. Drive gone mid-read: it
        // says so, with what was read. Otherwise the read is over.
        if summary?.paused == true, var paused = readProgress {
            paused.isPaused = true
            readProgress = paused
            Self.storePaused(paused)
        } else if summary?.disconnected == true, var cut = readProgress {
            cut.isDisconnected = true
            readProgress = cut
            Self.storePaused(cut)
        } else {
            readProgress = nil
        }
        readCount += 1
        await reload()
    }

    private func readMoved(done: Int, total: Int, sourceId: String) {
        // Reports hop over unordered: a late, smaller one is dropped, or the
        // estimate would start over ("Estimating time…" flickering back).
        guard var progress = readProgress, progress.sourceId == sourceId, !progress.isPaused,
              done > progress.done || total != progress.total
        else { return }
        progress.done = done
        progress.total = total
        progress.estimate.record(processed: done)
        readProgress = progress
    }

    /// A connection's Add as Source switch, after its form saved (FS-19.03
    /// §1): on adds the source and reads it now; off removes it — its
    /// photos leave ShotDex, nothing on the server is touched.
    func setServerSource(_ isSource: Bool, connection: FileServer) async {
        let store = SourceStore(database: database)
        let existing = try? store.serverSourceId(connectionId: connection.id)
        if isSource, existing ?? nil == nil {
            guard let id = try? store.addServer(name: connection.name, connectionId: connection.id) else { return }
            readingSourceId = id
            await reload()
            _ = await servers.rescan(sourceId: id)
            readingSourceId = nil
            readCount += 1
        } else if !isSource, let id = existing ?? nil {
            try? store.remove(sourceId: id)
            readCount += 1
        }
        await reload()
    }

    /// Remove… (Mac Settings › Sources, FS-18.04 §3 AC-72): the source's
    /// photos leave ShotDex unless another source holds a copy; nothing in
    /// the folder, on the drive or on the server is touched.
    func remove(sourceId: String) async {
        let database = database
        do {
            // Marks every copy missing: off the main actor for a 50,000-photo source.
            try await Task.detached { try SourceStore(database: database).remove(sourceId: sourceId) }.value
        } catch {
            failure = .error(String(localized: "ShotDex could not remove the source: \(error.localizedDescription)",
                                    comment: "Sources: Remove failed"))
        }
        readCount += 1
        await reload()
    }

    /// Grant Access…: the folder picked again; its files are read back to
    /// the same photos (FS-19.01b §2).
    func grantAccess(sourceId: String, folder: URL) async {
        do {
            try FolderSourceAccess(database: database).grant(sourceId: sourceId, folder: folder)
        } catch {
            failure = .error(String(localized: "ShotDex could not keep access to “\(folder.lastPathComponent)”: \(error.localizedDescription)",
                                    comment: "Sources: Grant Access failed"))
            await reload()
            return
        }
        await read(sourceId: sourceId)
    }

    /// Why a drop on Settings › Sources is not taken: one folder at a time,
    /// not a file, not while a read goes (FS-18.04 §3 AC-73).
    nonisolated static func dropRefusal(_ urls: [URL], isReading: Bool) -> String? {
        if isReading {
            return String(localized: "Wait for the current read to finish, then drop the folder again.", comment: "Sources: drop while reading")
        }
        guard urls.count == 1, let url = urls.first else {
            return String(localized: "Drop one folder at a time.", comment: "Sources: several items dropped")
        }
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            return String(localized: "“\(url.lastPathComponent)” is a file. Drop the folder that holds it.", comment: "Sources: a file dropped")
        }
        return nil
    }

    /// Why `folder` cannot be added — it is a source already, or inside or
    /// around one — or nil when it can.
    func overlap(_ folder: URL) -> String? {
        // A folder that lost access keeps the path it had; a new folder there
        // is not that source.
        let lost = Set(rows.filter { $0.text.status == .needsAccess }.map(\.id))
        let existing = ((try? SourceStore(database: database).sources()) ?? []).filter { !lost.contains($0.id) }.compactMap { source in
            Self.path(of: source.bookmark).map { SourceOverlap.Existing(name: source.name, path: $0.path) }
        }
        return SourceOverlap.check(folder.path, against: existing).message
    }

    /// Where a folder source was last seen, from its bookmark, for Grant
    /// Access…'s panel to open next to it; nil when the bookmark says nothing.
    func lastKnownPath(sourceId: String) -> URL? {
        Self.path(of: (try? SourceStore(database: database).sources())?.first { $0.id == sourceId }?.bookmark)
    }

    /// The path a bookmark records, read without opening it (no scope needed).
    private static func path(of bookmark: Data?) -> URL? {
        guard let bookmark, let path = URL.resourceValues(forKeys: [.pathKey], fromBookmarkData: bookmark)?.path else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// A deletion through the sources from a screen with no grid of its own
    /// behind it (Cull): the Library reloads what went, the rows recount.
    func photosDeleted() {
        readCount += 1
        refresh()
    }

    /// A file opened from the cloud is down and read (FS-19.01b §4): the
    /// grid swaps its cloud tile for the photo, the rows recount.
    func cloudFileDownloaded() {
        readCount += 1
        refresh()
    }

    /// Rescan in a server source's browser, or Try Again on its row.
    func rescanServer(sourceId: String) async {
        if let summary = await servers.rescan(sourceId: sourceId), summary.photos > 0 { readCount += 1 }
        await reload()
    }

    /// On launch and each return to the foreground (FS-19.01 §5): what
    /// changed while ShotDex was away, read without a Re-index.
    func readAll() async {
        #if DEBUG
        await addSeededFolder()
        #endif
        // Only a read that changed something reloads the grid: a reload under
        // an open viewer would take it away.
        // A read paused by the user stays paused until Resume (FS-19.01 §4).
        let paused = readProgress.flatMap { $0.isPaused || $0.isDisconnected ? $0.sourceId : nil }
        if await runner.readAll(skipping: paused.map { [$0] } ?? []) { readCount += 1 }
        // Servers are listed by the on-server check, within each
        // connection's Backup rules (FS-19.07 §6): `serverListingChanged`.
        await reload()
    }

    /// A server source's listing found new or changed photos.
    func serverListingChanged() {
        readCount += 1
        refresh()
    }

    #if DEBUG
    /// `-ShotDexSeedFolderSource Kyoto`: adds Documents/Kyoto of the app's own
    /// container as a folder source, once — the step a UI script cannot take
    /// in Files' picker, which runs outside the app.
    static let seedArgument = "-ShotDexSeedFolderSource"

    private func addSeededFolder() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: Self.seedArgument), index + 1 < arguments.count else { return }
        let name = arguments[index + 1]
        guard !((try? SourceStore(database: database).sources()) ?? []).contains(where: { $0.name == name }),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = documents.appendingPathComponent(name, isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        _ = try? await runner.add(folder: folder, includesSubfolders: true, pairsRawAndJpeg: true)
    }
    #endif

    private static func isICloudDrive(_ bookmark: Data?) -> Bool {
        var stale = false
        guard let bookmark, let url = try? SourceBookmark.resolve(bookmark, isStale: &stale) else { return false }
        return url.path.contains("/Mobile Documents/")
    }
}

private typealias Row_ = GRDB.Row
