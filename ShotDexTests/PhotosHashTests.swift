import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ShotDex

/// FS-19.02 §1b — Photos assets take part in content identity.
@MainActor
@Suite struct PhotosHashTests {
    /// AC-49: hashing two Photos originals reads each into memory once,
    /// stores a fast and a full hash for its copy, and leaves no file behind:
    /// nothing the size of an original appears in the temporary or caches
    /// folders.
    /// A second run has nothing left to do; an unreadable original is skipped
    /// and stays queued.
    @Test func streamsWithoutDiskGrowth() async throws {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch(
            ["A", "B", "gone"].map { PhotoMarksStoreTests.record($0) }, cursorAssetId: nil)
        let originals = [
            "A": try MetadataFixture.encode(.jpeg, options: MetadataFixture.Options()),
            "B": try MetadataFixture.encode(.tiff, options: MetadataFixture.Options()),
        ]
        let reads = Counter()
        let pass = PhotosContentHashPass(store: ContentHashStore(database: database)) { assetId in
            reads.add(assetId)
            guard let data = originals[assetId] else { throw PhotosContentHashPass.ReadError.missingAsset }
            return data
        }
        let started = Date()

        #expect(try await pass.run() == 2)
        let sizes = Set(originals.values.map(\.count))
        #expect(Self.filesWritten(since: started).filter { sizes.contains($0.value) }.isEmpty)
        #expect(reads.ids.sorted() == ["A", "B", "gone"])

        let store = ContentHashStore(database: database)
        let a = try #require(try store.hash(copyId: "photos:A"))
        #expect(a == (try ContentHasher.hash(DataBytes(data: originals["A"]!), full: true)))
        #expect(try store.hash(copyId: "photos:gone") == nil)

        #expect(try await pass.run() == 0)
        #expect(try store.photosCopiesNeedingHash(limit: 10).map(\.assetId) == ["gone"])
    }

    /// Files under the app's temporary and caches folders written since
    /// `start`, with their sizes — other tests may write there too, so the
    /// check looks for a file the size of an original.
    private static func filesWritten(since start: Date) -> [String: Int] {
        var out: [String: Int] = [:]
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let roots = [FileManager.default.temporaryDirectory,
                     FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]]
        for root in roots {
            guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys)) else { continue }
            for case let url as URL in walk {
                guard let values = try? url.resourceValues(forKeys: keys),
                      let modified = values.contentModificationDate, modified >= start else { continue }
                out[url.path] = values.fileSize ?? 0
            }
        }
        return out
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var _ids: [String] = []
        var ids: [String] { lock.withLock { _ids } }
        func add(_ id: String) { lock.withLock { _ids.append(id) } }
    }
}
