import Foundation

/// Every photo, video and sidecar under one server folder, depth first —
/// the listing a server source is indexed from (FS-19.03 §2) and the one
/// common photos are found in (FS-19.08 §5). Dot names are dropped, so the
/// `.shotdex/` index and hidden files never show up; part files fail the
/// readable check.
enum ServerTreeListing {
    /// `entries`, when given, lists each folder instead of the client — with
    /// the folder's write time as its parent listed it (nil for `folder`
    /// itself): how Common Photos reuses a day folder that has not changed
    /// (FS-19.08 §6e).
    static func list(_ folder: String, client: RemoteFileClient,
                     entries: ((_ path: String, _ folderModified: Date?) async throws -> [RemoteEntry])? = nil)
        async throws -> [FolderEnumeration.Entry] {
        var out: [FolderEnumeration.Entry] = []
        var pending: [(path: String, modified: Date?)] = [("", nil)]
        while let (relative, folderModified) = pending.popLast() {
            try Task.checkCancellation()
            let path = ServerUploadPath.join(folder, relative)
            let listed: [RemoteEntry]
            if let entries {
                listed = try await entries(path, folderModified)
            } else {
                listed = try await client.entries(in: path)
            }
            for entry in listed where !entry.name.hasPrefix(".") {
                let path = relative.isEmpty ? entry.name : relative + "/" + entry.name
                if entry.isDirectory {
                    pending.append((path, entry.modified))
                    continue
                }
                let url = URL(fileURLWithPath: entry.name)
                let isSidecar = url.pathExtension.lowercased() == "xmp"
                guard isSidecar || FolderEnumeration.isReadable(url) else { continue }
                out.append(FolderEnumeration.Entry(relativePath: path, size: entry.size, modified: entry.modified, isSidecar: isSidecar))
            }
        }
        return out.sorted { $0.relativePath < $1.relativePath }
    }
}
