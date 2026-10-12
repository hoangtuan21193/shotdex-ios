import Foundation
import Testing
@testable import ShotDex

/// Custom… date folder names (FS-22.01 §4).
@Suite struct BackupDateNameTests {
    private let names: BackupDateName = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return BackupDateName(calendar: calendar, locale: Locale(identifier: "en_US"))
    }()

    /// 2025-10-12 14:03:27 UTC.
    private let taken = Date(timeIntervalSince1970: 1_760_277_807)

    /// AC-6: `/` and `:` never reach the separator; a typed `年` does.
    @Test func forbiddenCharactersRefused() {
        #expect(BackupDateName.cleanSeparator("a/b") == "ab")
        #expect(BackupDateName.cleanSeparator("ab:") == "ab")
        #expect(BackupDateName.cleanSeparator(#"\*?"<>|"#) == "")

        var format = BackupCustomDate()
        format.separator = "年"
        #expect(names.custom(taken, format) == "2025年10年12")
        format.separator = "a/b:"
        #expect(names.custom(taken, format) == "2025ab10ab12")
    }

    @Test func orderPartsAndForms() {
        var format = BackupCustomDate()
        format.separator = " - "
        format.order = .dayMonthYear
        format.yearStyle = .short
        format.monthForm = .abbreviated
        #expect(names.custom(taken, format) == "12 - Oct - 25")
        format.order = .monthDayYear
        format.monthForm = .name
        #expect(names.custom(taken, format) == "October - 12 - 25")
    }

    /// An empty separator with all-number parts is still a name.
    @Test func emptySeparatorIsCompact() {
        var format = BackupCustomDate()
        format.separator = ""
        #expect(names.custom(taken, format) == "20251012")
        #expect(names.isUsable(format, sample: taken))
    }

    /// A Month folder name carries no day.
    @Test func monthNameHasNoDay() {
        var format = BackupCustomDate(parts: [.year, .month])
        format.separator = "-"
        #expect(names.custom(taken, format) == "2025-10")
        #expect(!names.isUsable(BackupCustomDate(parts: []), sample: taken))
    }
}
