import CoreGraphics
import Foundation
import GRDB
import ImageIO
import Observation
import os

/// One thing the open folder shows, in drawing order: folders, then photos
/// (FS-19.03 §4). Files that are not photos are only counted.
enum MacServerBrowserItem: Identifiable, Hashable {
    case folder(String)
    case photo(ServerPhoto)

    var id: String {
        switch self {
        case .folder(let name): CommonPhotosEntry.folderId(name)
        case .photo(let photo): "photo:\(photo.id)"
        }
    }

    var name: String {
        switch self {
        case .folder(let name): name
        case .photo(let photo): photo.primary.name
        }
    }
}

/// Find Common Photos… asked for, with what it starts from (FS-19.08 §3):
/// a source connection and server paths of the folders picked — maybe
/// none, from the menu bar.
struct MacCommonPhotosRequest: Identifiable, Equatable {
    let id = UUID()
    let connectionId: String
    let sourceId: String
    let folders: [String]
    /// Run Again (FS-19.08 §6c): the set's destination and action, and the
    /// scan starts at once.
    var destination: String?
    var action: CommonPhotosRun.Action?
    var scansAtOnce = false
}

/// What the library knows about a photo it shows from the server: its copy
/// (whose thumbnail the index keeps) and its marks (FS-01.12 §7).
struct MacServerCopy: Equatable, Sendable {
    let copyId: String
    let rating: Int
    let flag: PhotoFlag?
}

/// The Mac browser of a server source (board `MAC_ServerBrowser`, FS-19.03
/// §4): where it is in the source's folder, what each folder it has opened
/// lists, the library's copies of those photos, and Rescan. Every call to
/// the server goes through the connection's lock (`LockedRemoteFileClient`,
/// FS-19.07 §5), so browsing waits its turn behind Backup and the index
/// instead of sharing an SMB session with them. Paths are relative to the
/// connection's Folder — the source's root.
@MainActor
@Observable
final class MacServerBrowserModel {
    enum Listing: Equatable {
        case loading
        case loaded(ServerFolderContents)
        case failed(RemoteFileError)
    }

    /// One column of the folder browser: a folder above the open one, its
    /// subfolders, and the one on the way down.
    struct Column: Identifiable, Equatable {
        let path: String
        let title: String
        let selected: String?
        var id: String { path }
    }

    enum Layout: String, CaseIterable, Identifiable {
        case icons, list
        var id: String { rawValue }
    }

    /// What a finished Rescan has to say; nil when it went through.
    enum RescanProblem: Equatable {
        case stopped(RemoteFileError)
        case disconnected
        case notRun
    }

    let sourceId: String
    private(set) var sourceName: String
    let server: FileServer
    private(set) var history: BrowseHistory
    private(set) var listings: [String: Listing] = [:]
    /// The library's copies of the open folders' photos, by `photoKey`.
    private(set) var copies: [String: MacServerCopy] = [:]
    private(set) var storage: StorageSpace?
    private(set) var isRescanning = false
    var rescanProblem: RescanProblem?
    /// When the index last saw this source's files (newest `lastSeenAt`).
    private(set) var lastIndexed: Date?
    private(set) var isAscending = true
    var layout = Layout.icons
    /// Filters the open folder by name.
    var searchText = "" {
        didSet { pruneSelection() }
    }
    /// What is picked, by `MacServerBrowserItem.id`, in `selectionFolder`.
    private(set) var selection = ClickSelection()
    /// The folder whose items `selection` picks: the open folder for the
    /// grid and the list, or the folder a column lists when the ⌘/⇧-click
    /// was made there (FS-19.08 §3). A click elsewhere starts over.
    private(set) var selectionFolder = ""
    /// File › Find Common Photos… or the context menu asked for the sheet
    /// (FS-19.08 §4); the screen presents it from this (T10).
    var commonPhotosRequest: MacCommonPhotosRequest?

