import Foundation
import Observation
import UIKit

/// One thing the browser lists (FS-17.01 §2b), in the order it is drawn:
/// folders, then photos, then — with Show All Files — everything else.
enum ServerBrowserItem: Identifiable, Hashable {
    case folder(String)
    case photo(ServerPhoto)
    case file(RemoteEntry)

    var id: String {
        switch self {
        case .folder(let name): "folder:\(name)"
        case .photo(let photo): "photo:\(photo.id)"
        case .file(let entry): "file:\(entry.name)"
        }
    }

    /// The name Rename starts from: a file's name without its extension.
    var baseName: String {
        switch self {
        case .folder(let name): name
        case .photo(let photo): (photo.primary.name as NSString).deletingPathExtension
        case .file(let entry): (entry.name as NSString).deletingPathExtension
        }
    }

    /// The names on the server this item stands for.
    var names: [String] {
        switch self {
        case .folder(let name): [name]
        case .photo(let photo): photo.files.map(\.name)
        case .file(let entry): [entry.name]
        }
    }
}

/// One visit to a connection in the Files-style browser (FS-17.01 §2, §4,
/// §5): where it has been, how it draws, and the changes it makes on the
/// server. Each folder keeps its own `ServerFolderModel` for the visit, so
/// Back and Forward do not list again.
@MainActor
@Observable
final class ServerBrowserModel {
    enum Mode: Equatable {
        case browse
        /// Picking a folder for the upload sheet or the connection form.
        case chooseFolder
    }

    enum Layout: String, CaseIterable, Identifiable {
        case icons
        case list

        var id: String { rawValue }
    }

    let session: ServerBrowseSession
    let mode: Mode
    private(set) var history: BrowseHistory
    private(set) var layout: Layout
    private(set) var showsAllFiles: Bool
    private(set) var sort: ServerPhotoSort
    private(set) var ascending: Bool
    /// A change on the server is running; the screen blocks a second one.
    private(set) var isWorking = false
    /// What went wrong with New Folder, Rename or Delete; the screen shows
    /// it and clears it.
    var editError: String?

    /// Made while SwiftUI reads `current` in a body, so not observed —
    /// filling it must not invalidate the view reading it.
    @ObservationIgnored private var folders: [String: ServerFolderModel] = [:]
    private let makeFolderModel: (String) -> ServerFolderModel
    private let fileHistory: ServerFileHistory?
    /// Collections → Network (FS-17.04); nil where tiles are not offered.
    private let shortcuts: ServerShortcutCatalog?
    /// Folders whose tile cover was refreshed this visit.
    @ObservationIgnored private var coveredPaths: Set<String> = []
    private let onUploadsForgotten: () -> Void
    private let defaults: UserDefaults

    init(
        session: ServerBrowseSession,
        start: String,
        mode: Mode = .browse,
        fileHistory: ServerFileHistory? = nil,
        shortcuts: ServerShortcutCatalog? = nil,
        defaults: UserDefaults = .standard,
        onUploadsForgotten: @escaping () -> Void = {},
        makeFolderModel: @escaping (String) -> ServerFolderModel
    ) {
        self.session = session
        self.mode = mode
        self.fileHistory = fileHistory
        self.shortcuts = shortcuts
        self.defaults = defaults
        self.onUploadsForgotten = onUploadsForgotten
        self.makeFolderModel = makeFolderModel
        history = BrowseHistory(start: ServerUploadPath.normalizedFolder(start))
        let id = session.server.id
        layout = defaults.string(forKey: Self.key("layout", id)).flatMap(Layout.init(rawValue:)) ?? .icons
        showsAllFiles = defaults.bool(forKey: Self.key("showsAllFiles", id))
        let storedSort = defaults.string(forKey: Self.key("sort", id)).flatMap(ServerPhotoSort.init(rawValue:)) ?? .name
        sort = storedSort
        ascending = defaults.object(forKey: Self.key("ascending", id)) as? Bool ?? storedSort.defaultAscending
    }

    private static func key(_ name: String, _ serverId: String) -> String { "serverBrowser.\(name).\(serverId)" }

    var server: FileServer { session.server }

    // MARK: Where

    var path: String { history.current }

    /// The folder on screen, made on first visit.
    var current: ServerFolderModel { folderModel(for: history.current) }

