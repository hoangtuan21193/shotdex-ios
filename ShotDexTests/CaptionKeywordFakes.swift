import Foundation
import os
@testable import ShotDex

/// Photos as the caption/keyword tests see it: the writer applies each
/// change to the fake reader's library, counts `performChanges` blocks, can
/// refuse ids (a shared-library photo), fail the whole block, or hold the
/// block open until the test lets it finish.
final class FakeCaptionKeywordWriter: PhotoPropertyWriting, @unchecked Sendable {
    let library: FakeExtendedMetadataReader
    private let lock = OSAllocatedUnfairLock<State>(initialState: State())

    private struct State {
        var blocks: [[String: CaptionKeywordChange]] = []
        var refused: Set<String> = []
        var failure: Error?
        var gate: CheckedContinuation<Void, Never>?
        var holds = false
        var resourceRequests = 0
    }

    /// The modification date every asset has before a write; each write moves
    /// it one second.
    let modificationDate: Int

    init(library: FakeExtendedMetadataReader, modificationDate: Int = 1_700_000_000) {
        self.library = library
        self.modificationDate = modificationDate
    }

    var blocks: [[String: CaptionKeywordChange]] { lock.withLock { $0.blocks } }
    var refused: Set<String> {
        get { lock.withLock { $0.refused } }
        set { lock.withLock { $0.refused = newValue } }
    }
    var failure: Error? {
        get { lock.withLock { $0.failure } }
        set { lock.withLock { $0.failure = newValue } }
    }
    /// Asset resources asked for — the writer has no way to ask, so this
    /// stays 0; a test reads it to say so.
    var resourceRequests: Int { lock.withLock { $0.resourceRequests } }

    /// The next block waits for `release()`.
    func hold() { lock.withLock { $0.holds = true } }

    func release() {
        let gate = lock.withLock { state -> CheckedContinuation<Void, Never>? in
            state.holds = false
            defer { state.gate = nil }
            return state.gate
        }
        gate?.resume()
    }

    var isHolding: Bool { lock.withLock { $0.gate != nil } }

    func setRatings(_ ratings: [String: Int]) async throws -> PropertyWriteResult {
        throw CocoaError(.featureUnsupported)
    }

    func applyCaptionKeywords(_ changes: [String: CaptionKeywordChange]) async throws -> PropertyWriteResult {
        if lock.withLock({ $0.holds }) {
            await withCheckedContinuation { continuation in
                lock.withLock { $0.gate = continuation }
            }
        }
        let (failure, refused) = lock.withLock { ($0.failure, $0.refused) }
        if let failure { throw failure }
        var written: [String: CaptionKeywordChange] = [:]
        var dates: [String: PropertyWriteResult.Dates] = [:]
        for (id, change) in changes where !refused.contains(id) {
            guard let value = library.read(ids: [id])[id] else { continue }
            library.set(id, change.applied(to: value))
            written[id] = change
            dates[id] = .init(before: modificationDate, after: modificationDate + 1)
        }
        let block = written
        lock.withLock { $0.blocks.append(block) }
        return PropertyWriteResult(dates: dates, refused: Set(changes.keys).intersection(refused))
    }
}

/// A `CaptionKeywordService` over an in-memory database and the fakes.
@MainActor
struct CaptionKeywordHarness {
    let database: AppDatabase
    let store: PhotoKeywordStore
    let library: FakeExtendedMetadataReader
    let writer: FakeCaptionKeywordWriter
    let mirror: ExtendedMetadataMirrorPass
    let service: CaptionKeywordService

    init(_ photos: [String: CaptionKeywords], indexed: [String]? = nil) throws {
        database = try AppDatabase.makeEmpty()
        let metadata = MetadataStore(database: database)
        try metadata.saveBatch((indexed ?? Array(photos.keys)).map { PhotoMarksStoreTests.record($0) }, cursorAssetId: nil)
        store = PhotoKeywordStore(database: database)
        library = FakeExtendedMetadataReader(photos)
        writer = FakeCaptionKeywordWriter(library: library)
        mirror = ExtendedMetadataMirrorPass(store: store, reader: library)
        let store = store
        service = CaptionKeywordService(
            writer: writer,
            reader: library,
            mirror: mirror,
            store: store,
            metadataStore: metadata,
            keywordCatalog: { _ in (try? store.keywordCounts()) ?? [] }
        )
    }

    func modificationDate(_ id: String) throws -> Int? {
        try database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT modificationDate FROM photo_metadata WHERE assetId = ?", arguments: [id])
        }
    }
}
