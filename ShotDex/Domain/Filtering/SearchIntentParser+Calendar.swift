import Foundation

extension SearchIntentParser {
    /// Month names, seasons and days of the week (FS-01.03c §5):
    /// `june` · `tháng 6` → Month of Year; `june 2024` · `tháng 6 2024` ·
    /// `tháng 6/2024` → that month; `summer` · `mùa hè` → Season;
    /// `monday` · `thứ 2` · `cuối tuần` → Day of Week.
    static func calendarRule(
        _ tokens: [Token],
        _ index: Int,
        _ calendar: Calendar
    ) -> (SmartAlbumRule, Int)? {
        let token = tokens[index].canonical

        if let season = CaptureSeason(rawValue: token) {
            return (SmartAlbumRule(field: .season, op: .isExactly, text: season.rawValue), 1)
        }
        if let day = CaptureWeekday(rawValue: token) {
            return (SmartAlbumRule(field: .dayOfWeek, op: .isExactly, text: day.rawValue), 1)
        }

        // `m6` (a month name), or `month` + 1–12 (`tháng 6`), or `month` + `6/2024`.
        var month: Int?
        var consumed = 1
        var year: Int?
        if token.hasPrefix("m"), let number = Int(token.dropFirst()), (1...12).contains(number) {
            month = number
        } else if token == "month", index + 1 < tokens.count {
            let next = tokens[index + 1].canonical
            if let number = Int(next), (1...12).contains(number) {
                month = number
                consumed = 2
            } else {
                let parts = next.split(separator: "/")
                if parts.count == 2, let number = Int(parts[0]), (1...12).contains(number),
                   let value = Self.year(String(parts[1])) {
                    month = number
                    year = value
                    consumed = 2
                }
            }
        }
        guard let month else { return nil }
        if year == nil, index + consumed < tokens.count, let value = Self.year(tokens[index + consumed].canonical) {
            year = value
            consumed += 1
        }
        if let year {
            let anchor = CaptureMonth(year: year, month: month).anchorDate(calendar: calendar)
            return (SmartAlbumRule(field: .dateTaken, op: .inMonth, number: anchor.timeIntervalSince1970), consumed)
        }
        return (SmartAlbumRule(field: .monthOfYear, op: .isExactly, text: String(month)), consumed)
    }
}
