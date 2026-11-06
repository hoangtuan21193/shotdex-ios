import CryptoKit
import Foundation

/// FS-19.08 §6d: one copy Compare shows whole — from its cache when it is
/// there, else read from the server in chunks, each one call, so the
/// connection is free between them and the scan's calls go first
/// (`ConnectionLock.Priority.compare`, AC-184). The bytes are checked against
/// the SHA-256 the scan proved before the file takes its place; a read
/// cancelled or failed leaves nothing behind.
struct CommonPhotosCompareLoader: Sendable {
    enum Outcome: Equatable, Sendable {
        case file(URL)
        /// The bytes on the server are not the ones the scan proved.
        case changed
        /// Reading it would leave less than the margin free.
        case noRoom
    }

    /// One call each: long enough to keep a NAS busy, short enough that the
    /// scan waits for at most one of them.
    static let chunkBytes = 4 * 1024 * 1024

    let client: any RemoteFileClient
    let cache: CompareFileCache
    /// Free bytes on the volume the cache sits on.
    var freeBytes: @Sendable () -> Int64 = { Int64.max }
    /// What every write here leaves free (FS-22.02 §2).
    var margin: Int64 = BackupRunner.minimumFreeBytes
    var chunkBytes = CommonPhotosCompareLoader.chunkBytes

    func load(path: String, sha256: String, size: Int64,
              progress: @escaping @Sendable (Int64) -> Void = { _ in }) async throws -> Outcome {
        if let cached = cache.cached(path: path, sha256: sha256) { return .file(cached) }
        guard freeBytes() - size >= margin else { return .noRoom }
        try FileManager.default.createDirectory(at: cache.directory, withIntermediateDirectories: true)
        let target = cache.url(forPath: path, sha256: sha256)
        // A part of its own: a load that overlaps this one (the row shown
        // again) never writes into or removes this one's bytes.
        let part = target.appendingPathExtension("part-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: part) }
        guard FileManager.default.createFile(atPath: part.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let handle = try FileHandle(forWritingTo: part)
        var hash = SHA256()
        var offset: Int64 = 0
        do {
            while offset < size {
                try Task.checkCancellation()
                let chunk = try await client.readRange(path, offset: offset, length: Int(min(Int64(chunkBytes), size - offset)))
                guard !chunk.isEmpty else { break }
                try handle.write(contentsOf: chunk)
                hash.update(data: chunk)
                offset += Int64(chunk.count)
                progress(offset)
            }
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        try Task.checkCancellation()
        // A Quick Check row has no SHA-256 to hold the copy to (§6e): the
        // size is all there is to check.
        let isQuick = sha256.hasPrefix(CommonPhoto.quickPrefix)
        guard offset == size, isQuick || FileChecksum.hex(hash.finalize()) == sha256 else { return .changed }
        // Another load of the same copy may have finished first: its file stands.
        if !FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.moveItem(at: part, to: target)
        }
        cache.stored(path: path, sha256: sha256, size: size)
        return .file(target)
    }
}
