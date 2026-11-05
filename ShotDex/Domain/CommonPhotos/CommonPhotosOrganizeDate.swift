import Foundation

/// The date a Common Photos copy is filed by when Organize uses dates
/// (FS-19.08 §6e): when it was taken (read from the photo's head — never a
/// video's, which is not downloaded for it), else the date its folder is
/// named after in the first folder (`2025/03/15`, `2025-03-15`, `20250315`,
/// `2025/03` → the 1st), else the file's write time on the server.
enum CommonPhotosOrganizeDate {
    static func date(taken: Date?, folder: String, modified: Date?, calendar: Calendar = .current) -> Date? {
        taken ?? folderDate(folder, calendar: calendar) ?? modified
    }

    /// The date a folder path names, its deepest one; nil when none does.
    static func folderDate(_ folder: String, calendar: Calendar = .current) -> Date? {
        let parts = folder.split(separator: "/").map(String.init)
        // Deepest first: `2025/03/15`, then `2025/03`, then any `2025-03-15` or `20250315` on the way down.
        for end in stride(from: parts.count, through: 1, by: -1) {
            let tail = Array(parts[..<end])
            if tail.count >= 3, let date = day(tail[tail.count - 3], tail[tail.count - 2], tail[tail.count - 1], calendar) { return date }
            if let date = compact(tail[tail.count - 1], calendar) { return date }
            if tail.count >= 2, let date = day(tail[tail.count - 2], tail[tail.count - 1], "01", calendar) { return date }
        }
        return nil
    }

    private static func day(_ year: String, _ month: String, _ day: String, _ calendar: Calendar) -> Date? {
        guard year.count == 4, (1...2).contains(month.count), (1...2).contains(day.count),
              let y = Int(year), let m = Int(month), let d = Int(day),
              (1900...2200).contains(y), (1...12).contains(m), (1...31).contains(d) else { return nil }
        let components = DateComponents(year: y, month: m, day: d, hour: 12)
        guard let date = calendar.date(from: components), calendar.component(.day, from: date) == d else { return nil }
        return date
    }

    /// `2025-03-15`, `2025.03.15`, `2025_03_15`, `20250315` — a whole folder name.
    private static func compact(_ name: String, _ calendar: Calendar) -> Date? {
        let digits = name.filter(\.isNumber)
        let separators = name.filter { !$0.isNumber }
        guard digits.count == 8, separators.count == 0 || (separators.count == 2 && Set(separators).count == 1 && "-._".contains(separators.first!)) else { return nil }
        let chars = Array(digits)
        return day(String(chars[0..<4]), String(chars[4..<6]), String(chars[6..<8]), calendar)
    }
}
