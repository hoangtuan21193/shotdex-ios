import Foundation
import Testing
@testable import ShotDex

/// FS-19.08 §6d: Compare's downloads stay within their cap, never lose the
/// row on screen, and go when Compare closes.
@Suite struct CompareFileCacheTests {
    private func store(_ cache: CompareFileCache, _ path: String, size: Int) throws {
        let url = cache.url(forPath: path, sha256: "sha-" + path)
        try FileManager.default.createDirectory(at: cache.directory, withIntermediateDirectories: true)
        try Data(count: size).write(to: url)
        cache.stored(path: path, sha256: "sha-" + path, size: Int64(size))
    }

    /// AC-182: over the cap, the least recently shown goes first — never a
    /// file of the row on screen; closing empties the folder.
    @Test func capsAndCleansUp() throws {
        let cache = CompareFileCache(capacity: 250)
        try store(cache, "A/1.JPG", size: 100)
        try store(cache, "B/1.JPG", size: 100)
        // A/1 shown again: B/1 is now the oldest.
        #expect(cache.cached(path: "A/1.JPG", sha256: "sha-A/1.JPG") != nil)
        cache.pin(paths: [(path: "B/1.JPG", sha256: "sha-B/1.JPG"), (path: "A/2.JPG", sha256: "sha-A/2.JPG")])
        try store(cache, "A/2.JPG", size: 100)

        // 300 > 250: the oldest unpinned (A/1) went; pinned B/1 stayed.
        #expect(cache.cached(path: "A/1.JPG", sha256: "sha-A/1.JPG") == nil)
        #expect(cache.cached(path: "B/1.JPG", sha256: "sha-B/1.JPG") != nil)
        #expect(cache.totalBytes == 200)

        cache.removeAll()
        #expect(!FileManager.default.fileExists(atPath: cache.directory.path))
    }
}
