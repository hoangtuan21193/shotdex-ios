import Foundation

/// SMB paths from the machine's root (FS-15.01 §3a): the first component is
/// the shared folder, the rest a path inside it — one path, no separate
/// Share field.
enum SMBPath {
    /// `photos/RAW/a.CR3` → (`photos`, `RAW/a.CR3`); `photos` → (`photos`,
    /// `""`); nil for the root, which only lists the shares.
    static func split(_ path: String) -> (share: String, rest: String)? {
        let components = ServerUploadPath.normalizedFolder(path).split(separator: "/", maxSplits: 1).map(String.init)
        guard let share = components.first else { return nil }
        return (share, components.count > 1 ? components[1] : "")
    }
}
