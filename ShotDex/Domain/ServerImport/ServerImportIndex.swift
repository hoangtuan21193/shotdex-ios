import Foundation

/// Which server photos the library already has (FS-17 §4): a file whose
/// path and size match an upload or download row, and whose asset is still
/// in the library.
enum ServerImportIndex {
    static func inLibrary(
        photos: [ServerPhoto],
        folder: String,
        known: [KnownRemoteFile],
        existingAssetIds: Set<String>
    ) -> Set<String> {
        let present = Dictionary(grouping: known.filter { existingAssetIds.contains($0.assetId) }, by: \.remotePath)
        var result = Set<String>()
        for photo in photos {
            let matched = photo.files.contains { file in
                present[ServerUploadPath.join(folder, file.name)]?.contains { $0.byteCount == file.size } ?? false
            }
            if matched { result.insert(photo.id) }
        }
        return result
    }

    /// The SHA-256 a history row already knows for this exact file, if any —
    /// the check a download must pass (FS-17.02 §2).
    static func knownChecksum(path: String, size: Int64, known: [KnownRemoteFile]) -> String? {
        known.first { $0.remotePath == path && $0.byteCount == size }?.sha256
    }
}
