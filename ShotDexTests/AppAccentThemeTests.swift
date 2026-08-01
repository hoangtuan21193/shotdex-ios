import Testing
@testable import ShotDex

struct AppAccentThemeTests {
    @Test func everyStoredRawValueRoundTrips() {
        for theme in AppAccentTheme.allCases {
            #expect(AppAccentTheme.resolved(theme.rawValue) == theme)
        }
    }

    @Test func unwrittenOrUnknownRawValuesFallBackToTheDefault() {
        // No preference yet, a value from a build that offered another colour,
        // and a raw value in the wrong case all mean the app's own amber.
        #expect(AppAccentTheme.resolved(nil) == .amber)
        #expect(AppAccentTheme.resolved("") == .amber)
        #expect(AppAccentTheme.resolved("chartreuse") == .amber)
        #expect(AppAccentTheme.resolved("Green") == .amber)
        #expect(AppAccentTheme.default == .amber)
    }

    @Test func themesAreDistinctAndNamed() {
        #expect(AppAccentTheme.allCases.count == 4)
        let names = Set(AppAccentTheme.allCases.map(\.displayName))
        #expect(names.count == AppAccentTheme.allCases.count)
        #expect(!names.contains(""))
    }
}