    private func folderModel(for path: String) -> ServerFolderModel {
        if let model = folders[path] {
            model.apply(sort: sort, ascending: ascending)
            return model
        }
        let model = makeFolderModel(path)
        model.apply(sort: sort, ascending: ascending)
        folders[path] = model
        return model
    }

    /// Nothing but the computer's shared folders lives at an SMB root.
    var isAtSMBRoot: Bool { server.transferProtocol == .smb && path.isEmpty }

    func title(for path: String) -> String {
        guard path.isEmpty else { return ServerUploadPath.lastComponent(of: path) }
        return server.transferProtocol == .sftp
            ? String(localized: "Home", comment: "Server browser: the SFTP login's home folder")
            : server.name
    }

    var title: String { title(for: path) }

    /// The title menu: the folders above, nearest first (FS-17.01 §2a).
    var ancestors: [String] { BrowseHistory.ancestors(of: path) }

    func open(folder name: String) {
        leaveSelection()
        history.open(ServerUploadPath.join(path, name))
    }

    func go(to path: String) {
        leaveSelection()
        history.open(path)
    }

    /// False at the first visit: the screen is left instead.
    func goBack() -> Bool {
        leaveSelection()
        return history.goBack()
    }

    func goForward() {
        leaveSelection()
        history.goForward()
    }

    private func leaveSelection() {
        if current.isSelecting { current.isSelecting = false }
    }

    // MARK: How it draws

    func setLayout(_ newLayout: Layout) {
        layout = newLayout
        defaults.set(newLayout.rawValue, forKey: Self.key("layout", server.id))
    }

    func setShowsAllFiles(_ value: Bool) {
        showsAllFiles = value
        defaults.set(value, forKey: Self.key("showsAllFiles", server.id))
    }

    /// Sort By, as in Files: picking the current order flips its direction,
    /// a new one starts in its own direction.
    func chooseSort(_ newSort: ServerPhotoSort) {
        if newSort == sort {
            ascending.toggle()
        } else {
            sort = newSort
            ascending = newSort.defaultAscending
        }
        defaults.set(sort.rawValue, forKey: Self.key("sort", server.id))
        defaults.set(ascending, forKey: Self.key("ascending", server.id))
        current.apply(sort: sort, ascending: ascending)
    }

    /// What the folder on screen lists, in drawing order.
    var items: [ServerBrowserItem] {
        let model = current
        var items = model.contents.folders.map(ServerBrowserItem.folder)
        items += model.photos.map(ServerBrowserItem.photo)
        if showsAllFiles { items += model.contents.others.map(ServerBrowserItem.file) }
        return items
    }

    /// Photos can be picked only when browsing (FS-17.01 §5).
    var canSelect: Bool { mode == .browse }

    /// Rename and Delete: browsing only, never a share at an SMB root.
    var canEdit: Bool { mode == .browse && !isAtSMBRoot }

    var canCreateFolder: Bool { !isAtSMBRoot }

    var canChoose: Bool { mode == .chooseFolder && !isAtSMBRoot }

    // MARK: Collections tiles (FS-17.04)

    /// Add to Collections: browsing only, and never an SMB root, which only
    /// lists shared folders.
    func canAddShortcut(at path: String) -> Bool {
        shortcuts != nil && mode == .browse && !(server.transferProtocol == .smb && ServerUploadPath.normalizedFolder(path).isEmpty)
    }

    func isShortcut(_ path: String) -> Bool {
        shortcuts?.shortcut(serverId: server.id, path: path) != nil
    }

    /// Adds the folder as a tile, or removes the one it has. Nothing is
    /// written to the server.
    func toggleShortcut(at path: String) {
        guard let shortcuts, canAddShortcut(at: path) else { return }
        if let existing = shortcuts.shortcut(serverId: server.id, path: path) {
            shortcuts.remove(existing.id)
        } else {
            // At a root the folder has no name of its own; the connection's
            // says more than "Home" (FS-17.04 §1).
            let name = ServerUploadPath.normalizedFolder(path).isEmpty ? server.name : title(for: path)
            shortcuts.add(serverId: server.id, path: path, name: name)
        }
    }

