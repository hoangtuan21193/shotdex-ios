import Foundation

/// Date folder and file names for a backup (FS-22.01 §3–§5). Pure: the
/// calendar and the language for month names come in, so a test pins both.
struct BackupDateName: Sendable {
    /// Characters a NAS folder or file name cannot hold (SMB's set, which
    /// covers SFTP and WebDAV).
    static let forbiddenCharacters: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]

    var calendar: Calendar
    /// Month names follow the app's language, not the NAS's (FS-22.01 §3).
    var locale: Locale

    init(calendar: Calendar = .current, locale: Locale = .current) {
        var calendar = calendar
        calendar.locale = locale
        self.calendar = calendar
        self.locale = locale
    }

    func year(_ date: Date, style: BackupOrganize.YearStyle) -> String {
        let year = calendar.component(.year, from: date)
        switch style {
        case .full: return String(format: "%04d", year)
        case .short: return String(format: "%02d", year % 100)
        }
    }

    func month(_ date: Date, organize: BackupOrganize) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        let month = parts.month ?? 1
        switch organize.monthStyle {
        case .number: return String(format: "%02d", month)
        case .yearMonth: return "\(year(date, style: organize.yearStyle))-\(String(format: "%02d", month))"
        case .abbreviated: return monthName(month, abbreviated: true)
        case .name: return monthName(month, abbreviated: false)
        case .kanji: return "\(month)月"
        case .vietnamese: return "Tháng \(month)"
        case .custom: return custom(date, organize.customMonth)
        }
    }

    func day(_ date: Date, organize: BackupOrganize) -> String {
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        let y = year(date, style: organize.yearStyle)
        let m = String(format: "%02d", p.month ?? 1)
        let d = String(format: "%02d", p.day ?? 1)
        switch organize.dayStyle {
        case .dashed: return "\(y)-\(m)-\(d)"
        case .dotted: return "\(y).\(m).\(d)"
        case .underscored: return "\(y)_\(m)_\(d)"
        case .compact: return "\(y)\(m)\(d)"
        case .dayOnly: return d
        case .custom: return custom(date, organize.customDay)
        }
    }

    /// A Custom… name: the parts it carries, in its order, joined by its
    /// separator with any forbidden character taken out.
    func custom(_ date: Date, _ format: BackupCustomDate) -> String {
        let p = calendar.dateComponents([.month, .day], from: date)
        let ordered: [BackupCustomDate.Part] = switch format.order {
        case .yearMonthDay: [.year, .month, .day]
        case .dayMonthYear: [.day, .month, .year]
        case .monthDayYear: [.month, .day, .year]
        }
        let texts = ordered.filter(format.parts.contains).map { part -> String in
            switch part {
            case .year: return year(date, style: format.yearStyle)
            case .month:
                let month = p.month ?? 1
                return switch format.monthForm {
                case .number: String(format: "%02d", month)
                case .abbreviated: monthName(month, abbreviated: true)
                case .name: monthName(month, abbreviated: false)
                }
            case .day: return String(format: "%02d", p.day ?? 1)
            }
        }
        return texts.joined(separator: Self.cleanSeparator(format.separator))
    }

    /// `2025-10-12 14.03.27` — the stem of the Date and Time file names.
    func timestamp(_ date: Date) -> String {
        let p = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d-%02d-%02d %02d.%02d.%02d",
            p.year ?? 0, p.month ?? 1, p.day ?? 1, p.hour ?? 0, p.minute ?? 0, p.second ?? 0
        )
    }

    /// True when `format` names a folder at all — the Custom… sheet's Done
    /// stays off until it does (FS-22.01 §4).
    func isUsable(_ format: BackupCustomDate, sample: Date = Date()) -> Bool {
        !custom(sample, format).isEmpty
    }

    /// The separator as typed, minus every character a NAS refuses.
    static func cleanSeparator(_ typed: String) -> String {
        String(typed.filter { !forbiddenCharacters.contains($0) })
    }

    /// A name from outside (an album title, a source folder) made safe for a
    /// NAS folder: forbidden characters become `-`, never `/`.
    /// Windows and SMB also refuse a name ending in a dot or a space
    /// (FS-19.08 §6e: a source folder `Trip. ` made on a Mac).
    static func safeFolderName(_ name: String) -> String {
        var cleaned = String(name.map { forbiddenCharacters.contains($0) ? "-" : $0 })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasSuffix(".") || cleaned.hasSuffix(" ") { cleaned.removeLast() }
        if cleaned.isEmpty { return "-" }
        // Names Windows keeps for devices (`CON`, `aux.jpg`, `COM1`).
        let stem = cleaned.split(separator: ".", maxSplits: 1).first.map { String($0).uppercased() } ?? ""
        if reservedNames.contains(stem) { cleaned += "-" }
        return cleaned
    }

    private static let reservedNames: Set<String> = Set(["CON", "PRN", "AUX", "NUL"]
        + (1...9).flatMap { ["COM\($0)", "LPT\($0)"] })

    private func monthName(_ month: Int, abbreviated: Bool) -> String {
        let names = abbreviated ? calendar.shortStandaloneMonthSymbols : calendar.standaloneMonthSymbols
        return names.indices.contains(month - 1) ? names[month - 1] : String(month)
    }
}
