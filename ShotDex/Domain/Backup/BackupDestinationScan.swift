import Foundation

/// Lists every file in a job's destination folder, all levels down — names,
/// sizes and dates only, no file is read (FS-22.05 §3).
///
/// Hidden entries are left out: `.shotdex/` holds the shared index, and a
/// NAS's own `.DS_Store` or `._` files are never photos. Part files are
/// unfinished writes, not contents.
enum BackupDestinationScan {
    struct File: Equatable, Sendable {
        /// Relative to the scanned folder.
        var path: String
        var size: Int64
        var modified: Date?
    }

    static func list(
        _ client: any RemoteFileClient,
        folder: String,
        onCount: (Int) -> Void = { _ in }
    ) async throws -> [File] {
        var files: [File] = []
        var pending = [""]
        while let relative = pending.popLast() {
            try Task.checkCancellation()
            for entry in try await client.entries(in: ServerUploadPath.join(folder, relative)) {
                // A part, or a common-photos copy being removed (FS-19.08 §6).
                if entry.name.hasPrefix(".") || entry.name.hasSuffix(ServerUploadPath.partSuffix)
                    || entry.name.hasSuffix(CommonPhotosRunner.removingSuffix) { continue }
                let path = ServerUploadPath.join(relative, entry.name)
                if entry.isDirectory {
                    pending.append(path)
                } else {
                    files.append(File(path: path, size: entry.size, modified: entry.modified))
                }
            }
            onCount(files.count)
        }
        return files
    }
}
