import Foundation

/// How a rename or delete on the server reaches the stored paths
/// (FS-17.01 §4b): a path is touched when it is the item itself or lies
/// inside it, if the item is a folder.
enum ServerHistoryPaths {
    static func isAffected(_ path: String, by item: String) -> Bool {
        let path = ServerUploadPath.normalizedFolder(path)
        let item = ServerUploadPath.normalizedFolder(item)
        guard !item.isEmpty else { return false }
        return path == item || path.hasPrefix(item + "/")
    }

    /// `path` after `item` became `newItem`; nil when the rename does not
    /// touch it.
    static func renamed(_ path: String, from item: String, to newItem: String) -> String? {
        guard isAffected(path, by: item) else { return nil }
        let path = ServerUploadPath.normalizedFolder(path)
        let item = ServerUploadPath.normalizedFolder(item)
        return ServerUploadPath.normalizedFolder(newItem) + path.dropFirst(item.count)
    }
}
