import Foundation
import GRDB
import os
import Testing
@testable import ShotDex

/// Photos' caption and keywords as a fake `ExtendedMetadataReading` sees
/// them: only the ids it holds exist (a `.limited` library holds only the
/// shared ones). Counts fetches — each `read` is one prefetched PhotoKit fetch.
final class FakeExtendedMetadataReader: ExtendedMetadataReading, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<State>(initialState: State())

    private struct State {
        var values: [String: CaptionKeywords] = [:]
        var fetches = 0
        var idsRead = 0
    }

    init(_ values: [String: CaptionKeywords] = [:]) {
        lock.withLock { $0.values = values }
    }

    var fetches: Int { lock.withLock { $0.fetches } }
    var idsRead: Int { lock.withLock { $0.idsRead } }

    func set(_ id: String, _ value: CaptionKeywords?) {
        lock.withLock { $0.values[id] = value }
    }

    func read(ids: [String]) -> [String: CaptionKeywords] {
        lock.withLock { state in
            state.fetches += 1
            state.idsRead += ids.count
            return ids.reduce(into: [:]) { result, id in
                if let value = state.values[id] { result[id] = value }
            }
        }
    }
}

/// FS-02.07 §8 — the full read of the mirror and its refreshes.
@MainActor
struct ExtendedMetadataMirrorPassTests {

    static func indexed(_ ids: [String]) throws -> (AppDatabase, PhotoKeywordStore) {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch(ids.map { PhotoMarksStoreTests.record($0) }, cursorAssetId: nil)
        return (database, PhotoKeywordStore(database: database))
    }

    static func ids(_ count: Int) -> [String] {
        (0..<count).map { String(format: "asset-%06d", $0) }
    }

    /// AC-16: under `.limited` only the 10 shared photos are indexed, so only
    /// they are read and mirrored — and `Private`, which lives only on a photo
    /// not shared, is never suggested even when an old row for it lingers.
    @Test func limitedSeesOnlyShared() async throws {
        let shared = Self.ids(10)
        let (database, store) = try Self.indexed(shared)
        var library = Dictionary(uniqueKeysWithValues: shared.map { ($0, CaptionKeywords(keywords: ["trip"])) })
        library["hidden-1"] = CaptionKeywords(keywords: ["Private"])
        let reader = FakeExtendedMetadataReader(library)
        let pass = ExtendedMetadataMirrorPass(store: store, reader: reader)

        let summary = await pass.runFullRead()
        #expect(summary.completed)
        #expect(reader.idsRead == 10)
        let mirrored = try await database.reader.read { db in
            try String.fetchAll(db, sql: "SELECT DISTINCT assetId FROM photo_keyword ORDER BY assetId")
        }
        #expect(mirrored == shared)

        // A row left behind for a photo that is no longer shared.
        try store.replace(["hidden-1": CaptionKeywords(keywords: ["Private"])])
        let suggestions = KeywordInput.suggestions(for: "Pri", in: try store.keywordCounts())
        #expect(suggestions.isEmpty)
    }

    /// 2,500 indexed photos: three pages, one fetch each, in id order.
    @Test func pagesOf1000() async throws {
        let all = Self.ids(2_500)
        let (_, store) = try Self.indexed(all)
        let reader = FakeExtendedMetadataReader(Dictionary(uniqueKeysWithValues: all.map { ($0, CaptionKeywords(keywords: ["x"])) }))
        let pass = ExtendedMetadataMirrorPass(store: store, reader: reader)
        let summary = await pass.runFullRead()
        #expect(summary.pages == 3)
        #expect(reader.fetches == 3)
        #expect(try store.passState().completedAt != nil)
        #expect(try store.keywordCounts() == [KeywordCount(keyword: "x", count: 2_500)])
        // Done means done: a second run reads nothing.
        await pass.runFullRead()
        #expect(reader.fetches == 3)
    }

    /// A run stopped after its first page picks up at the next id.
    @Test func resumesFromCursor() async throws {
        let all = Self.ids(2_000)
        let (_, store) = try Self.indexed(all)
        try store.savePassState(.init(cursorAssetId: all[999], completedAt: nil))
        let reader = FakeExtendedMetadataReader()
        let pass = ExtendedMetadataMirrorPass(store: store, reader: reader)
        let summary = await pass.runFullRead()
        #expect(reader.idsRead == 1_000)
        #expect(summary.pages == 1)
        #expect(summary.completed)
    }

