import Testing
@testable import ShotDex

/// FS-06.10 AC-13 and FS-06.08 AC-6 — the operator menu of every field the
/// rule builder offers. The switch below is exhaustive on purpose: a new
/// field does not compile until someone writes down its operators here.
struct SmartAlbumOperatorTests {

    @Test func everyFieldOperators() {
        for field in RuleField.allCases {
            #expect(field.kind.allowedOperators == Self.expected(field), "\(field)")
        }
    }

    /// Choice fields — the closed-set ones, Source among them — offer only
    /// *is* and *is not*: a value is always one of the set, so there is
    /// nothing to be missing.
    @Test func choiceFieldsOfferOnlyIsAndIsNot() {
        let choices = RuleField.allCases.filter { $0.kind == .choice }
        #expect(choices.contains(.source) && choices.contains(.original))
        for field in choices {
            #expect(field.kind.allowedOperators == [.isExactly, .isNot], "\(field)")
            #expect(field.defaultOperator == .isExactly, "\(field)")
        }
    }

    /// Every field the menu shows has at least one operator, except Favorite
    /// and Also on Server, whose rows are a Yes/No switch.
    @Test func selectableFieldsHaveOperators() {
        for field in RuleField.selectableCases(extendedMetadata: true) where field != .favorite && field != .alsoOnServer {
            #expect(!field.kind.allowedOperators.isEmpty, "\(field)")
        }
    }

    private static func expected(_ field: RuleField) -> [RuleOperator] {
        switch field {
        case .cameraBrand, .cameraBody, .lens, .filename, .place, .anyText:
            [.contains, .doesNotContain, .isExactly, .isNot]
        case .sensorFormat, .fileType, .mediaType, .flag, .source, .original:
            [.isExactly, .isNot]
        case .iso, .aperture, .shutter, .focalLength:
            [.equalTo, .greaterThan, .lessThan, .inRange]
        case .dateTaken:
            [.on, .inMonth, .inLastDays, .before, .after, .inRange]
        case .favorite, .alsoOnServer:
            []
        case .rating:
            [.atLeast, .equalTo, .atMost]
        case .keyword:
            [.hasKeyword, .lacksKeyword, .hasAnyKeyword, .hasNoKeywords]
        case .caption:
            [.contains, .doesNotContain]
        }
    }
}
