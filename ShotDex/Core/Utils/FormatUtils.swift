import Foundation

/// Pure formatting helpers for exposure values. No framework dependencies.
enum FormatUtils {

    /// `1/500s` for sub-second exposures, `2s` / `2.5s` for long exposures.
    static func shutterSpeed(_ seconds: Double) -> String? {
        guard seconds > 0, seconds.isFinite else { return nil }
        if seconds >= 1 {
            if seconds == seconds.rounded() {
                return "\(Int(seconds))s"
            }
            return String(format: "%.1fs", seconds)
        }
        let denominator = (1.0 / seconds).rounded()
        guard denominator >= 1 else { return nil }
        return "1/\(Int(denominator))s"
    }

    /// Chrome-width variant of `shutterSpeed`: `1/500` without the trailing
    /// `s` for sub-second exposures (inside an exposure group the fraction
    /// already reads as a shutter speed), but `2s` / `2.5s` kept for
    /// whole/decimal seconds where the unit is what separates it from an
    /// aperture or ISO value.
    static func shutterSpeedCompact(_ seconds: Double) -> String? {
        guard let full = shutterSpeed(seconds) else { return nil }
        guard full.hasPrefix("1/") else { return full }
        return String(full.dropLast())
    }

    /// `f/1.8`, `f/11`.
    static func aperture(_ value: Double) -> String? {
        guard value > 0, value.isFinite else { return nil }
        if value == value.rounded() {
            return "f/\(Int(value))"
        }
        return String(format: "f/%.1f", value)
    }

    /// `85mm`, `23.5mm`.
    static func focalLength(_ millimeters: Double) -> String? {
        guard millimeters > 0, millimeters.isFinite else { return nil }
        if millimeters == millimeters.rounded() {
            return "\(Int(millimeters))mm"
        }
        return String(format: "%.1fmm", millimeters)
    }

    /// `ISO 400`.
    static func iso(_ value: Int) -> String? {
        guard value > 0 else { return nil }
        return "ISO \(value)"
    }

    /// `12.4 MB` style, locale-aware.
    static func fileSize(_ bytes: Int) -> String? {
        guard bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Video duration: `0:07`, `1:23`, `1:02:03`.
    static func duration(_ seconds: Double) -> String {
        guard seconds > 0, seconds.isFinite else { return "0:00" }
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// `24.2 MP`.
    static func megapixels(_ value: Double) -> String? {
        guard value > 0, value.isFinite else { return nil }
        return String(format: "%.1f MP", value)
    }

    /// Joins non-nil metadata fragments with the ` · ` separator used on grid tiles.
    static func metadataLine(_ fragments: [String?]) -> String? {
        let parts = fragments.compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    /// Joins non-nil fragments with a single space — the tight grouping used
    /// inside one logical group (`400mm f/7.1 1/1000 ISO 3200`), where ` · `
    /// between every value would spend width without adding meaning. Groups
    /// themselves are still joined by `metadataLine`.
    static func tokenLine(_ fragments: [String?]) -> String? {
        let parts = fragments.compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }

    /// Grid day-section header: "Today" / "Yesterday", else "19 July 2026".
    /// Calendar/now/locale injectable for deterministic tests.
    static func dayHeader(
        _ date: Date,
        calendar: Calendar = .current,
        now: Date = Date(),
        locale: Locale = .current
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "Today")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday")
        }
        return date.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar)
                .day().month(.wide).year()
        )
    }

    /// Grid month-section header: "July 2026".
    static func monthHeader(
        _ date: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        date.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar)
                .month(.wide).year()
        )
    }

    /// Day-range label: "Mar 12 – Jun 4, 2026" (locale-dependent).
    static func dateRange(_ start: Date, _ end: Date) -> String {
        dayRangeFormatter.string(from: start, to: end)
    }

    private static let dayRangeFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