    /// AC-15 (the part a simulator can prove): 55,000 indexed photos with an
    /// empty mirror cost 55 fetches. The PhotoKit reader prefetches extended
    /// metadata on every fetch, so no asset is ever loaded lazily.
    @Test func fetchCountIsPages() async throws {
        let all = Self.ids(55_000)
        let (_, store) = try Self.indexed(all)
        let reader = FakeExtendedMetadataReader()
        let pass = ExtendedMetadataMirrorPass(store: store, reader: reader)
        let summary = await pass.runFullRead()
        #expect(summary.completed)
        #expect(reader.fetches == 55)
        #expect(reader.idsRead == 55_000)
    }

    /// AC-10: Photos reports B updated, its modification date unchanged — the
    /// index skips it (no file read) but the run's changes still carry it,
    /// and the mirror reads B's keywords again.
    @Test func updatedIdsRereadWithoutExif() async throws {
        let (_, store) = try Self.indexed(["A", "B"])
        let reader = FakeExtendedMetadataReader(["A": .empty, "B": .empty])
        let pass = ExtendedMetadataMirrorPass(store: store, reader: reader)
        await pass.runFullRead()

        reader.set("B", CaptionKeywords(keywords: ["Sunset"]))
        let observers = IndexRunObservers()
        observers.add { changes in await pass.handle(changes) }
        await observers.deliver(.incremental(inserted: [], updated: ["B"], deleted: [], accessIsFull: true))

        #expect(try store.value(assetId: "B").keywords == ["Sunset"])
        #expect(try store.value(assetId: "A") == .empty)
    }

    /// AC-10 end to end in the database: after the observer ran, the filter
    /// *Keyword has Sunset* finds B, and B's `photo_metadata` row — date,
    /// EXIF status, every EXIF column — is exactly what it was: nothing read
    /// B's file. (The mirror pass has no file reader at all.)
    @Test func updatedKeywordReachesFilter() async throws {
        let (database, store) = try Self.indexed(["A", "B"])
        let before = try PhotoMarksStoreTests.metadataRow("B", in: database)
        let reader = FakeExtendedMetadataReader(["A": .empty, "B": .empty])
        let pass = ExtendedMetadataMirrorPass(store: store, reader: reader)
        await pass.runFullRead()
        reader.set("B", CaptionKeywords(keywords: ["Sunset"]))
        await pass.handle(.incremental(inserted: [], updated: ["B"], deleted: [], accessIsFull: true))

        let sunset = SmartAlbumQuery(matchMode: .all, rules: [SmartAlbumRule(field: .keyword, op: .hasKeyword, text: "sunset")])
        let ids = try await LibraryQueries(database: database).gridItems(matching: sunset, sort: .dateTakenNewest).map(\.assetId)
        #expect(ids == ["B"])
        let after = try #require(try PhotoMarksStoreTests.metadataRow("B", in: database))
        let original = try #require(before)
        for column in original.columnNames {
            #expect(after[column] as DatabaseValue == original[column] as DatabaseValue, "\(column)")
        }
    }

    /// A full walk (history expired) asks for a new full read instead of
    /// reading the walk's ids twice.
    @Test func fullWalkRestartsFullRead() async throws {
        let (_, store) = try Self.indexed(["A"])
        let reader = FakeExtendedMetadataReader()
        let pass = ExtendedMetadataMirrorPass(store: store, reader: reader)
        await pass.runFullRead()
        #expect(await pass.needsFullRead() == false)
        await pass.handle(IndexRunChanges(changed: ["A"], deleted: [], isFullWalk: true, accessIsFull: true))
        #expect(await pass.needsFullRead())
    }

    /// The pass waits while someone is looking at a photo, between pages.
    @Test func yieldsWhilePaused() async throws {
        let (_, store) = try Self.indexed(Self.ids(10))
        let pauses = OSAllocatedUnfairLock(initialState: 3)
        let pass = ExtendedMetadataMirrorPass(
            store: store,
            reader: FakeExtendedMetadataReader(),
            shouldPause: { pauses.withLock { remaining in
                defer { remaining = max(0, remaining - 1) }
                return remaining > 0
            } },
            sleep: { _ in }
        )
        let summary = await pass.runFullRead()
        #expect(summary.completed)
        #expect(pauses.withLock { $0 } == 0)
    }
}
