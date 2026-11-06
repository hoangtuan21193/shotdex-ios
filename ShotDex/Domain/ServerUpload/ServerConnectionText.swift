import Foundation

/// Words of Settings › Servers (FS-18.04 §3 AC-77).
enum ServerConnectionText {
    /// Delete Connection's confirmation: what leaves ShotDex, what goes with
    /// the connection, and that nothing on the server is touched.
    static func deleteMessage(_ impact: ServerConnectionDeletion.Impact) -> String {
        var parts: [String] = []
        if impact.sourceId != nil {
            parts.append(impact.photoCount == 1
                ? String(localized: "Its photo leaves ShotDex unless another source has it.", comment: "Delete connection: one photo leaves the library")
                : String(localized: "Its \(impact.photoCount, format: .number) photos leave ShotDex unless another source has them.",
                         comment: "Delete connection: the source's photos leave the library"))
        }
        if impact.backupJobs > 0 {
            parts.append(impact.backupJobs == 1
                ? String(localized: "Its backup is deleted too.", comment: "Delete connection: one backup job goes with it")
                : String(localized: "Its \(impact.backupJobs, format: .number) backups are deleted too.", comment: "Delete connection: backup jobs go with it"))
        }
        if impact.shortcuts > 0 {
            parts.append(String(localized: "Its folder shortcuts go too.", comment: "Delete connection: server folder shortcuts go with it"))
        }
        parts.append(String(localized: "Nothing on the server is deleted. Its password leaves your Keychain.",
                            comment: "Delete connection: the server's files stay"))
        return parts.joined(separator: " ")
    }
}
