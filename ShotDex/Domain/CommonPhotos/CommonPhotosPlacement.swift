import Foundation

/// Where a Common Photos run's Organize files a photo under the
/// destination (FS-19.08 §6e): Backup's planner, fed with what a server
/// folder knows — the date from `CommonPhotosOrganizeDate`, and for Same
/// as Source the folders the photo sits in under the first folder.
enum CommonPhotosPlacement {
    /// Whether filing needs the photo's date — the date levels, or a file
    /// name made from it.
    static func needsDate(_ organize: BackupOrganize) -> Bool {
        ![.sameAsSource, .noFolders, .album].contains(organize.levels) || organize.fileNames != .original
    }

    /// The folders `path` sits in under `firstFolder`, `/`-separated; "" at
    /// its top or outside it.
    static func sourceFolder(of path: String, firstFolder: String) -> String {
        let parent = ServerUploadPath.parent(of: path)
        let root = firstFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmed = parent.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard trimmed.lowercased().hasPrefix(root.lowercased() + "/") else { return "" }
        return String(trimmed.dropFirst(root.count + 1))
    }

    /// The path under the destination; nil when that is the photo's own
    /// name at the top — what a run without Organize does.
    static func relativePath(organize: BackupOrganize, sourcePath: String, firstFolder: String, date: Date,
                             names: BackupDateName) -> String? {
        let name = ServerUploadPath.lastComponent(of: sourcePath)
        let input = BackupPlacementInput(
            date: date, isVideo: PairingRule.isMovie(name), originalFilename: name,
            isRAW: FileTypeBadge.isRAW(filename: name),
            sourceFolder: sourceFolder(of: sourcePath, firstFolder: firstFolder))
        let path = BackupPathPlanner(organize: organize, names: names).relativePath(for: input)
        return path == name ? nil : path
    }
}
