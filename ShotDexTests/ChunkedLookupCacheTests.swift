import Foundation
import Testing
@testable import ShotDex

struct ChunkedLookupCacheTests {

    /// Cache over ids "id0"..."id(count-1)" mapping to their index, with a
    /// fetch-call recorder.
    private func makeCache(
        count: Int,
        chunkSize: Int,
        maxChunks: Int,
        fetchedChunks: @escaping ([String]) -> Void = { _ in }
    ) -> ChunkedLookupCache<Int> {
        let cache = ChunkedLookupCache<Int>(chunkSize: chunkSize, maxChunks: maxChunks) { ids in
            fetchedChunks(ids)
            return Dictionary(uniqueKeysWithValues: ids.compactMap { id in
                Int(id.dropFirst(2)).map { (id, $0) }
            })
        }
        cache.setIds((0..<count).map { "id\($0)" })
        return cache
    }

    @Test func resolvesValuesAndChunkBoundaries() {
        var fetches: [[String]] = []
        let cache = makeCache(count: 10, chunkSize: 4, maxChunks: 3) { fetches.append($0) }

        #expect(cache.value(at: 0) == 0)
        #expect(cache.value(at: 3) == 3)
        // Same chunk — one fetch of the first 4 ids.
        #expect(fetches == [["id0", "id1", "id2", "id3"]])

        #expect(cache.value(at: 4) == 4)
        #expect(fetches.count == 2)
        // Final partial chunk clamps to the id count.
        #expect(cache.value(at: 9) == 9)
        #expect(fetches.last == ["id8", "id9"])
    }

    @Test func outOfRangeReturnsNil() {
        let cache = makeCache(count: 5, chunkSize: 4, maxChunks: 2)
        #expect(cache.value(at: -1) == nil)
        #expect(cache.value(at: 5) == nil)
    }

    @Test func missingIdInFetchResultReturnsNil() {
        let cache = ChunkedLookupCache<Int>(chunkSize: 2, maxChunks: 2) { _ in [:] }
        cache.setIds(["a", "b"])
        #expect(cache.value(at: 0) == nil)
    }

    @Test func evictsLeastRecentlyUsedChunk() {
        var fetches: [[String]] = []
        let cache = makeCache(count: 12, chunkSize: 2, maxChunks: 2) { fetches.append($0) }

        _ = cache.value(at: 0)   // chunk 0
        _ = cache.value(at: 2)   // chunk 1
        _ = cache.value(at: 0)   // chunk 0 touched — chunk 1 is now LRU
        _ = cache.value(at: 4)   // chunk 2 — evicts chunk 1
        #expect(fetches.count == 3)

        _ = cache.value(at: 0)   // chunk 0 still cached
        #expect(fetches.count == 3)
        _ = cache.value(at: 2)   // chunk 1 was evicted — re-fetches
        #expect(fetches.count == 4)
    }

    @Test func setIdsResetsChunks() {
        var fetches = 0
        let cache = makeCache(count: 4, chunkSize: 4, maxChunks: 2) { _ in fetches += 1 }
        _ = cache.value(at: 0)
        #expect(fetches == 1)

        cache.setIds(["id0", "id1"])
        _ = cache.value(at: 0)
        #expect(fetches == 2)
        // New list is shorter — old indexes are out of range.
        #expect(cache.value(at: 2) == nil)
    }

    @Test func removeAllDropsChunksButKeepsIds() {
        var fetches = 0
        let cache = makeCache(count: 4, chunkSize: 2, maxChunks: 2) { _ in fetches += 1 }
        _ = cache.value(at: 0)
        cache.removeAll()
        #expect(cache.value(at: 0) == 0)
        #expect(fetches == 2)
    }
}
