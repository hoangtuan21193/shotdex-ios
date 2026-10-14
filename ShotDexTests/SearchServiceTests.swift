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

    // MARK: AI Search model (FS-08.07 §5)

    /// A model that answers late, or never in time.
    private struct SlowModel: SearchModel {
        var delay: Duration
        var timeout: Duration
        func translate(_ query: String, vocabulary: FilterSuggestionCatalog) async -> [SmartAlbumRule]? {
            try? await Task.sleep(for: delay)
            return [SmartAlbumRule(field: .anyText, op: .contains, text: "model")]
        }
    }

    private func service(_ model: (any SearchModel)?) throws -> SearchService {
        let database = try AppDatabase.makeEmpty()
        let defaults = UserDefaults(suiteName: "search-\(UUID().uuidString)")!
        return SearchService(
            filterSuggestions: FilterSuggestionCache(libraryQueries: LibraryQueries(database: database)),
            recentSearches: RecentSearchStore(defaults: defaults),
            model: { model }
        )
    }

    /// AC-6: a model that is still thinking when its time is up is
    /// dropped; the parser's reading is applied, with no error.
    @Test func networkModelTimesOutToParser() async throws {
        // 10 s against a 200 ms timeout: well under 10 s proves the cut-off,
        // with room for a busy test run.
        let late = try service(SlowModel(delay: .seconds(10), timeout: .milliseconds(200)))
        let started = Date()
        let resolution = await late.resolve("ảnh hoàng hôn 85mm")
        #expect(Date().timeIntervalSince(started) < 5)
        #expect(!resolution.usedModel)
        #expect(resolution.query.rules.contains { $0.field == .focalLength || $0.field == .lens })

        let quick = try service(SlowModel(delay: .milliseconds(10), timeout: .seconds(2)))
        let answered = await quick.resolve("ảnh hoàng hôn 85mm")
        #expect(answered.usedModel)
    }

    /// AC-7: a cloud provider never becomes the AI Search model, even if a
    /// stored choice names one; a home server does.
    @Test func cloudProviderNeverUsed() {
        let claude = AIProvider(id: "c1", kind: .claude, name: "Claude", model: "m")
        let home = AIProvider(id: "h1", kind: .homeServer, name: "Mac Studio", address: "http://10.0.0.2:11434", model: "qwen3:14b")
        #expect(SearchModelFactory.make(choice: .provider("c1"), providers: [claude, home], key: { _ in "k" }) { nil } == nil)
        #expect(SearchModelFactory.make(choice: .provider("h1"), providers: [claude, home], key: { _ in nil }) { nil } is HomeServerSearchModel)
        #expect(SearchModelFactory.make(choice: .off, providers: [claude, home], key: { _ in nil }) { nil } == nil)
    }
}
