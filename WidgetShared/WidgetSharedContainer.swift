import Foundation

/// The App Group container the app writes into and the widgets read from.
///
/// These files are compiled into both the app and the widget target (the
/// widget folder is a synchronised group, and the `ShotDexWidget/Shared`
/// files are listed as an exception that also joins the `ShotDex` target), so
/// the two processes read and write the same layout from the same source.
/// Nothing here imports SwiftUI, WidgetKit or PhotoKit.
enum WidgetSharedContainer {
    static let appGroupIdentifier = "group.com.hoangtuan.shotdex"

    /// Nil on a build whose App ID lacks the App Groups capability; every
    /// reader degrades to its "Open ShotDex" state rather than showing zeroes.
    static var url: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
    }

    /// `yyyy-MM-dd` in the given calendar — the key a day's snapshot is filed
    /// under and the value a widget deep link carries. Fixed digits and no
    /// locale, so the app and the widget spell the same day the same way.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0, components.month ?? 0, components.day ?? 0
        )
    }

    /// The local midnight named by a `dayKey`, or nil for anything else.
    static func date(fromDayKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day
        else { return nil }
        return date
    }

    static func decode<T: Decodable>(_ type: T.Type, at url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func encode<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
