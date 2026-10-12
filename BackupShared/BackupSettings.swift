import Foundation

/// Everything about a job the form edits (FS-22.01 §2–§5). Decoded leniently:
/// a value this build cannot read falls back to its default instead of taking
/// the whole job with it.
struct BackupSettings: Codable, Hashable, Sendable {
    enum Content: String, Codable, Sendable, CaseIterable { case photosAndVideos, photosOnly, videosOnly }

    var content: Content = .photosAndVideos
    var includesEditedVersions = false
    var onlyOnWiFi = true
    var onlyWhileCharging = false
    var keepsScreenOn = false
    var organize = BackupOrganize()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = BackupSettings()
        content = (try? c.decode(Content.self, forKey: .content)) ?? fallback.content
        includesEditedVersions = (try? c.decode(Bool.self, forKey: .includesEditedVersions)) ?? fallback.includesEditedVersions
        onlyOnWiFi = (try? c.decode(Bool.self, forKey: .onlyOnWiFi)) ?? fallback.onlyOnWiFi
        onlyWhileCharging = (try? c.decode(Bool.self, forKey: .onlyWhileCharging)) ?? fallback.onlyWhileCharging
        keepsScreenOn = (try? c.decode(Bool.self, forKey: .keepsScreenOn)) ?? fallback.keepsScreenOn
        organize = (try? c.decode(BackupOrganize.self, forKey: .organize)) ?? fallback.organize
    }
}

/// How files are laid out at the destination (FS-22.01 §3–§5).
struct BackupOrganize: Codable, Hashable, Sendable {
    enum Levels: String, Codable, Sendable, CaseIterable {
        case yearMonthDay, yearMonth, yearDate, dateOnly, album, noFolders
    }
    enum YearStyle: String, Codable, Sendable, CaseIterable { case full, short }
    enum MonthStyle: String, Codable, Sendable, CaseIterable {
        case number, yearMonth, abbreviated, name, kanji, vietnamese, custom
    }
    enum DayStyle: String, Codable, Sendable, CaseIterable {
        case dashed, dotted, underscored, compact, dayOnly, custom
    }
    enum VideoPlacement: String, Codable, Sendable, CaseIterable {
        case together, apartAtTop, apartInYear, apartInMonth, apartInDay
    }
    enum FileNames: String, Codable, Sendable, CaseIterable { case original, dateAndTime, dateAndOriginal }

    var levels: Levels = .yearMonthDay
    var yearStyle: YearStyle = .full
    var monthStyle: MonthStyle = .abbreviated
    var dayStyle: DayStyle = .dotted
    var customMonth = BackupCustomDate(parts: [.year, .month])
    var customDay = BackupCustomDate()
    var videoPlacement: VideoPlacement = .apartAtTop
    var fileNames: FileNames = .original

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = BackupOrganize()
        levels = (try? c.decode(Levels.self, forKey: .levels)) ?? fallback.levels
        yearStyle = (try? c.decode(YearStyle.self, forKey: .yearStyle)) ?? fallback.yearStyle
        monthStyle = (try? c.decode(MonthStyle.self, forKey: .monthStyle)) ?? fallback.monthStyle
        dayStyle = (try? c.decode(DayStyle.self, forKey: .dayStyle)) ?? fallback.dayStyle
        customMonth = (try? c.decode(BackupCustomDate.self, forKey: .customMonth)) ?? fallback.customMonth
        customDay = (try? c.decode(BackupCustomDate.self, forKey: .customDay)) ?? fallback.customDay
        videoPlacement = (try? c.decode(VideoPlacement.self, forKey: .videoPlacement)) ?? fallback.videoPlacement
        fileNames = (try? c.decode(FileNames.self, forKey: .fileNames)) ?? fallback.fileNames
    }
}

/// A user-built date folder name (FS-22.01 §4): which parts, in what order,
/// how each is written, and the separator typed between them.
struct BackupCustomDate: Codable, Hashable, Sendable {
    enum Part: String, Codable, Sendable { case year, month, day }
    enum Order: String, Codable, Sendable, CaseIterable { case yearMonthDay, dayMonthYear, monthDayYear }
    enum MonthForm: String, Codable, Sendable, CaseIterable { case number, abbreviated, name }

    /// The parts this name carries — a Month folder name has no day.
    var parts: [Part] = [.year, .month, .day]
    var order: Order = .yearMonthDay
    var yearStyle: BackupOrganize.YearStyle = .full
    var monthForm: MonthForm = .number
    var separator = "."

    init(parts: [Part] = [.year, .month, .day]) {
        self.parts = parts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = BackupCustomDate()
        parts = (try? c.decode([Part].self, forKey: .parts)) ?? fallback.parts
        order = (try? c.decode(Order.self, forKey: .order)) ?? fallback.order
        yearStyle = (try? c.decode(BackupOrganize.YearStyle.self, forKey: .yearStyle)) ?? fallback.yearStyle
        monthForm = (try? c.decode(MonthForm.self, forKey: .monthForm)) ?? fallback.monthForm
        separator = (try? c.decode(String.self, forKey: .separator)) ?? fallback.separator
    }
}
