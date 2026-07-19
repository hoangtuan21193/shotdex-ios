import Foundation

/// Index-addressed lookup cache with chunked loading and LRU eviction.
///
/// The Library grid holds the whole library as slim rows but must not hold
/// a `PHAsset` per photo — this cache resolves values (PHAssets) for the
/// visible band only: a miss loads the surrounding chunk of ids via `fetch`,
/// and chunks beyond `maxChunks` are evicted least-recently-used, bounding
/// memory to `chunkSize * maxChunks` values however far the user scrolls.
///
/// Pure and generic so eviction/boundary math is unit-testable (`PHAsset`
/// can't be constructed in tests).
final class ChunkedLookupCache<Value> {
    private let chunkSize: Int
    private let maxChunks: Int
    private let fetch: ([String]) -> [String: Value]

    private var ids: [String] = []
    private var chunks: [Int: [String: Value]] = [:]
    /// Chunk indexes, most recently used first.
    private var lru: [Int] = []

    init(chunkSize: Int, maxChunks: Int, fetch: @escaping ([String]) -> [String: Value]) {
        precondition(chunkSize > 0 && maxChunks > 0)
        self.chunkSize = chunkSize
        self.maxChunks = maxChunks
        self.fetch = fetch
    }

    /// Replaces the id list (content reload); drops every cached chunk —
    /// indexes into the old ordering are meaningless against the new one.
    func setIds(_ ids: [String]) {
        self.ids = ids
        removeAll()
    }

    func removeAll() {
        chunks = [:]
        lru = []
    }

    /// Value for the id at `index` in the current id list, loading its
    /// chunk on a miss. Returns nil when out of range or when `fetch`
    /// didn't return the id (e.g. asset deleted from the library).
    func value(at index: Int) -> Value? {
        guard ids.indices.contains(index) else { return nil }
        let chunkIndex = index / chunkSize
        if chunks[chunkIndex] == nil {
            let range = (chunkIndex * chunkSize)..<min((chunkIndex + 1) * chunkSize, ids.count)
            chunks[chunkIndex] = fetch(Array(ids[range]))
        }
        touch(chunkIndex)
        return chunks[chunkIndex]?[ids[index]]
    }

    private func touch(_ chunkIndex: Int) {
        lru.removeAll { $0 == chunkIndex }
        lru.insert(chunkIndex, at: 0)
        while lru.count > maxChunks, let evicted = lru.popLast() {
            chunks.removeValue(forKey: evicted)
        }
    }
}
