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
    /// Bumped after every read, so the grid and the tabs reload what changed.
    private(set) var readCount = 0
    /// Remove… or Grant Access… did not go through; Settings says so.
    var failure: String?

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

    func load() {
        let store = SourceStore(database: database)
        let sources = (try? store.sources()) ?? []
        let counts = (try? store.photoCounts()) ?? [:]
        let statuses = (try? database.reader.read { db in
            Dictionary(uniqueKeysWithValues: try Row_.fetchAll(db, sql: """
                SELECT s.id, s.status, (SELECT MAX(lastSeenAt) FROM photo_copies c WHERE c.sourceId = s.id) AS lastRead,
                       (SELECT transferProtocol FROM file_servers f WHERE f.id = s.connectionId) AS protocol
                FROM sources s
                """).map { ($0["id"] as String, (status: $0["status"] as String?, lastRead: $0["lastRead"] as Int?,
                                                 protocol: $0["protocol"] as String?)) })
        }) ?? [:]
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
        guard let id = try? await runner.add(folder: url, includesSubfolders: includesSubfolders, pairsRawAndJpeg: pairsRawAndJpeg) else { return }
        await read(sourceId: id)
    }

    func read(sourceId: String) async {
        // One read at a time: the runner refuses a second, and its nil must
        // not end the first one's progress on the row.
        guard readingSourceId == nil else { return }
        readingSourceId = sourceId
        load()
        _ = try? await runner.read(sourceId: sourceId)
        readingSourceId = nil
        readCount += 1
        load()
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
            load()
            _ = await servers.rescan(sourceId: id)
            readingSourceId = nil
            readCount += 1
        } else if !isSource, let id = existing ?? nil {
            try? store.remove(sourceId: id)
            readCount += 1
        }
        load()
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
            failure = String(localized: "ShotDex could not remove the source: \(error.localizedDescription)",
                             comment: "Sources: Remove failed")
        }
        readCount += 1
        load()
    }

    /// Grant Access…: the folder picked again; its files are read back to
    /// the same photos (FS-19.01b §2).
    func grantAccess(sourceId: String, folder: URL) async {
        do {
            try FolderSourceAccess(database: database).grant(sourceId: sourceId, folder: folder)
        } catch {
            failure = String(localized: "ShotDex could not keep access to “\(folder.lastPathComponent)”: \(error.localizedDescription)",
                             comment: "Sources: Grant Access failed")
            load()
            return
        }
        await read(sourceId: sourceId)
    }

    /// Where a folder source was last seen, from its bookmark, for Grant
    /// Access…'s panel to open next to it; nil when the bookmark says nothing.
    func lastKnownPath(sourceId: String) -> URL? {
        guard let source = (try? SourceStore(database: database).sources())?.first(where: { $0.id == sourceId }),
              let bookmark = source.bookmark,
              let values = URL.resourceValues(forKeys: [.pathKey], fromBookmarkData: bookmark), let path = values.path else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// A deletion through the sources from a screen with no grid of its own
    /// behind it (Cull): the Library reloads what went, the rows recount.
    func photosDeleted() {
        readCount += 1
        load()
    }

    /// A file opened from the cloud is down and read (FS-19.01b §4): the
    /// grid swaps its cloud tile for the photo, the rows recount.
    func cloudFileDownloaded() {
        readCount += 1
        load()
    }

    /// Rescan in a server source's browser, or Try Again on its row.
    func rescanServer(sourceId: String) async {
        if let summary = await servers.rescan(sourceId: sourceId), summary.photos > 0 { readCount += 1 }
        load()
    }

    /// On launch and each return to the foreground (FS-19.01 §5): what
    /// changed while ShotDex was away, read without a Re-index.
    func readAll() async {
        #if DEBUG
        await addSeededFolder()
        #endif
        // Only a read that changed something reloads the grid: a reload under
        // an open viewer would take it away.
        if await runner.readAll() { readCount += 1 }
        // Servers are listed by the on-server check, within each
        // connection's Backup rules (FS-19.07 §6): `serverListingChanged`.
        load()
    }

    /// A server source's listing found new or changed photos.
    func serverListingChanged() {
        readCount += 1
        load()
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
