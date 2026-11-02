import Foundation

/// Every photo, video and sidecar under one server folder, depth first —
/// the listing a server source is indexed from (FS-19.03 §2) and the one
/// common photos are found in (FS-19.08 §5). Dot names are dropped, so the
/// `.shotdex/` index and hidden files never show up; part files fail the
/// readable check.
enum ServerTreeListing {
    static func list(_ folder: String, client: RemoteFileClient) async throws -> [FolderEnumeration.Entry] {
        var out: [FolderEnumeration.Entry] = []
        var pending = [""]
        while let relative = pending.popLast() {
            try Task.checkCancellation()
            for entry in try await client.entries(in: ServerUploadPath.join(folder, relative)) where !entry.name.hasPrefix(".") {
                let path = relative.isEmpty ? entry.name : relative + "/" + entry.name
                if entry.isDirectory {
                    pending.append(path)
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
