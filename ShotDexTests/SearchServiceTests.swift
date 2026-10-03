import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-02.07 §7 — what a search's words match once parsed: leftovers and plain
/// text reach the Photos caption and keywords.
@MainActor
struct SearchServiceTests {

    /// Three photos in Fukuoka, one of them captioned *Wedding*; one photo
    /// elsewhere also captioned *wedding*; one with the keyword `golden hour`.
    static func library() throws -> AppDatabase {
        let database = try AppDatabase.makeEmpty()
        let ids = ["f1", "f2", "f3", "x1", "g1"]
        try MetadataStore(database: database).saveBatch(ids.map { PhotoMarksStoreTests.record($0) }, cursorAssetId: nil)
        try database.writer.write { db in
            try db.execute(sql: "UPDATE photo_metadata SET placeLocality = 'Fukuoka', placeSearchText = 'fukuoka japan' WHERE assetId IN ('f1','f2','f3')")
        }
        try PhotoKeywordStore(database: database).replace([
            "f2": CaptionKeywords(caption: "Wedding at the harbour"),
            "x1": CaptionKeywords(caption: "Our wedding"),
            "g1": CaptionKeywords(keywords: ["golden hour"]),
        ])
        return database
    }

    /// ⚠️-1 decided 2026-10-03: `fukuoka wedding` keeps the place chip and
    /// matches the rest wherever free text looks — here the caption — so the
    /// answer is the one Fukuoka photo captioned *Wedding*, not none.
    @Test func leftoverWordsMatchCaption() async throws {
        let database = try Self.library()
        let intent = SearchIntentParser.parse(
            "fukuoka wedding",
            vocabulary: FilterSuggestionCatalog(places: ["Fukuoka"]),
            readsKeywords: true
        )
        #expect(intent.leftoverText == "wedding")
        var query = intent.query
        query.rules.append(contentsOf: SearchService.leftoverRules(intent.leftoverText))
        #expect(query.rules.map(\.field) == [.place, .anyText])
        #expect(query.rules.last?.compactDisplaySummary == "\"wedding\"")
        let ids = try await LibraryQueries(database: database).gridItems(matching: query, sort: .dateTakenNewest).map(\.assetId)
        #expect(ids == ["f2"])
    }

    /// AC-9: `keyword:"golden hour"` finds the 1 photo carrying it.
    @Test func keywordPrefixFindsPhotos() async throws {
        let database = try Self.library()
        let intent = SearchIntentParser.parse(#"keyword:"golden hour""#, readsKeywords: true)
        #expect(try await LibraryQueries(database: database).count(matching: intent.query) == 1)
    }
}
