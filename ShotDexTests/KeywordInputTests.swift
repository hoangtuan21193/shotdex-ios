import Foundation
import Testing
@testable import ShotDex

/// FS-02.07 §4 — what one Return in the Add Keyword field writes, and what
/// the suggestions under it show.
struct KeywordInputTests {

    /// AC-3: `sunset, beach` is two keywords; the library's `Sunset` wins
    /// over the lower-case spelling typed.
    @Test func commaSplits() {
        #expect(KeywordInput.split("sunset, beach") == ["sunset", "beach"])
        #expect(KeywordInput.split("  a ,, b ,  ") == ["a", "b"])
        #expect(KeywordInput.split(" , ") == [])
        #expect(KeywordInput.split("Beach, beach, BEACH") == ["Beach"])
    }

    @Test func reusesExistingCase() {
        let existing = KeywordInput.spellings([KeywordCount(keyword: "Sunset", count: 40)])
        #expect(KeywordInput.keywords(from: "sunset, beach", existing: existing) == ["Sunset", "beach"])
        #expect(KeywordInput.spelling(for: "SUNSET", existing: existing) == "Sunset")
    }

    /// `Đà Lạt` and `Da Lat` are two keywords (only case is folded when
    /// choosing a spelling), but one search matches both.
    @Test func diacriticsStayDistinct() {
        let existing = KeywordInput.spellings([KeywordCount(keyword: "Đà Lạt", count: 3)])
        #expect(KeywordInput.spelling(for: "Da Lat", existing: existing) == "Da Lat")
        #expect(KeywordInput.spelling(for: "đà lạt", existing: existing) == "Đà Lạt")
        #expect(KeywordInput.caseKey("Đà Lạt") != KeywordInput.caseKey("Da Lat"))
        #expect(KeywordInput.foldKey("Đà Lạt") == KeywordInput.foldKey("Da Lat"))
    }

    /// AC-3: `sun` → `Sunset 40` first; at most 8, most photos first,
    /// matching without case or diacritics, the photo's own keywords left out.
    @Test func suggestionsRankByCount() {
        let catalog = [
            KeywordCount(keyword: "Sun Valley", count: 3),
            KeywordCount(keyword: "Sunrise", count: 12),
            KeywordCount(keyword: "Sunset", count: 40),
            KeywordCount(keyword: "beach", count: 90),
        ] + (1...10).map { KeywordCount(keyword: "sun\($0)", count: 1) }
        let found = KeywordInput.suggestions(for: "sun", in: catalog)
        #expect(found.count == 8)
        #expect(found.first == KeywordCount(keyword: "Sunset", count: 40))
        #expect(found.prefix(3).map(\.keyword) == ["Sunset", "Sunrise", "Sun Valley"])
        #expect(KeywordInput.suggestions(for: "SÚN", in: catalog).first?.keyword == "Sunset")
        #expect(KeywordInput.suggestions(for: "sun", in: catalog, excluding: ["sunset"]).first?.keyword == "Sunrise")
        #expect(KeywordInput.suggestions(for: "  ", in: catalog).isEmpty)
    }
}
