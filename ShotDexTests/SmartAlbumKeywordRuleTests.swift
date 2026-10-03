import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-02.07 §7 — the Keyword and Caption fields of the rule builder, compiled
/// through the one SQL builder the grid, the sheet's footer count and the
/// Statistics charts all use.
@MainActor
struct SmartAlbumKeywordRuleTests {

    /// 200 photos: 40 with `Sunset` (5 of them spelled `sunset`), 10 with
    /// `Hoi An` only, 150 with no keyword at all; 3 captions.
    static func library() throws -> AppDatabase {
        let ids = (0..<200).map { String(format: "k%03d", $0) }
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch(ids.map { PhotoMarksStoreTests.record($0) }, cursorAssetId: nil)
        var values: [String: CaptionKeywords] = [:]
        for (index, id) in ids.enumerated() {
            switch index {
            case 0..<35: values[id] = CaptionKeywords(keywords: ["Sunset", "beach"])
            case 35..<40: values[id] = CaptionKeywords(keywords: ["sunset"])
            case 40..<50: values[id] = CaptionKeywords(keywords: ["Hoi An"])
            default: break
            }
        }
        values[ids[0]]?.caption = "Wedding at the beach"
        values[ids[60]] = CaptionKeywords(caption: "Đám cưới ở Hội An — wedding")
        values[ids[61]] = CaptionKeywords(caption: "Street food")
        try PhotoKeywordStore(database: database).replace(values)
        return database
    }

    static func album(_ rule: SmartAlbumRule) -> SmartAlbumQuery {
        SmartAlbumQuery(matchMode: .all, rules: [rule])
    }

    /// AC-8: *Keyword has Sunset* counts 40 (both spellings, any case typed);
    /// *Keyword has no keywords* counts 150 — the sheet footer's count and the
    /// grid agree.
    @Test func hasSunsetAndHasNone() async throws {
        let queries = LibraryQueries(database: try Self.library())
        let sunset = Self.album(SmartAlbumRule(field: .keyword, op: .hasKeyword, text: "SUNSET"))
        #expect(try await queries.count(matching: sunset) == 40)
        #expect(try await queries.gridItems(matching: sunset, sort: .dateTakenNewest).count == 40)

        let none = Self.album(SmartAlbumRule(field: .keyword, op: .hasNoKeywords))
        #expect(none.rules.first?.isValid == true)
        #expect(try await queries.count(matching: none) == 150)
        #expect(try await queries.gridItems(matching: none, sort: .dateTakenNewest).count == 150)

        let any = Self.album(SmartAlbumRule(field: .keyword, op: .hasAnyKeyword))
        #expect(try await queries.count(matching: any) == 50)
        let notSunset = Self.album(SmartAlbumRule(field: .keyword, op: .lacksKeyword, text: "sunset"))
        #expect(try await queries.count(matching: notSunset) == 160)
    }

    /// Caption contains / doesn't contain, without regard to case or
    /// diacritics, as place search does.
    @Test func captionContains() async throws {
        let queries = LibraryQueries(database: try Self.library())
        let wedding = Self.album(SmartAlbumRule(field: .caption, op: .contains, text: "WEDDING"))
        #expect(try await queries.count(matching: wedding) == 2)
        let hoiAn = Self.album(SmartAlbumRule(field: .caption, op: .contains, text: "hoi an"))
        #expect(try await queries.count(matching: hoiAn) == 1)
        let notWedding = Self.album(SmartAlbumRule(field: .caption, op: .doesNotContain, text: "wedding"))
        #expect(try await queries.count(matching: notWedding) == 198)
    }

    /// The chart editor builds its condition with the same rows and the same
    /// SQL (❓-1): a count chart filtered on *Keyword has Sunset* counts 40.
    @Test func keywordConditionFiltersChart() throws {
        let statistics = StatisticsQueries(database: try Self.library())
        let spec = ChartSpec(
            title: "Sunsets", kind: .kpi, dimension: nil,
            filter: Self.album(SmartAlbumRule(field: .keyword, op: .hasKeyword, text: "Sunset"))
        )
        #expect(try statistics.chartData(for: spec, scope: .allTime).first?.value == 40)
        let byCamera = ChartSpec(
            title: "Sunsets by camera", kind: .bar, dimension: .cameraBody,
            filter: Self.album(SmartAlbumRule(field: .keyword, op: .hasKeyword, text: "Sunset"))
        )
        #expect(try statistics.chartData(for: byCamera, scope: .allTime).map(\.value).reduce(0, +) == 40)
    }

    /// The new operators and fields survive a save and a decode; a keyword
    /// rule needs a value only for has / doesn't have.
    @Test func decodesAndValidates() throws {
        let query = SmartAlbumQuery(matchMode: .any, rules: [
            SmartAlbumRule(field: .keyword, op: .hasKeyword, text: "Sunset"),
            SmartAlbumRule(field: .keyword, op: .hasNoKeywords),
            SmartAlbumRule(field: .caption, op: .doesNotContain, text: "wedding"),
        ])
        let decoded = try JSONDecoder().decode(SmartAlbumQuery.self, from: JSONEncoder().encode(query))
        #expect(decoded == query)
        #expect(!SmartAlbumRule(field: .keyword, op: .hasKeyword, text: " ").isValid)
        #expect(SmartAlbumRule(field: .keyword, op: .hasAnyKeyword).isValid)
        #expect(!SmartAlbumRule(field: .caption, op: .contains).isValid)
        #expect(RuleField.keyword.kind.allowedOperators == [.hasKeyword, .lacksKeyword, .hasAnyKeyword, .hasNoKeywords])
        #expect(RuleField.caption.kind.allowedOperators == [.contains, .doesNotContain])
    }

    /// Chips: `keyword: Sunset`, `no keywords`, `caption contains "wedding"`.
    @Test func chips() {
        let en = Locale(identifier: "en")
        #expect(KeywordCopy.chip(for: SmartAlbumRule(field: .keyword, op: .hasKeyword, text: "Sunset"), locale: en) == "keyword: Sunset")
        #expect(KeywordCopy.chip(for: SmartAlbumRule(field: .keyword, op: .hasNoKeywords), locale: en) == "no keywords")
        #expect(KeywordCopy.chip(for: SmartAlbumRule(field: .caption, op: .contains, text: "wedding"), locale: en) == "caption contains \"wedding\"")
    }

    /// AC-14: below iOS 27 the field menu has neither field.
    @Test func fieldsHiddenBelow27() {
        let hidden = RuleField.selectableCases(extendedMetadata: false)
        #expect(!hidden.contains(.keyword) && !hidden.contains(.caption))
        let shown = RuleField.selectableCases(extendedMetadata: true)
        #expect(shown.contains(.keyword) && shown.contains(.caption))
        #expect(!shown.contains(.mediaType))
    }
}
