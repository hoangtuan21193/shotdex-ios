import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-02.07 §8 — the caption/keyword mirror: two tables that follow
/// `photo_metadata` out of the database but are never written by the indexer.
@MainActor
struct PhotoKeywordStoreTests {

    static func record(_ id: String) -> PhotoMetadata {
        PhotoMarksStoreTests.record(id)
    }

    static func seeded(_ ids: [String]) throws -> (AppDatabase, MetadataStore, PhotoKeywordStore) {
        let database = try AppDatabase.makeEmpty()
        let metadata = MetadataStore(database: database)
        try metadata.saveBatch(ids.map(record), cursorAssetId: nil)
        return (database, metadata, PhotoKeywordStore(database: database))
    }

    @Test func migrationCreatesMirrorTables() throws {
        let database = try AppDatabase.makeEmpty()
        try database.reader.read { db in
            #expect(try db.tableExists("photo_keyword"))
            #expect(try db.tableExists("photo_caption"))
            #expect(try db.tableExists("extended_metadata_state"))
            let indexes = try db.indexes(on: "photo_keyword").map(\.name)
            #expect(indexes.contains("photo_keyword_caseKey"))
            #expect(indexes.contains("photo_keyword_foldKey"))
            // Not a column of the row the indexer rewrites.
            #expect(!(try db.columns(in: "photo_metadata").map(\.name)).contains("caption"))
        }
    }

    /// AC-11: a full reindex (every `photo_metadata` row upserted again by a
    /// newer indexer) leaves A's 2 keywords and caption exactly as they were.
    @Test func fullReindexKeepsMirror() throws {
        let (database, metadata, store) = try Self.seeded(["A", "B"])
        try store.replace(["A": CaptionKeywords(caption: "Sunrise at Ba Na", keywords: ["Sunset", "Hoi An"])])

        var again = Self.record("A")
        again.indexerVersion = PhotoMetadata.currentIndexerVersion + 1
        again.indexedAt = 1_800_000_000
        try metadata.saveBatch([again, Self.record("B")], cursorAssetId: "B")
        try metadata.upsert(again)

        let value = try store.value(assetId: "A")
        #expect(value.keywords == ["Sunset", "Hoi An"])
        #expect(value.caption == "Sunrise at Ba Na")
        let counts = try database.reader.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_keyword WHERE assetId = 'A'"),
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_caption WHERE assetId = 'A'")
            )
        }
        #expect(counts.0 == 2)
        #expect(counts.1 == 1)
    }

    /// A photo that leaves the library takes its mirror rows with it, in the
    /// same transaction as its `photo_metadata` row.
    @Test func deleteAssetsTakesMirror() throws {
        let (_, metadata, store) = try Self.seeded(["A", "B"])
        try store.replace([
            "A": CaptionKeywords(caption: "a", keywords: ["x"]),
            "B": CaptionKeywords(caption: "b", keywords: ["x", "y"]),
        ])
        try metadata.deleteAssets(ids: ["A"])
        #expect(try store.value(assetId: "A") == .empty)
        #expect(try store.value(assetId: "B") == CaptionKeywords(caption: "b", keywords: ["x", "y"]))
    }

    /// Clear local metadata index clears the mirror and where its read stood,
    /// so the next launch reads it again from Photos.
    @Test func clearIndexClearsMirror() throws {
        let (_, metadata, store) = try Self.seeded(["A"])
        try store.replace(["A": CaptionKeywords(caption: "a", keywords: ["x"])])
        try store.savePassState(.init(cursorAssetId: nil, completedAt: 1_800_000_000))
        try metadata.deleteAll()
        #expect(try store.value(assetId: "A") == .empty)
        #expect(try store.passState() == .initial)
    }

    /// Replacing writes what Photos holds now: a keyword gone from the asset
    /// is gone from the mirror, an empty caption is no row.
    @Test func replaceIsWholeAsset() throws {
        let (_, _, store) = try Self.seeded(["A"])
        try store.replace(["A": CaptionKeywords(caption: "old", keywords: ["x", "y"])])
        try store.replace(["A": CaptionKeywords(caption: "  ", keywords: ["y"])])
        #expect(try store.value(assetId: "A") == CaptionKeywords(caption: nil, keywords: ["y"]))
    }

    /// AC-16: a mirror row whose photo is not indexed (not shared under
    /// `.limited`, or gone) is never counted, never suggested.
    @Test func suggestionsIgnoreOrphans() throws {
        let (_, _, store) = try Self.seeded(["A"])
        try store.replace([
            "A": CaptionKeywords(keywords: ["trip"]),
            "unshared": CaptionKeywords(keywords: ["Private", "trip"]),
        ])
        #expect(try store.keywordCounts() == [KeywordCount(keyword: "trip", count: 1)])
    }

    /// AC-3: counts are photos per keyword over every spelling, shown in the
    /// spelling most photos use, most photos first.
    @Test func suggestionsRankByCount() throws {
        let ids = (0..<50).map { "p\($0)" }
        let (_, _, store) = try Self.seeded(ids)
        var values: [String: CaptionKeywords] = [:]
        for (index, id) in ids.enumerated() {
            var keywords: [String] = []
            if index < 38 { keywords.append("Sunset") } else if index < 40 { keywords.append("sunset") }
            if index < 12 { keywords.append("Sunrise") }
            values[id] = CaptionKeywords(keywords: keywords)
        }
        try store.replace(values)
        let counts = try store.keywordCounts()
        #expect(counts.prefix(2) == [KeywordCount(keyword: "Sunset", count: 40), KeywordCount(keyword: "Sunrise", count: 12)])
        #expect(KeywordInput.suggestions(for: "sun", in: counts).first == KeywordCount(keyword: "Sunset", count: 40))
    }
}
