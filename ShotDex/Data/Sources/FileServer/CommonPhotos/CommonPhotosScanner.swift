import Foundation

/// The reading half of the common-photos scan (FS-19.08 §5): lists every
/// chosen folder, then reads the 64 KB head of the files whose size is in
/// every folder and that do not already look alike by name or subfolder.
/// Nothing else of any file is read here.
struct CommonPhotosScanner {
    let client: RemoteFileClient

    /// Photos and videos of each folder, and the `.xmp` sidecars beside them
    /// (they follow their photo, FS-19.08 §6, and are never matched).
    struct Listing: Equatable, Sendable {
        var files: [[CommonPhotosFile]]
        var sidecars: [[CommonPhotosFile]]
    }

    func list(_ folders: [String]) async throws -> Listing {
        var listing = Listing(files: [], sidecars: [])
        for (index, folder) in folders.enumerated() {
            let entries = try await ServerTreeListing.list(folder, client: client)
            let files = entries.map {
                (CommonPhotosFile(folder: index, relativePath: $0.relativePath, size: $0.size, modified: $0.modified), $0.isSidecar)
            }
            listing.files.append(files.filter { !$0.1 }.map(\.0))
            listing.sidecars.append(files.filter(\.1).map(\.0))
        }
        return listing
    }

    /// Capture keys for the candidates name and subfolder leave unmatched,
    /// and for the files they could match. `known` holds keys the index
    /// already has (a folder that is a source, FS-19.08 §5 step 3); only the
    /// rest are read. Videos and heads ImageIO cannot read give none. A file
    /// that cannot be read (gone since the listing, no permission) gives
    /// none too; a server that went away stops the scan.
    func captureKeys(for groups: [CommonPhotosMatcher.SizeGroup], folders: [String],
                     known: [CommonPhotosFile: String] = [:]) async throws -> [CommonPhotosFile: String] {
        var keys = known
        for group in groups {
            let alike = CommonPhotosMatcher.likely(group)
            guard group.files.joined().contains(where: { !alike.contains($0) }) else { continue }
            for file in group.files.joined() where keys[file] == nil && !FolderEnumeration.isMovie(URL(fileURLWithPath: file.name)) {
                try Task.checkCancellation()
                let path = ServerUploadPath.join(folders[file.folder], file.relativePath)
                let head: Data
                do {
                    head = try await client.readRange(path, offset: 0, length: CommonPhotosCaptureKey.headLength)
                } catch let error as RemoteFileError where !error.stopsBatch {
                    continue
                }
                if let key = CommonPhotosCaptureKey.key(fromHead: head) { keys[file] = key }
            }
        }
        return keys
    }
}
