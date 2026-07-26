import Foundation
import os
import Testing
@testable import ShotDex

struct AsyncChunkedLookupCacheTests {

    @MainActor
    @Test func cacheMissReturnsImmediatelyThenPublishesChunk() async {
        let fetchState = OSAllocatedUnfairLock(initialState: (count: 0, ranOnMain: false))
        let cache = AsyncChunkedLookupCache<Int>(chunkSize: 3, maxChunks: 2) { ids in
            fetchState.withLock {
                $0.count += 1
                $0.ranOnMain = Thread.isMainThread
            }
            return Dictionary(uniqueKeysWithValues: ids.map { ($0, Int($0.dropFirst(2))!) })
        }
        cache.replaceKeys((0..<6).map { "id\($0)" })

        #expect(cache.value(at: 1) == nil)
        let resolved = await waitForValue { cache.value(at: 1) }

        #expect(resolved == 1)
        #expect(fetchState.withLock { $0.count } == 1)
        #expect(fetchState.withLock { $0.ranOnMain } == false)
    }

    @MainActor
    @Test func changingIdsDiscardsOldGeneration() async {
        let cache = AsyncChunkedLookupCache<String>(chunkSize: 2, maxChunks: 2) { ids in
            if ids.first == "old" {
                Thread.sleep(forTimeInterval: 0.02)
            }
            return Dictionary(uniqueKeysWithValues: ids.map { ($0, $0) })
        }

        cache.replaceKeys(["old"])
        #expect(cache.value(at: 0) == nil)
        cache.replaceKeys(["new"])
        #expect(cache.value(at: 0) == nil)

        let resolved = await waitForValue { cache.value(at: 0) }
        #expect(resolved == "new")
    }

    @MainActor
    private func waitForValue<Value>(
        _ read: () -> Value?
    ) async -> Value? {
        for _ in 0..<200 {
            if let value = read() {
                return value
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return nil
    }
}
