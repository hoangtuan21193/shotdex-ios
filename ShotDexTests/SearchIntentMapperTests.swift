import Foundation
import Testing

@testable import ShotDex

/// The AI path's only gate. `AISearchTranslator` cannot be tested without an
/// Apple-Intelligence device, which is exactly why every decision it makes is
/// here instead.
struct SearchIntentMapperTests {
    private func rule(_ field: String, _ comparison: String, text: String? = nil,
                      value: Double? = nil, upper: Double? = nil) -> SmartAlbumRule? {
        SearchIntentMapper.rule(
            from: GeneratedSearchRule(
                field: field, comparison: comparison,
                text: text, value: value, upperValue: upper
            )
        )
    }

    @Test func aFieldOrComparisonTheAppDoesNotHaveIsDropped() {
        #expect(rule("colour", "is", text: "red") == nil)
        #expect(rule("iso", "approximately", value: 400) == nil)
        // Empty output produces no query at all rather than an empty match-all.
        #expect(SearchIntentMapper.rules(from: []).isEmpty)
    }

    @Test func synonymsForTheSameFieldAllLand() {
        #expect(rule("location", "contains", text: "Fukuoka")?.field == .place)
        #expect(rule("city", "contains", text: "Fukuoka")?.field == .place)
        #expect(rule("fnumber", "greater", value: 1.2)?.field == .aperture)
        #expect(rule("focallength", "less", value: 35)?.field == .focalLength)
        #expect(rule("make", "contains", text: "Canon")?.field == .cameraBrand)
    }

    @Test func numbersOutsideWhatAPhotoCanHaveAreRefused() {
        // A rule here would show a confident chip over an empty grid.
        #expect(rule("iso", "is", value: 1.4) == nil)
        #expect(rule("aperture", "is", value: 3_200) == nil)
        #expect(rule("focal", "is", value: 100_000) == nil)
        #expect(rule("iso", "greater", value: 3_200)?.op == .greaterThan)
    }

    @Test func aRangeMissingItsUpperBoundIsNotAHalfRule() {
        #expect(rule("iso", "range", value: 100) == nil)
        let ordered = rule("iso", "between", value: 400, upper: 100)
        // Bounds arrive in whichever order the model wrote them.
        #expect(ordered?.number == 100)
        #expect(ordered?.numberUpper == 400)
    }

    @Test func daysAndEpochsAreNotConfusedForEachOther() {
        // "last 30 days" is a count. A model that passes an epoch here would be
        // asking for the last fifty-six thousand years.
        #expect(rule("date", "lastdays", value: 30)?.number == 30)
        #expect(rule("date", "lastdays", value: 1_700_000_000) == nil)
        // And an epoch that is really milliseconds is out of range.
        #expect(rule("date", "before", value: 1_700_000_000_000) == nil)
        #expect(rule("date", "before", value: 1_577_836_800)?.op == .before)
    }

    @Test func choiceValuesAreMatchedLooselyAgainstTheClosedSet() {
        #expect(rule("filetype", "is", text: "JPEG")?.text == PhotoFileType.jpeg.rawValue)
        #expect(rule("filetype", "is", text: "jpg")?.text == PhotoFileType.jpeg.rawValue)
        #expect(rule("format", "is", text: "RAW")?.text == PhotoFileType.raw.rawValue)
        #expect(rule("sensor", "is", text: "full frame")?.text == SensorFormat.fullFrame.rawValue)
        #expect(rule("filetype", "is", text: "webp") == nil)
        // A negated choice keeps its meaning through the operator swap.
        #expect(rule("filetype", "not", text: "raw")?.op == .isNot)
    }

    @Test func favoriteCarriesItsPolarity() {
        #expect(rule("favorite", "is")?.boolValue == true)
        #expect(rule("favorite", "not")?.boolValue == false)
    }

    @Test func textRulesNeedActualText() {
        #expect(rule("place", "contains", text: "  ") == nil)
        #expect(rule("place", "contains") == nil)
        #expect(rule("place", "is", text: "Tokyo")?.op == .isExactly)
    }
}
