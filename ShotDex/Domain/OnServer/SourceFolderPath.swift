import Foundation

/// Folder paths of a server source (FS-19.07 §7): the folder browser
/// answers with a path from the server's root, and a Source condition keeps
/// it from the source's own root, which is the connection's Folder.
enum SourceFolderPath {
    /// `Shared/2025` for `iCloud Photo/Shared/2025` under `iCloud Photo`;
    /// empty for the root itself; nil for a folder outside the source.
    static func relative(chosen: String, root: String) -> String? {
        let chosen = trimmed(chosen)
        let root = trimmed(root)
        guard !root.isEmpty else { return chosen }
        if chosen == root { return "" }
        guard chosen.hasPrefix(root + "/") else { return nil }
        return String(chosen.dropFirst(root.count + 1))
    }

    /// Where the browser opens: the chosen folder, from the server's root.
    static func absolute(_ folder: String?, root: String) -> String {
        let folder = trimmed(folder ?? "")
        let root = trimmed(root)
        if folder.isEmpty { return root }
        return root.isEmpty ? folder : root + "/" + folder
    }

    private static func trimmed(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }
}
