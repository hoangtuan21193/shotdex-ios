import Foundation

private struct UncheckedSendableBox<Wrapped>: @unchecked Sendable {
    let value: Wrapped
}

/// Main-actor, non-blocking counterpart to `ChunkedLookupCache`.
///
/// A cache miss schedules the surrounding chunk on a detached task and returns
/// immediately — with the value carried over from the previous key ordering
/// when there is one, otherwise nil — so collection-view data-source and
/// prefetch callbacks never block on PhotoKit. The caller bumps a
/// lightweight refresh token from
/// `onChunkLoaded`; visible cells then reconfigure and pick up the resolved
/// values. Generation checks discard results from an old id ordering.
@MainActor
final class AsyncChunkedLookupCache<Value> {
    private let chunkSize: Int
    private let maxChunks: Int
    private let fetch: @Sendable ([String]) -> [String: Value]

    private var ids: [String] = []
    private var chunks: [Int: [String: Value]] = [:]
    private var lru: [Int] = []
    private var loadingTasks: [Int: Task<Void, Never>] = [:]
    private var generation = 0
    /// Values resolved under the previous key ordering, kept by key so a
    /// `replaceKeys` that shares keys keeps serving them while the new chunks
    /// resolve. Chunks are indexed by position, so growing the list at the
    /// anchored end (the first-paint slice becoming the whole library) moves
    /// every on-screen tile to a different chunk index — without this the
    /// tiles would all blank for a round trip. Bounded by the chunk budget
    /// and replaced, not accumulated, on each `replaceKeys`.
    private var carriedValues: [String: Value] = [:]

    /// Called on the main actor after a current-generation chunk is installed.
    var onChunkLoaded: (() -> Void)?

    init(
        chunkSize: Int,
        maxChunks: Int,
        fetch: @escaping @Sendable ([String]) -> [String: Value]
    ) {
        precondition(chunkSize > 0 && maxChunks > 0)
        self.chunkSize = chunkSize
        self.maxChunks = maxChunks
        self.fetch = fetch
    }

    /// Replaces the ordered id list and invalidates every cached/in-flight
    /// chunk. Detached fetches that already started may finish, but their
    /// generation no longer matches and their result is ignored. Values already
    /// resolved stay available by key (see `carriedValues`) until the next
    /// replacement, so keys the two orderings share never regress to nil.
    func replaceKeys(_ ids: [String]) {
        let resolved = chunks.values.reduce(into: [String: Value]()) { merged, chunk in
            merged.merge(chunk) { current, _ in current }
        }
        generation &+= 1
        self.ids = ids
        removeAll()
        carriedValues = resolved
    }

    /// Returns a cached value, or schedules its chunk and falls back to the
    /// value carried over from the previous ordering (nil when there is none).
    /// This method is intentionally cheap enough for `cellForItem` and prefetch.
    func value(at index: Int) -> Value? {
        guard ids.indices.contains(index) else { return nil }
        let id = ids[index]
        let chunkIndex = index / chunkSize
        if let value = chunks[chunkIndex]?[id] {
            touch(chunkIndex)
            return value
        }
        loadIfNeeded(chunkIndex)
        return carriedValues[id]
    }

    func removeAll() {
        for task in loadingTasks.values {
            task.cancel()
        }
        loadingTasks = [:]
        chunks = [:]
        lru = []
        carriedValues = [:]
    }

    private func loadIfNeeded(_ chunkIndex: Int) {
        guard chunks[chunkIndex] == nil, loadingTasks[chunkIndex] == nil else { return }
        let lowerBound = chunkIndex * chunkSize
        guard lowerBound < ids.count else { return }
        let upperBound = min(lowerBound + chunkSize, ids.count)
        let chunkIds = Array(ids[lowerBound..<upperBound])
        let requestedGeneration = generation
        let fetch = self.fetch

        loadingTasks[chunkIndex] = Task { [weak self] in
            let transfer = await Task.detached(priority: .userInitiated) {
                UncheckedSendableBox(value: fetch(chunkIds))
            }.value
            guard let self, !Task.isCancelled else { return }
            self.loadingTasks[chunkIndex] = nil
            guard self.generation == requestedGeneration else { return }
            self.chunks[chunkIndex] = transfer.value
            self.touch(chunkIndex)
            self.onChunkLoaded?()
        }
    }

    private func touch(_ chunkIndex: Int) {
        lru.removeAll { $0 == chunkIndex }
        lru.insert(chunkIndex, at: 0)
        while lru.count > maxChunks, let evicted = lru.popLast() {
            chunks.removeValue(forKey: evicted)
        }
    }
}
