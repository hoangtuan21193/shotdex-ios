import Foundation

/// The folder one Combine Photos save works in: every original is written
/// here and read back lazily from disk, so a forty-frame save holds file
/// handles, not forty originals' bytes (FS-01.10 §6).
///
/// Gone when the save ends, succeeded or not — a cancelled save leaves nothing
/// behind (AC-13).
final class PhotoStackSession {
    let folder: URL

    init(root: URL = FileManager.default.temporaryDirectory) throws {
        folder = root.appendingPathComponent("PhotoStack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Writes one original and returns where it went. `index` keeps names
    /// unique; the order of frames is the caller's, not the folder's.
    func store(_ data: Data, index: Int) throws -> URL {
        let url = folder.appendingPathComponent(String(format: "frame-%04d", index))
        try data.write(to: url)
        return url
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }

    deinit { remove() }
}
