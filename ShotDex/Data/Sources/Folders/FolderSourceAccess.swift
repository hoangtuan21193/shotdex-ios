import Foundation
import GRDB

/// Opening a folder source through its security-scoped bookmark (FS-19.01b
/// §2), the way `ExportFolderStore` opens export folders.
struct FolderSourceAccess: Sendable {
    let database: AppDatabase

    enum State: Equatable, Sendable {
        case available(URL)
        /// The bookmark no longer opens (folder renamed while the app was
        /// closed, permission withdrawn): the row says Needs access and offers
        /// Grant Access…; the photos stay, offline.
        case needsAccess
        /// A drive that is not plugged in.
        case offline
    }

    /// Resolves the source's bookmark; a stale one that still opens is made
    /// again. Updates the source's status and its copies' online flag.
    func open(sourceId: String) throws -> State {
        let row = try database.reader.read { db in
            try Row.fetchOne(db, sql: "SELECT kind, bookmark FROM sources WHERE id = ?", arguments: [sourceId])
        }
        guard let row else { return .needsAccess }
        let kind: String = row["kind"]
        let bookmark: Data? = row["bookmark"]
        var isStale = false
        guard let bookmark, let url = try? SourceBookmark.resolve(bookmark, isStale: &isStale) else {
            return try mark(.needsAccess, sourceId: sourceId)
        }
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
        guard (try? url.checkResourceIsReachable()) == true else {
            return try mark(kind == "drive" ? .offline : .needsAccess, sourceId: sourceId)
        }
        if isStale, let renewed = try? SourceBookmark.make(for: url) {
            try database.writer.write { db in
                try db.execute(sql: "UPDATE sources SET bookmark = ? WHERE id = ?", arguments: [renewed, sourceId])
            }
        }
        return try mark(.available(url), sourceId: sourceId)
    }

    /// Grant Access…: the user points at the folder again. The new bookmark
    /// is kept; the next read matches the files back to their photos by path
    /// and, where they moved, by hash — same ids, no duplicate.
    func grant(sourceId: String, folder: URL) throws {
        let isAccessing = folder.startAccessingSecurityScopedResource()
        defer { if isAccessing { folder.stopAccessingSecurityScopedResource() } }
        let bookmark = try SourceBookmark.make(for: folder)
        try database.writer.write { db in
            try db.execute(sql: "UPDATE sources SET bookmark = ?, name = ? WHERE id = ?",
                           arguments: [bookmark, folder.lastPathComponent, sourceId])
        }
        _ = try open(sourceId: sourceId)
    }

    @discardableResult
    private func mark(_ state: State, sourceId: String) throws -> State {
        let status: String
        switch state {
        case .available: status = "online"
        case .needsAccess: status = "needsAccess"
        case .offline: status = "offline"
        }
        try database.writer.write { db in
            try db.execute(sql: "UPDATE sources SET status = ? WHERE id = ?", arguments: [status, sourceId])
            if case .available = state {
                try db.execute(sql: "UPDATE photo_copies SET isOnline = 1 WHERE sourceId = ?", arguments: [sourceId])
            } else {
                try db.execute(sql: "UPDATE photo_copies SET isOnline = 0 WHERE sourceId = ?", arguments: [sourceId])
            }
        }
        return state
    }
}

/// Source folders kept open for the app's lifetime once used — the sidecar
/// writer and the viewer reach files one at a time, and a security scope
/// opened and closed around each would cost a bookmark resolve per file.
final class FolderSourceRoots: @unchecked Sendable {
    private let database: AppDatabase
    private let lock = NSLock()
    private var roots: [String: URL] = [:]

    init(database: AppDatabase) {
        self.database = database
    }

    /// The folder of `sourceId`, inside its scope; nil while it cannot be
    /// opened (unplugged, access lost).
    func root(_ sourceId: String) -> URL? {
        if let known = lock.withLock({ roots[sourceId] }) {
            if (try? known.checkResourceIsReachable()) == true { return known }
            lock.withLock { roots[sourceId] = nil }
            known.stopAccessingSecurityScopedResource()
        }
        guard case .available(let url) = try? FolderSourceAccess(database: database).open(sourceId: sourceId) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        lock.withLock { roots[sourceId] = url }
        return url
    }

    /// A source removed or pointed at another folder: its old folder's
    /// scope closes and the next `root` opens what the bookmark says now.
    func forget(_ sourceId: String) {
        guard let known = lock.withLock({ roots.removeValue(forKey: sourceId) }) else { return }
        known.stopAccessingSecurityScopedResource()
    }

    /// Whether files of `sourceId` can go to a Trash (FS-19.04 §1): a USB-C
    /// drive on iPad or iPhone, some exFAT/FAT volumes and the app's own
    /// folder have none, and are deleted for good after the red dialog.
    /// Unknown — the source is away — counts as having one: nothing is
    /// deleted then anyway.
    func hasTrash(_ sourceId: String) -> Bool {
        guard let root = root(sourceId) else { return true }
        return (try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: root, create: false)) != nil
    }

    func fileURL(sourceId: String, relativePath: String) -> URL? {
        root(sourceId)?.appendingPathComponent(relativePath)
    }
}
