import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Server thumbnails and capture dates on disk (FS-17 §4), so reopening a
/// folder reads nothing from the server. A file that changed on the server
/// has a new size or write time, and so a new key.
///
/// One `.jpg` per thumbnail and one small `.json` per file (capture date,
/// and whether a thumbnail exists — "none" is remembered too). Least
/// recently used first out once the folder passes `limit`.
final class RemoteThumbnailCache: @unchecked Sendable {
    struct Key: Hashable, Sendable {
        let connectionId: String
        let path: String
        let size: Int64
        let modified: Date?

        var fileStem: String {
            let text = "\(connectionId)|\(path)|\(size)|\(modified?.timeIntervalSince1970 ?? 0)"
            return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }

    struct Entry: @unchecked Sendable {
        /// Nil when the file is known to have no usable preview.
        let image: CGImage?
        /// Whether a thumbnail pass ran (a date-only pass leaves this false).
        let hasThumbnailResult: Bool
        let captureDate: Date?
        let hasCaptureDate: Bool
    }

    private struct Meta: Codable {
        var hasThumbnailResult = false
        var hasImage = false
        var captureDate: Date?
        var hasCaptureDate = false
    }

    let directory: URL
    let limit: Int64
    private let lock = NSLock()

    init(directory: URL, limit: Int64 = 500 * 1024 * 1024) {
        self.directory = directory
        self.limit = limit
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static var standard: RemoteThumbnailCache {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return RemoteThumbnailCache(directory: caches.appendingPathComponent("ServerThumbnails", isDirectory: true))
    }

    func entry(for key: Key) -> Entry? {
        lock.withLock {
            guard let meta = readMeta(key) else { return nil }
            var image: CGImage?
            if meta.hasImage {
                let url = imageURL(key)
                if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                    image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                }
                touch(url)
            }
            touch(metaURL(key))
            return Entry(image: image, hasThumbnailResult: meta.hasThumbnailResult,
                         captureDate: meta.captureDate, hasCaptureDate: meta.hasCaptureDate)
        }
    }

    func store(_ result: RemoteThumbnailResult, for key: Key) {
        lock.withLock {
            var meta = readMeta(key) ?? Meta()
            meta.hasThumbnailResult = true
            meta.hasImage = false
            if let image = result.thumbnail?.image {
                let url = imageURL(key)
                if let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
                    meta.hasImage = CGImageDestinationFinalize(destination)
                }
            }
            if result.captureDate != nil || !meta.hasCaptureDate {
                meta.captureDate = result.captureDate ?? meta.captureDate
                meta.hasCaptureDate = true
            }
            writeMeta(meta, key)
        }
        trim()
    }

    /// A Date Taken pass: the date only, the thumbnail left for later.
    func storeCaptureDate(_ date: Date?, for key: Key) {
        lock.withLock {
            var meta = readMeta(key) ?? Meta()
            meta.captureDate = date
            meta.hasCaptureDate = true
            writeMeta(meta, key)
        }
    }

    /// Drops least recently used files until the folder is under `limit`.
    func trim() {
        lock.withLock {
            let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
            guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
            var entries = files.compactMap { url -> (URL, Int64, Date)? in
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
                return (url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
            }
            var total = entries.reduce(0) { $0 + $1.1 }
            guard total > limit else { return }
            entries.sort { $0.2 < $1.2 }
            for (url, size, _) in entries {
                try? FileManager.default.removeItem(at: url)
                total -= size
                if total <= limit { break }
            }
        }
    }

    func removeAll() {
        lock.withLock {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    // MARK: Files

    private func imageURL(_ key: Key) -> URL { directory.appendingPathComponent(key.fileStem + ".jpg") }
    private func metaURL(_ key: Key) -> URL { directory.appendingPathComponent(key.fileStem + ".json") }

    private func readMeta(_ key: Key) -> Meta? {
        guard let data = try? Data(contentsOf: metaURL(key)) else { return nil }
        return try? JSONDecoder().decode(Meta.self, from: data)
    }

    private func writeMeta(_ meta: Meta, _ key: Key) {
        guard let data = try? JSONEncoder().encode(meta) else { return }
        try? data.write(to: metaURL(key), options: .atomic)
    }

    /// Marks a file used — the eviction order.
    private func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }
}