    @ObservationIgnored private let client: any RemoteFileClient
    @ObservationIgnored private let refresh: ServerSourceRefresh
    @ObservationIgnored private let database: AppDatabase
    @ObservationIgnored private let thumbnailStore: FolderThumbnails
    @ObservationIgnored private let thumbnailCache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = MacServerBrowserModel.thumbnailCacheBytes
        return cache
    }()
    @ObservationIgnored private var connectTask: Task<RemoteFileError?, Never>?
    /// Rescan and Try Again outlive the click that started them; `close()`
    /// cancels them with the visit.
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var isClosed = false
    @ObservationIgnored private var hasReadLastIndexed = false

    /// Decoded thumbnails kept while the browser is open: ~150 tiles of
    /// 400px JPEG at 4 bytes a pixel.
    private static let thumbnailCacheBytes = 96 * 1024 * 1024

    init(sourceId: String, sourceName: String, server: FileServer, client: any RemoteFileClient,
         refresh: ServerSourceRefresh, database: AppDatabase, thumbnails: FolderThumbnails = .standard, start: String = "") {
        let start = ServerUploadPath.normalizedFolder(start)
        history = BrowseHistory(start: start)
        selectionFolder = start
        self.sourceId = sourceId
        self.sourceName = sourceName
        self.server = server
        self.client = client
        self.refresh = refresh
        self.database = database
        thumbnailStore = thumbnails
    }

    // MARK: Where

    var path: String { history.current }
    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }

    func rename(to name: String) { sourceName = name }

    func title(for path: String) -> String {
        path.isEmpty ? sourceName : ServerUploadPath.lastComponent(of: path)
    }

    var title: String { title(for: path) }

    /// The source's root and every folder down to the open one — the path bar.
    var crumbs: [String] {
        let components = path.split(separator: "/").map(String.init)
        return [""] + components.indices.map { components[...$0].joined(separator: "/") }
    }

    var columns: [Column] { Self.columns(for: path, title: title(for:)) }

    /// The two folders above `path` (board `MAC_ServerBrowser`), each with
    /// the folder on the way down picked. Near the top, where fewer than
    /// two folders are above, the open folder's own subfolders fill the
    /// second column, as in Finder.
    private static func columns(for path: String, title: (String) -> String) -> [Column] {
        let components = path.split(separator: "/").map(String.init)
        var columns = BrowseHistory.ancestors(of: path).prefix(2).reversed().map { ancestor in
            let depth = ancestor.isEmpty ? 0 : ancestor.split(separator: "/").count
            return Column(path: ancestor, title: title(ancestor), selected: components[depth])
        }
        if columns.count < 2 { columns.append(Column(path: path, title: title(path), selected: nil)) }
        return columns
    }

    func open(folder name: String) { go(to: ServerUploadPath.join(path, name)) }

    func go(to newPath: String) {
        history.open(newPath)
        clearSelection()
    }

    func goBack() {
        history.goBack()
        clearSelection()
    }

    func goForward() {
        history.goForward()
        clearSelection()
    }

    // MARK: What it shows

    var listing: Listing { listings[path] ?? .loading }

    var contents: ServerFolderContents? { contents(of: path) }

    func contents(of path: String) -> ServerFolderContents? {
        if case .loaded(let contents) = listings[path] { contents } else { nil }
    }

    /// The open folder in drawing order, filtered by the search field.
    var items: [MacServerBrowserItem] {
        guard let contents else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(_ name: String) -> Bool { query.isEmpty || name.localizedStandardContains(query) }
        var folders = contents.folders.filter(matches)
        var photos = contents.photos.filter { $0.files.contains { matches($0.name) } }
        if !isAscending {
            folders.reverse()
            photos.reverse()
        }
        return folders.map(MacServerBrowserItem.folder) + photos.map(MacServerBrowserItem.photo)
    }

    func toggleSortDirection() { isAscending.toggle() }

    /// Key of a photo in `folder`: the folder and its first file's name.
    func photoKey(_ photo: ServerPhoto, in folder: String) -> String { ServerUploadPath.join(folder, photo.id) }

    func copy(of photo: ServerPhoto) -> MacServerCopy? { copies[photoKey(photo, in: path)] }

    /// The tile's thumbnail from the index's cache (FS-19.03 §5), decoded on
    /// first ask and kept within the cache's byte limit.
    func thumbnail(copyId: String) async -> CGImage? {
        if let image = thumbnailCache.object(forKey: copyId as NSString) { return image }
        let url = thumbnailStore.url(copyId: copyId)
        let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }.value
        if let image { thumbnailCache.setObject(image, forKey: copyId as NSString, cost: image.bytesPerRow * image.height) }
        return image
    }

    // MARK: Selection

    /// What the open folder's grid and list show as picked: nothing when the
    /// selection was made in a column above.
    var openFolderSelection: Set<String> { selectionFolder == path ? selection.ids : [] }

    /// Whether `item` of `folder` is picked.
    func isSelected(_ item: MacServerBrowserItem, in folder: String) -> Bool {
        folder == selectionFolder && selection.contains(item.id)
    }

    /// Every item `folder` draws, in order: the open folder's grid, or a
    /// column's folders.
    private func order(in folder: String) -> [String] {
        folder == path ? items.map(\.id) : folders(in: folder).map(CommonPhotosEntry.folderId)
    }

    private func folders(in folder: String) -> [String] {
        folder == path ? items.compactMap { if case .folder(let name) = $0 { name } else { nil } } : (contents(of: folder)?.folders ?? [])
    }

    /// A click on `item` drawn in `folder` (the open one unless a column):
    /// alone it picks only `item`; ⌘ (`extendsSelection`) adds or removes
    /// it; ⇧ (`extendsRange`) picks the run from the anchor in that folder.
    func click(_ item: MacServerBrowserItem, in folder: String? = nil, extendsSelection: Bool = false, extendsRange: Bool = false) {
        let folder = folder ?? path
        if folder != selectionFolder {
            selection.clear()
            selectionFolder = folder
        }
        selection.click(item.id, in: order(in: folder), extendsSelection: extendsSelection, extendsRange: extendsRange)
    }

    /// The List view's own selection (it handles ⌘ and ⇧ itself).
    func setSelection(_ ids: Set<String>) {
        if selectionFolder != path {
            selection.clear()
            selectionFolder = path
        }
        selection.replace(with: ids, in: order(in: path))
    }

    /// Picks folders of the open folder by name (`-ShotDexServerSelect`).
    func selectFolders(named names: [String]) {
        selectionFolder = path
        let wanted = Set(names.map(CommonPhotosEntry.folderId))
        selection.replace(with: wanted.intersection(order(in: path)), in: order(in: path))
    }

    func clearSelection() {
        selection.clear()
        selectionFolder = path
    }

    /// The picked folders as paths under the source's root, in drawing order.
    var selectedFolderPaths: [String] {
        CommonPhotosEntry.picked(selection, selectionFolder: selectionFolder, folder: selectionFolder,
                                 folders: folders(in: selectionFolder))
    }

    /// Return: open the one folder picked in the open folder.
    func openSelectedFolder() -> Bool {
        let folders = CommonPhotosEntry.picked(selection, selectionFolder: selectionFolder, folder: path, folders: folders(in: path))
        guard selection.count == 1, folders.count == 1 else { return false }
        go(to: folders[0])
        return true
    }

    private func pruneSelection() {
        selection.prune(to: order(in: selectionFolder))
    }

    // MARK: Right-click

    /// The item under the pointer, for the right-click that may follow.
    @ObservationIgnored private var pointerTarget: (item: MacServerBrowserItem, folder: String)?

    func pointer(isOver: Bool, item: MacServerBrowserItem, in folder: String) {
        if isOver {
            pointerTarget = (item, folder)
        } else if pointerTarget?.item.id == item.id, pointerTarget?.folder == folder {
            pointerTarget = nil
        }
    }

    /// A right-click: as in Finder, an item that is not picked becomes the
    /// selection first, so the highlight shows what the menu acts on.
    func secondaryClick() {
        guard let target = pointerTarget, !isSelected(target.item, in: target.folder) else { return }
        click(target.item, in: target.folder)
    }

    // MARK: Find Common Photos (FS-19.08 §3)

    /// The folders a right-click on `item` of `folder` acts on.
    func commonPhotosFolders(for item: MacServerBrowserItem, in folder: String? = nil) -> [String] {
        let folder = folder ?? path
        guard case .folder(let name) = item else { return selectedFolderPaths }
        return CommonPhotosEntry.targets(rightClicked: name, in: folder, selection: selection,
                                         selectionFolder: selectionFolder, folders: folders(in: folder))
    }

    /// The open folder's folders among `ids` — a List right-click. Ids that
    /// stand for a column's picks are not the open folder's.
    func folderPaths(forIds ids: Set<String>) -> [String] {
        folders(in: path).filter { ids.contains(CommonPhotosEntry.folderId($0)) }.map { ServerUploadPath.join(path, $0) }
    }

    /// Find Common Photos… with the folders picked now.
    func findCommonPhotosInSelection() {
        findCommonPhotos(folders: selectedFolderPaths, connectionId: server.id, sourceId: sourceId)
    }

    /// The hook the sheet (T10) presents from: `folders` are paths under
    /// the source's root, made server paths here — the runner's terms.
    func findCommonPhotos(folders: [String], connectionId: String, sourceId: String) {
        let request = MacCommonPhotosRequest(connectionId: connectionId, sourceId: sourceId,
                                             folders: CommonPhotosEntry.serverPaths(folders, connectionFolder: server.folder))
        Self.log.notice("find common photos: \(request.folders.joined(separator: ", "), privacy: .private) on \(connectionId, privacy: .public)")
        commonPhotosRequest = request
    }

    private static let log = Logger(subsystem: "com.hoangtuan.shotdex", category: "commonPhotos")

    // MARK: Loading

    /// The open folder first — the grid waits on it — then the library's
    /// copies of its photos, the columns above it, and the room left on the
    /// server. A visit cancelled by leaving the folder writes nothing more.
    func visit() async {
        let path = path
        await load(path)
        guard !Task.isCancelled else { return }
        await readCopies(path)
        for column in Self.columns(for: path, title: title(for:)) where column.path != path {
            guard !Task.isCancelled else { return }
            await load(column.path)
        }
        guard !Task.isCancelled else { return }
        if storage == nil, contents(of: path) != nil {
            do {
                try await connect()
                storage = try await client.storageSpace(at: remotePath(path))
            } catch {
                await dropSessionIfLost(error)
            }
        }
        if !hasReadLastIndexed {
            hasReadLastIndexed = true
            await readLastIndexed()
        }
    }

    /// The server changed under the browser (a common-photos run on this
    /// connection ended): every folder is listed again as it comes up.
    func refreshListings() {
        start {
            self.listings = [:]
            self.copies = [:]
            self.pruneSelection()
            await self.visit()
        }
    }

    /// Try Again after a failed listing: a fresh session, then the visit.
    func retry() {
        start {
            await self.dropSession()
            self.listings[self.path] = nil
            await self.visit()
        }
    }

    /// Rescan (FS-19.03 §3): the source's whole listing compared again by
    /// `ServerSourceRefresh` — joining a pass already running — then the
    /// folders on screen listed again.
    func rescan() {
        guard !isRescanning else { return }
        start {
            self.isRescanning = true
            self.rescanProblem = nil
            let summary = await self.refresh.rescan(sourceId: self.sourceId)
            self.isRescanning = false
            guard !Task.isCancelled else { return }
            if let summary {
                if let stop = summary.stoppedBy {
                    self.rescanProblem = .stopped(stop)
                } else if summary.disconnected {
                    self.rescanProblem = .disconnected
                }
            } else {
                self.rescanProblem = .notRun
            }
            let path = self.path
            let onScreen = [path] + Self.columns(for: path, title: self.title(for:)).map(\.path)
            self.listings = self.listings.filter { onScreen.contains($0.key) }
            self.copies = [:]
            self.thumbnailCache.removeAllObjects()
            for folder in onScreen {
                guard !Task.isCancelled else { return }
                await self.load(folder, force: true)
            }
            await self.readCopies(path)
            self.pruneSelection()
            await self.readLastIndexed()
        }
    }

    /// Ends the visit: no new session after this, running work cancelled,
    /// the session closed.
    func close() async {
        isClosed = true
        work?.cancel()
        work = nil
        await dropSession()
    }

    private func start(_ body: @escaping @MainActor () async -> Void) {
        guard !isClosed else { return }
        work?.cancel()
        work = Task { await body() }
    }

    private func remotePath(_ path: String) -> String { ServerUploadPath.join(server.folder, path) }

    private func connect() async throws {
        guard !isClosed else { throw CancellationError() }
        if connectTask == nil {
            let client = client
            connectTask = Task {
                do {
                    try await client.connect()
                    return nil
                } catch {
                    return error as? RemoteFileError ?? .other(error.localizedDescription)
                }
            }
        }
        if let error = await connectTask?.value {
            connectTask = nil
            throw error
        }
        if isClosed {
            await dropSession()
            throw CancellationError()
        }
    }

    private func dropSession() async {
        guard connectTask != nil else { return }
        connectTask = nil
        await client.disconnect()
    }

    /// A session the server dropped is not used again: the next call connects afresh.
    private func dropSessionIfLost(_ error: Error) async {
        switch error as? RemoteFileError {
        case .connectionLost, .unreachable: await dropSession()
        default: break
        }
    }

    private func load(_ folder: String, force: Bool = false) async {
        if !force, case .loaded = listings[folder] { return }
        if contents(of: folder) == nil { listings[folder] = .loading }
        do {
            try await connect()
            let entries = try await client.entries(in: remotePath(folder))
            guard !Task.isCancelled else { return }
            listings[folder] = .loaded(ServerFolderListing.contents(of: entries))
        } catch is CancellationError {
            if case .loading = listings[folder] { listings[folder] = nil }
        } catch {
            await dropSessionIfLost(error)
            guard !Task.isCancelled else {
                if case .loading = listings[folder] { listings[folder] = nil }
                return
            }
            listings[folder] = .failed(error as? RemoteFileError ?? .other(error.localizedDescription))
        }
    }

    /// The library's copies of the photos directly in `folder`, with their
    /// marks: one range read on `photo_copies_path` (sourceId,
    /// relativePathKey), children picked in Swift. A photo the index has not
    /// read yet has none and keeps the placeholder tile.
    private func readCopies(_ folder: String) async {
        guard let contents = contents(of: folder), !contents.photos.isEmpty else { return }
        var photoByPathKey: [String: String] = [:]
        for photo in contents.photos {
            for file in photo.files {
                photoByPathKey[FolderSourceIndexer.pathKey(ServerUploadPath.join(folder, file.name))] = photoKey(photo, in: folder)
            }
        }
        let sourceId = sourceId
        let folderKey = FolderSourceIndexer.pathKey(folder)
        // Every key under `folder/` sorts between "folder/" and "folder0"
        // ('0' follows '/'), so the index answers it as one range; deeper
        // files in that range fall out at `photoByPathKey`. The root is
        // every key with no '/'.
        let range = folderKey.isEmpty
            ? "instr(c.relativePathKey, '/') = 0"
            : "c.relativePathKey >= ? AND c.relativePathKey < ?"
        let arguments: StatementArguments = folderKey.isEmpty
            ? [sourceId]
            : [sourceId, folderKey + "/", folderKey + "0"]
        let rows: [(pathKey: String, copy: MacServerCopy)] = (try? await database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT c.id, c.relativePathKey,
                       COALESCE((SELECT rating FROM pending_photo_rating WHERE assetId = c.photoId),
                                (SELECT rating FROM photo_user_marks WHERE photoId = c.photoId AND rating IS NOT NULL),
                                (SELECT rating FROM photo_metadata WHERE assetId = c.photoId), 0) AS rating,
                       (SELECT flag FROM photo_flag WHERE assetId = c.photoId) AS flag
                FROM photo_copies c
                WHERE c.sourceId = ? AND c.missingSince IS NULL AND \(range)
                """, arguments: arguments).map { row in
                (row["relativePathKey"], MacServerCopy(copyId: row["id"], rating: row["rating"],
                                                       flag: (row["flag"] as String?).flatMap(PhotoFlag.init(rawValue:))))
            }
        }) ?? []
        guard !Task.isCancelled else { return }
        for row in rows {
            if let key = photoByPathKey[row.pathKey] { copies[key] = row.copy }
        }
    }

    private func readLastIndexed() async {
        let sourceId = sourceId
        let seen = try? await database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT MAX(lastSeenAt) FROM photo_copies WHERE sourceId = ?", arguments: [sourceId])
        }
        lastIndexed = seen.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}
