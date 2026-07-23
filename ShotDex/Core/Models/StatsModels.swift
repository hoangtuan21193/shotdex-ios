import Foundation

/// Time scope for a chart. Each dashboard widget carries its own scope
/// (persisted inside its config), so `Codable` — the sole payload is a
/// `ClosedRange<Int>`, which the standard library already encodes.
enum StatsDateScope: Codable, Hashable, Sendable {
    case allTime
    case thisYear
    case thisMonth
    /// User-picked start–end interval, in epoch seconds (whole days).
    case custom(ClosedRange<Int>)

    var title: String {
        switch self {
        case .allTime: String(localized: "All Time")
        case .thisYear: String(localized: "This Year")
        case .thisMonth: String(localized: "This Month")
        case .custom(let range):
            FormatUtils.dateRange(
                Date(timeIntervalSince1970: TimeInterval(range.lowerBound)),
                Date(timeIntervalSince1970: TimeInterval(range.upperBound))
            )
        }
    }

    /// Resolves the scope into an epoch-second interval, or nil for all time.
    func dateInterval(now: Date = Date(), calendar: Calendar = .current) -> ClosedRange<Int>? {
        switch self {
        case .allTime:
            return nil
        case .thisYear:
            guard let start = calendar.dateInterval(of: .year, for: now)?.start else { return nil }
            return Int(start.timeIntervalSince1970)...Int(now.timeIntervalSince1970)
        case .thisMonth:
            guard let start = calendar.dateInterval(of: .month, for: now)?.start else { return nil }
            return Int(start.timeIntervalSince1970)...Int(now.timeIntervalSince1970)
        case .custom(let range):
            return range
        }
    }

    /// Builds a custom scope covering the given days in full
    /// (start of `days.lowerBound` through the last second of `days.upperBound`).
    static func custom(days: ClosedRange<Date>, calendar: Calendar = .current) -> StatsDateScope {
        let start = calendar.startOfDay(for: days.lowerBound)
        let endOfDay = calendar.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: calendar.startOfDay(for: days.upperBound)
        ) ?? days.upperBound
        return .custom(Int(start.timeIntervalSince1970)...Int(endOfDay.timeIntervalSince1970))
    }
}

/// One point of a dashboard chart's result: an X-axis label, a Y-axis value,
/// and (when applicable) a raw key for drill-down and a series name for
/// multi-line charts. Produced by `StatsDAO.aggregate`.
struct ChartDatum: Equatable, Identifiable, Sendable {
    /// X-axis label (bucket name, group value, or time period).
    var label: String
    /// Y-axis value (count, or the aggregate — file size in bytes, etc.).
    var value: Double
    /// Raw group key for drill-down to a filtered Library (nil = not drillable).
    var drillKey: String?
    /// Series name for `.line` charts split by a second dimension (nil = single).
    var series: String?
    /// True for the synthetic "Unknown" bucket (missing metadata).
    var isUnknown: Bool = false

    var id: String { "\(series ?? "")|\(label)" }
}

/// A generic "name + count + share" row used by camera/lens/format usage stats.
struct UsageCount: Equatable, Identifiable, Sendable {
    var name: String
    var count: Int
    var percentage: Double
    /// True for the synthetic bucket of photos whose column is NULL/empty —
    /// not drillable, since filters can't express "field is missing".
    var isUnknown: Bool = false

    var id: String { name }
}

/// One histogram bucket (ISO, aperture, shutter, focal length).
struct HistogramBucket: Equatable, Identifiable, Sendable {
    var label: String
    var lowerBound: Double
    var upperBound: Double?
    var count: Int

    var id: String { label }
}

/// Focal length buckets for zoom-lens histograms (spec §7.4).
enum FocalHistogramBucket: CaseIterable, Sendable {
    case b12To19, b20To27, b28To34, b35To49, b50To69, b70To99
    case b100To199, b200To299, b300To499, b500Plus

    var range: (lower: Double, upper: Double?) {
        switch self {
        case .b12To19: (12, 20)
        case .b20To27: (20, 28)
        case .b28To34: (28, 35)
        case .b35To49: (35, 50)
        case .b50To69: (50, 70)
        case .b70To99: (70, 100)
        case .b100To199: (100, 200)
        case .b200To299: (200, 300)
        case .b300To499: (300, 500)
        case .b500Plus: (500, nil)
        }
    }

    var label: String {
        let (lower, upper) = range
        if let upper {
            return "\(Int(lower))–\(Int(upper) - 1)"
        }
        return "\(Int(lower))+"
    }
}

/// Headline numbers shown in the summary cards.
struct StatsSummary: Equatable, Sendable {
    var totalPhotos: Int
    var mostUsedCamera: String?
    var mostUsedLens: String?
    var mostUsedFocalLength: Double?
    var mostUsedEquivalentFocalLength: Double?
    var mostUsedSensorFormat: SensorFormat?

    static let empty = StatsSummary(
        totalPhotos: 0,
        mostUsedCamera: nil,
        mostUsedLens: nil,
        mostUsedFocalLength: nil,
        mostUsedEquivalentFocalLength: nil,
        mostUsedSensorFormat: nil
    )
}
