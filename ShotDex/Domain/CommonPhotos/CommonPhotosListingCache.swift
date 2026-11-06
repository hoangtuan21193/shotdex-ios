import Foundation

/// When a rescan may take a folder's listing from the last one instead of
/// asking the server again (FS-19.08 §6e): only a folder whose write time,
/// as its parent lists it now, is the one it had then — a day folder's
/// changes when a file is added or removed in it — that had no folders of
/// its own (a change inside a subfolder does not reach it), listed less than
/// a day ago (NTFS keeps a folder's time when a file in it is rewritten in
/// place). A Move, Scan Everything, or a server that reports no folder
/// times lists every folder.
enum CommonPhotosListingCache {
    static let maxAge: TimeInterval = 24 * 60 * 60

    /// A folder as it was last listed.
    struct Listed: Equatable, Sendable {
        /// The folder's write time as its parent listed it, epoch seconds.
        var folderModified: Int
        var hasSubfolders: Bool
        var entries: [RemoteEntry]
        var listedAt: Date
    }

    static func reuses(_ listed: Listed?, folderModified: Date?, now: Date) -> Bool {
        guard let listed, let folderModified, !listed.hasSubfolders else { return false }
        return Int(folderModified.timeIntervalSince1970) == listed.folderModified
            && now.timeIntervalSince(listed.listedAt) < maxAge && now >= listed.listedAt
    }
}