    /// A tile's cover is the folder's first photo, in the order on screen,
    /// once its thumbnail has arrived — at most once a visit per folder.
    func refreshCover() {
        guard let shortcuts, !coveredPaths.contains(path),
              let tile = shortcuts.shortcut(serverId: server.id, path: path) else { return }
        let model = current
        guard model.listing == .loaded, let first = model.photos.first,
              let image = model.thumbnails[first.id] else { return }
        coveredPaths.insert(path)
        if let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.7) {
            shortcuts.setCover(jpeg, for: tile.id)
        }
    }

    // MARK: Changes on the server

    /// Makes `typed` in the folder on screen and opens it. A folder that is
    /// already there is simply opened.
    @discardableResult
    func createFolder(named typed: String) async -> Bool {
        guard canCreateFolder, let name = RemoteFolderListing.validatedName(typed) else { return false }
        let newPath = ServerUploadPath.join(path, name)
        let folder = current
        isWorking = true
        defer { isWorking = false }
        do {
            try await session.perform { client in try await client.createDirectory(newPath) }
            await folder.load(force: true)
            go(to: newPath)
            return true
        } catch {
            editError = Self.message(for: error)
            return false
        }
    }

    /// Renames an item, keeping extensions; a RAW+JPEG pair moves together.
    /// Both histories follow the new names (FS-17.01 §4b).
    @discardableResult
    func rename(_ item: ServerBrowserItem, to typed: String) async -> Bool {
        guard canEdit, let base = RemoteFolderListing.validatedName(typed) else { return false }
        let moves: [(from: String, to: String)] = item.names.map { name in
            let ext = (name as NSString).pathExtension
            let newName: String = switch item {
            case .folder: base
            case .photo, .file: ext.isEmpty ? base : "\(base).\(ext)"
            }
            return (name, newName)
        }
        guard moves.contains(where: { $0.from != $0.to }) else { return true }
        let taken = Set(takenNames().map { $0.lowercased() }).subtracting(item.names.map { $0.lowercased() })
        if moves.contains(where: { taken.contains($0.to.lowercased()) }) {
            editError = String(localized: "An item named “\(base)” already exists.", comment: "Server browser: Rename to a name already in the folder")
            return false
        }
        let folder = path
        let model = current
        isWorking = true
        defer { isWorking = false }
        for move in moves where move.from != move.to {
            let source = ServerUploadPath.join(folder, move.from)
            let destination = ServerUploadPath.join(folder, move.to)
            do {
                try await session.perform { client in try await client.move(source, to: destination) }
                try? fileHistory?.move(source, to: destination, on: server)
                if case .folder = item { dropFolderModels(under: source) }
            } catch {
                editError = Self.message(for: error)
                await model.load(force: true)
                return false
            }
        }
        await model.load(force: true)
        return true
    }

    /// Deletes items in turn — a folder with everything in it — and stops
    /// at the first failure (FS-17.01 §4b). Upload proof for what went is
    /// dropped as each item goes.
    func delete(_ items: [ServerBrowserItem]) async {
        guard canEdit, !items.isEmpty else { return }
        let folder = path
        let model = current
        isWorking = true
        defer { isWorking = false }
        var forgot = 0
        outer: for item in items {
            for name in item.names {
                let target = ServerUploadPath.join(folder, name)
                do {
                    if case .folder = item {
                        try await session.perform { client in try await client.removeFolderTree(target) }
                        dropFolderModels(under: target)
                    } else {
                        try await session.perform { client in try await client.remove(target) }
                    }
                    forgot += (try? fileHistory?.forgetUploads(at: target, on: server)) ?? 0
                } catch {
                    editError = Self.message(for: error)
                    break outer
                }
            }
        }
        model.isSelecting = false
        if forgot > 0 { onUploadsForgotten() }
        await model.load(force: true)
    }

    private func takenNames() -> [String] {
        let contents = current.contents
        return contents.folders + contents.photos.flatMap { $0.files.map(\.name) } + contents.others.map(\.name)
    }

    /// A folder renamed or deleted: its visits (and everything under it)
    /// would show stale listings.
    private func dropFolderModels(under target: String) {
        for key in folders.keys where ServerHistoryPaths.isAffected(key, by: target) {
            folders.removeValue(forKey: key)?.close()
        }
    }

    func close() {
        folders.values.forEach { $0.close() }
    }

    private static func message(for error: Error) -> String {
        ((error as? RemoteFileError) ?? .other(error.localizedDescription)).localizedDescription
    }
}
