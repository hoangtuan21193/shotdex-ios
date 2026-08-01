import Foundation
import Testing

@testable import ShotDex

struct SearchIntentParserTests {
    /// A fixed Tuesday afternoon, in a fixed zone: every date expectation below is
    /// computed from this, never from the clock.
    private let now: Date
    private let calendar: Calendar
    private let vocabulary = FilterSuggestionCatalog(
        brands: ["Canon", "Sony"],
        bodies: ["Canon EOS R6", "Sony A7 IV"],
        lenses: ["RF 85mm F1.2 L USM"],
        places: ["Fukuoka", "Đà Nẵng", "Tokyo"]
    )

    init() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        self.calendar = calendar
        now = calendar.date(from: DateComponents(year: 2_026, month: 3, day: 17, hour: 15))!
    }

    private func rules(_ query: String) -> [SmartAlbumRule] {
        SearchIntentParser.parse(query, vocabulary: vocabulary, now: now, calendar: calendar)
            .query.rules
    }

    /// What a rule *means*, without its identity.
    ///
    /// `SmartAlbumRule` is `Equatable` including its `id`, and every rule is built
    /// with a fresh `UUID`, so two rules that say exactly the same thing are never
    /// `==`. Comparing these keeps the expectations readable and makes the failure
    /// message say which field is wrong.
    private struct RuleMeaning: Equatable, CustomStringConvertible {
        var field: RuleField
        var op: RuleOperator
        var text: String
        var number: Double?
        var numberUpper: Double?
        var boolValue: Bool
        var focalMode: FocalLengthMode

        init(_ rule: SmartAlbumRule) {
            field = rule.field
            op = rule.op
            text = rule.text
            number = rule.number
            numberUpper = rule.numberUpper
            boolValue = rule.boolValue
            focalMode = rule.focalMode
        }

        var description: String {
            "\(field) \(op) text:\(text) number:\(number as Any) upper:\(numberUpper as Any)"
        }
    }

    private func meanings(_ query: String) -> [RuleMeaning] {
        rules(query).map(RuleMeaning.init)
    }

    private func meaning(_ rule: SmartAlbumRule) -> RuleMeaning { RuleMeaning(rule) }

    private func intent(_ query: String) -> SearchIntent {
        SearchIntentParser.parse(query, vocabulary: vocabulary, now: now, calendar: calendar)
    }

    private func epoch(_ year: Int, _ month: Int, _ day: Int, _ endOfDay: Bool = false) -> Double {
        let start = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        return endOfDay
            ? calendar.date(byAdding: .day, value: 1, to: start)!
                .addingTimeInterval(-1).timeIntervalSince1970
            : start.timeIntervalSince1970
    }

    // MARK: Comparisons

    @Test func theSameComparisonReadsTheSameInBothLanguages() {
        // The example the feature was asked for, in every spelling of it.
        for query in ["f > 1.2", "f>1.2", "f lớn hơn 1.2", "khẩu độ trên 1.2", "aperture over 1.2"] {
            let rules = rules(query)
            #expect(rules.count == 1, "\(query)")
            #expect(rules.first?.field == .aperture, "\(query)")
            #expect(rules.first?.op == .greaterThan, "\(query)")
            #expect(rules.first?.number == 1.2, "\(query)")
        }
    }

    @Test func aPhraseIsNeverMatchedInsideAWord() {
        // "tu" (từ, "from") lives inside "aperture". Matching phrases as substrings
        // turned "aperture over 1.2" into "aper from re over 1.2" and lost the query.
        let tokens = SearchIntentParser.canonicalTokens("aperture over 1.2")
        #expect(tokens.map(\.canonical) == ["f", ">", "1.2"])
    }

    @Test func lessThanAndRangesWork() {
        #expect(rules("iso dưới 400").first?.op == .lessThan)
        #expect(rules("iso under 400").first?.number == 400)

        let range = rules("iso 100-400").first
        #expect(range?.op == .inRange)
        #expect(range?.number == 100)
        #expect(range?.numberUpper == 400)

        let spelled = rules("tiêu cự từ 24 đến 70").first
        #expect(spelled?.field == .focalLength)
        #expect(spelled?.op == .inRange)
        #expect(spelled?.number == 24)
        #expect(spelled?.numberUpper == 70)
    }

    @Test func aComparisonCanLeadWithItsUnitInsteadOfAFieldName() {
        let rule = rules("trên 200mm").first
        #expect(rule?.field == .focalLength)
        #expect(rule?.op == .greaterThan)
        #expect(rule?.number == 200)
    }

    @Test func fasterShutterMeansASmallerNumber() {
        // The one comparison in the app that inverts when spoken: a faster shutter
        // is fewer seconds, so "faster than 1/500" must not become `>`.
        for query in ["nhanh hơn 1/500", "faster than 1/500"] {
            let rule = rules(query).first
            #expect(rule?.field == .shutter, "\(query)")
            #expect(rule?.op == .lessThan, "\(query)")
            #expect(rule?.number == 1.0 / 500, "\(query)")
        }
        #expect(rules("chậm hơn 1/30").first?.op == .greaterThan)
    }

    // MARK: What already worked must keep working

    @Test func theOldShorthandsStillParse() {
        #expect(meanings("85mm") == [
            meaning(SmartAlbumRule(field: .focalLength, op: .equalTo, number: 85)),
        ])
        #expect(meanings("ISO 3200") == [
            meaning(SmartAlbumRule(field: .iso, op: .equalTo, number: 3_200)),
        ])
        #expect(meanings("f/1.8") == [
            meaning(SmartAlbumRule(field: .aperture, op: .equalTo, number: 1.8)),
        ])
        #expect(meanings("1/500") == [
            meaning(SmartAlbumRule(field: .shutter, op: .equalTo, number: 1.0 / 500)),
        ])
    }

    // MARK: Dates

    @Test func yearsBecomeCalendarBoundariesNotBareNumbers() {
        // "before 2020" means before the year started, "after 2023" after it ended;
        // anything else quietly drops twelve months of photos.
        #expect(rules("trước 2020").first?.op == .before)
        #expect(rules("trước 2020").first?.number == epoch(2_020, 1, 1))
        #expect(rules("sau 2023").first?.op == .after)
        #expect(rules("sau 2023").first?.number == epoch(2_023, 12, 31, true))

        let year = rules("năm 2023").first
        #expect(year?.op == .inRange)
        #expect(year?.number == epoch(2_023, 1, 1))
        #expect(year?.numberUpper == epoch(2_023, 12, 31, true))
        // A bare four-digit year is a year on its own.
        #expect(rules("2023").first?.field == .dateTaken)
    }

    @Test func namedPeriodsResolveAgainstTheSuppliedDate() {
        let yesterday = rules("hôm qua").first
        #expect(yesterday?.number == epoch(2_026, 3, 16))
        #expect(yesterday?.numberUpper == epoch(2_026, 3, 16, true))

        let lastMonth = rules("tháng trước").first
        #expect(lastMonth?.number == epoch(2_026, 2, 1))
        #expect(lastMonth?.numberUpper == epoch(2_026, 2, 28, true))

        #expect(rules("7 ngày qua").first?.op == .inLastDays)
        #expect(rules("7 ngày qua").first?.number == 7)
        #expect(rules("last 30 days").first?.number == 30)
    }

    // MARK: Standalone conditions

    @Test func singleWordConditionsAreRecognised() {
        #expect(rules("yêu thích").first?.field == .favorite)
        #expect(rules("favorite").first?.boolValue == true)
        #expect(meanings("raw").first == meaning(SmartAlbumRule(
            field: .fileType, op: .isExactly, text: PhotoFileType.raw.rawValue
        )))
        #expect(meanings("full frame").first == meaning(SmartAlbumRule(
            field: .sensorFormat, op: .isExactly, text: SensorFormat.fullFrame.rawValue
        )))
    }

    // MARK: Names

    @Test func aBareWordIsAPlaceOnlyBecauseTheLibrarySaysSo() {
        // Nothing about "fukuoka" says it is a city — the index does. That is why
        // there is no heuristic here to be wrong about.
        #expect(meanings("fukuoka") == [
            meaning(SmartAlbumRule(field: .place, op: .contains, text: "Fukuoka")),
        ])
        // Typed without diacritics, matched with them.
        #expect(meanings("da nang") == [
            meaning(SmartAlbumRule(field: .place, op: .contains, text: "Đà Nẵng")),
        ])
        #expect(rules("Canon EOS R6").first?.field == .cameraBody)
        // A word the library has never seen stays free text.
        #expect(rules("IMG_1234").isEmpty)
        #expect(intent("IMG_1234").leftoverText == "IMG_1234")
        #expect(intent("IMG_1234").isConfident == false)
    }

    // MARK: Whole sentences

    @Test func fillerWordsAreDroppedRatherThanSearchedFor() {
        // "chụp" must not become a text condition: nothing contains it, so the
        // query would return an empty grid.
        let combined = rules("iso trên 3200 chụp trước 2020")
        #expect(combined.count == 2)
        #expect(combined.first?.field == .iso)
        #expect(combined.first?.op == .greaterThan)
        #expect(combined.last?.field == .dateTaken)
        #expect(intent("iso trên 3200 chụp trước 2020").leftoverText == nil)

        let mixed = rules("ảnh chụp ở fukuoka f dưới 2")
        #expect(mixed.contains { $0.field == .place && $0.text == "Fukuoka" })
        #expect(mixed.contains { $0.field == .aperture && $0.op == .lessThan })
    }

    @Test func animplausibleNumberIsRefusedInsteadOfMatchingNothing() {
        // "iso 1.4" is an aperture the user mislabelled. A rule would produce a
        // confident chip over an empty grid; free text at least searches.
        #expect(rules("iso 1.4").isEmpty)
        #expect(rules("f 3200").isEmpty)
        #expect(intent("").isConfident == false)
    }
}
