import Foundation

/// FS-19.08 §6d: the whole files Compare downloads to show a copy the index
/// has no picture of — in a temporary folder of their own, at most
/// `capacity` bytes (the least recently shown go first, never the files
/// pinned for the row on screen), all removed when Compare closes.
/// `@unchecked Sendable`: every mutable field is read and written under `lock`.
final class CompareFileCache: @unchecked Sendable {
    /// 2 GB (user 2026-11-04).
    static let defaultCapacity: Int64 = 2 * 1024 * 1024 * 1024

    let directory: URL
    let capacity: Int64
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var pinned: Set<String> = []
    private var clock = 0

    private struct Entry {
        let url: URL
        let size: Int64
        var used: Int
    }

    init(capacity: Int64 = CompareFileCache.defaultCapacity,
         parent: URL = FileManager.default.temporaryDirectory) {
        self.capacity = capacity
        directory = parent.appendingPathComponent("ShotDexCompare-\(UUID().uuidString)", isDirectory: true)
    }

    /// Where the copy at `path` with these bytes goes. One key per copy:
    /// each side shows its own file.
    func url(forPath path: String, sha256: String) -> URL {
        // Hex only, whatever the caller passed: the name never makes a folder.
        let name = String(sha256.filter(\.isHexDigit).prefix(16)) + "-" + String(UInt64(bitPattern: Int64(path.hashValue)), radix: 36)
        let ext = (path as NSString).pathExtension
        return directory.appendingPathComponent(ext.isEmpty ? name : "\(name).\(ext)")
    }

    /// The file, when this copy is here already; marks it just shown.
    func cached(path: String, sha256: String) -> URL? {
        lock.withLock {
            let key = Self.key(path, sha256)
            guard var entry = entries[key], FileManager.default.fileExists(atPath: entry.url.path) else { return nil }
            clock += 1
            entry.used = clock
            entries[key] = entry
            return entry.url
        }
    }

    /// The files of the row on screen: never evicted while pinned.
    func pin(paths: [(path: String, sha256: String)]) {
        lock.withLock { pinned = Set(paths.map { Self.key($0.path, $0.sha256) }) }
    }

    /// A file downloaded to `url(forPath:sha256:)`: kept, then the oldest
    /// unpinned go until the folder is within capacity.
    func stored(path: String, sha256: String, size: Int64) {
        lock.withLock {
            clock += 1
            entries[Self.key(path, sha256)] = Entry(url: url(forPath: path, sha256: sha256), size: size, used: clock)
            var total = entries.values.reduce(Int64(0)) { $0 + $1.size }
            for (key, entry) in entries.sorted(by: { $0.value.used < $1.value.used }) where total > capacity {
                guard !pinned.contains(key) else { continue }
                try? FileManager.default.removeItem(at: entry.url)
                entries[key] = nil
                total -= entry.size
            }
        }
    }

    /// Bytes held now.
    var totalBytes: Int64 { lock.withLock { entries.values.reduce(Int64(0)) { $0 + $1.size } } }

    /// Folders a crash or a force-quit left behind: swept at launch.
    static func sweepLeftovers(in parent: URL = FileManager.default.temporaryDirectory) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        for name in names where name.hasPrefix("ShotDexCompare-") {
            try? FileManager.default.removeItem(at: parent.appendingPathComponent(name))
        }
    }

    /// Compare closed: the folder goes.
    func removeAll() {
        lock.withLock {
            entries = [:]
            pinned = []
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static func key(_ path: String, _ sha256: String) -> String { sha256 + "|" + path }
}
