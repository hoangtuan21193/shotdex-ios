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
        guard let bookmark, let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else {
            return try mark(.needsAccess, sourceId: sourceId)
        }
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
        guard (try? url.checkResourceIsReachable()) == true else {
            return try mark(kind == "drive" ? .offline : .needsAccess, sourceId: sourceId)
        }
        if isStale, let renewed = try? url.bookmarkData() {
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
        let bookmark = try folder.bookmarkData()
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
