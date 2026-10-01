import Foundation

/// The words of the Insights card (FS-07.02 §4). Every sentence is one whole
/// template in the `Insights` string table — no sentence is glued together
/// from pieces — and counts of photos go through that table's plural
/// variants. Numbers, percentages, months and focal lengths are formatted for
/// `locale`; tests pass a fixed one.
enum InsightCopy {
    static let table = "Insights"

    // MARK: Sentences

    static func sentence(_ insight: Insight, locale: Locale = .current) -> String {
        switch insight.kind {
        case let .focalValue(millimetres, count, denominator, namesDenominator):
            let share = percent(count, of: denominator, locale: locale)
            let focal = focalLength(millimetres)
            return namesDenominator
                ? String(localized: "\(share) of your photos with a known equivalent focal length are at \(focal) equivalent.",
                         table: table, locale: locale, comment: "Insights: one focal length, e.g. 75% … 35mm")
                : String(localized: "\(share) of your photos are at \(focal) equivalent.",
                         table: table, locale: locale, comment: "Insights: one focal length, e.g. 85% … 26mm")

        case let .focalGroup(buckets, count, denominator, namesDenominator):
            let share = percent(count, of: denominator, locale: locale)
            let range = focalRange(buckets)
            let name = groupName(buckets, locale: locale)
            return namesDenominator
                ? String(localized: "\(share) of your photos with a known equivalent focal length are at \(range) equivalent (\(name)).",
                         table: table, locale: locale, comment: "Insights: an angle-of-view group, e.g. 60% … 20–34mm … (Wide)")
                : String(localized: "\(share) of your photos are at \(range) equivalent (\(name)).",
                         table: table, locale: locale, comment: "Insights: an angle-of-view group, e.g. 60% … 20–34mm … (Wide)")

        case let .pair(body, lens, count, denominator, namesDenominator):
            let share = percent(count, of: denominator, locale: locale)
            return namesDenominator
                ? String(localized: "\(body) with \(lens) took \(share) of your photos with a known camera and lens.",
                         table: table, locale: locale, comment: "Insights: body + lens pair, e.g. EOS R6 with RF 85mm … 40%")
                : String(localized: "\(body) with \(lens) took \(share) of your photos.",
                         table: table, locale: locale, comment: "Insights: body + lens pair, e.g. EOS R6 with RF 85mm … 40%")

        case let .slowShutter(count, denominator, namesDenominator):
            let share = percent(count, of: denominator, locale: locale)
            return namesDenominator
                ? String(localized: "\(share) of your photos with a known shutter speed and focal length were shot slower than 1/focal length.",
                         table: table, locale: locale, comment: "Insights: share exposed longer than 1/equivalent focal length")
                : String(localized: "\(share) of your photos were shot slower than 1/focal length.",
                         table: table, locale: locale, comment: "Insights: share exposed longer than 1/equivalent focal length")

        case let .busiestMonth(year, month, count):
            let name = monthName(year: year, month: month, locale: locale)
            return String(localized: "\(name) was your busiest month: \(count) photos.",
                          table: table, locale: locale, comment: "Insights: busiest month and its photo count (plural)")
        }
    }

    // MARK: Card lines

    static func belowThreshold(_ photosWithCamera: Int, locale: Locale = .current) -> String {
        String(localized: "Insights appear once 50 photos have camera info — \(photosWithCamera) so far.",
               table: table, locale: locale, comment: "Insights card under the 50-photo threshold")
    }

    static func unknownSensorFooter(_ count: Int, locale: Locale = .current) -> String {
        String(localized: "\(count) photos are from cameras with an unknown sensor size.",
               table: table, locale: locale, comment: "Insights footer; opens Settings → Unknown Cameras (plural)")
    }

    static func indexingFooter(locale: Locale = .current) -> String {
        String(localized: "Updating as your library is indexed.", table: table, locale: locale,
               comment: "Insights footer while the index is still running")
    }

    // MARK: Values

    /// A whole percentage in the locale's style. 99.5% and up to (not
    /// including) 100% reads "99%" — "100%" only when it really is all.
    static func percent(_ count: Int, of total: Int, locale: Locale = .current) -> String {
        guard total > 0 else { return 0.0.formatted(.percent.precision(.fractionLength(0)).locale(locale)) }
        var whole = (Double(count) * 100 / Double(total)).rounded()
        if whole >= 100, count < total { whole = 99 }
        return (whole / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// The app's focal-length spelling ("26mm"), as on chips, overlays and Info.
    static func focalLength(_ millimetres: Int) -> String {
        MetadataFormatter.focalLength(Double(millimetres)) ?? "\(millimetres)mm"
    }

    /// "August 2026" in the locale's words.
    static func monthName(year: Int, month: Int, locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let date = calendar.date(from: DateComponents(year: year, month: month, day: 15)) ?? .now
        var style = Date.FormatStyle(date: .omitted, time: .omitted).month(.wide).year()
        style.locale = locale
        style.calendar = calendar
        return date.formatted(style)
    }

    /// "20–34mm", "under 20mm", "300mm and longer" — the span of one angle
    /// group, or of two adjacent ones merged.
    static func focalRange(_ buckets: [FocalAngleBucket]) -> String {
        let lower = buckets.first?.range.lowerBound.map { Int($0) }
        let upper = buckets.last?.range.upperBound.map { Int($0.rounded(.down)) }
        switch (lower, upper) {
        case let (lower?, upper?):
            return "\(lower)–\(focalLength(upper))"
        case let (nil, upper?):
            return String(localized: "under \(focalLength(upper + 1))", table: table,
                          comment: "Insights: the shortest angle-of-view group, e.g. under 20mm")
        case let (lower?, nil):
            return String(localized: "\(focalLength(lower)) and longer", table: table,
                          comment: "Insights: the longest angle-of-view group, e.g. 300mm and longer")
        case (nil, nil):
            return ""
        }
    }

    static func groupName(_ buckets: [FocalAngleBucket], locale: Locale = .current) -> String {
        let names = buckets.map { name(of: $0, locale: locale) }
        return names.formatted(.list(type: .and).locale(locale))
    }

    static func name(of bucket: FocalAngleBucket, locale: Locale = .current) -> String {
        switch bucket {
        case .ultraWide: String(localized: "Ultra-wide", table: table, locale: locale, comment: "Angle-of-view group")
        case .wide: String(localized: "Wide", table: table, locale: locale, comment: "Angle-of-view group")
        case .standard: String(localized: "Standard", table: table, locale: locale, comment: "Angle-of-view group")
        case .portrait: String(localized: "Portrait", table: table, locale: locale, comment: "Angle-of-view group")
        case .telephoto: String(localized: "Telephoto", table: table, locale: locale, comment: "Angle-of-view group")
        case .superTelephoto: String(localized: "Super telephoto", table: table, locale: locale, comment: "Angle-of-view group")
        }
    }
}
