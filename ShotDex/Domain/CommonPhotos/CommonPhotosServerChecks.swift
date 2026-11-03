import Foundation

/// Checks against the server that gathering (FS-19.08 §6) and undoing it
/// (§6b) share, so both ask the same questions the same way.
struct CommonPhotosServerChecks: Sendable {
    let client: any RemoteFileClient

    /// Asked again right before a copy is moved or removed: the same size
    /// and write time as at the scan, or — with no write time to go by —
    /// the same SHA-256.
    func isUnchanged(_ source: CommonPhotosItem.Source, sha256: String) async throws -> Bool {
        let folder = ServerUploadPath.parent(of: source.path)
        let name = ServerUploadPath.lastComponent(of: source.path)
        guard let entry = try await client.entries(in: folder).first(where: { $0.name == name && !$0.isDirectory }),
              entry.size == source.size else { return false }
        if let modifiedAt = source.modifiedAt {
            return entry.modified.map { Int($0.timeIntervalSince1970) } == modifiedAt
        }
        return try await client.sha256(of: source.path, progress: { _ in }) == sha256
    }

    /// Whether `path` holds `size` bytes hashing to `sha256`; false when it
    /// is not there.
    func holds(_ path: String, size: Int64, sha256: String) async throws -> Bool {
        guard try await client.fileSize(at: path) == size else { return false }
        return try await client.sha256(of: path, progress: { _ in }) == sha256
    }

    /// A path as two spellings of one place compare: folder form, NFC,
    /// lowercased.
    static func comparable(_ path: String) -> String {
        ServerUploadPath.normalizedFolder(path).precomposedStringWithCanonicalMapping.lowercased()
    }

    /// Where a photo's sidecar goes beside `photoName` in `folder`: the
    /// photo's final name with the sidecar's own form — `IMG_2 (2).xmp`, or
    /// `IMG_2 (2).JPG.xmp` for a full-name sidecar.
    static func sidecarTarget(_ sidecar: String, photoPath: String, photoName: String, folder: String) -> String {
        let sidecarName = ServerUploadPath.lastComponent(of: sidecar)
        let isFullName = sidecarName.lowercased() == ServerUploadPath.lastComponent(of: photoPath).lowercased() + ".xmp"
        let ext = (sidecarName as NSString).pathExtension
        let name = isFullName ? photoName + "." + ext : (photoName as NSString).deletingPathExtension + "." + ext
        return ServerUploadPath.join(folder, name)
    }
}
