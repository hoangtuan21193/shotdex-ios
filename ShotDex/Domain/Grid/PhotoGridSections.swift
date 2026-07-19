import Foundation

/// One date section of the photo grid: a contiguous run of flat indices into
/// the (already date-sorted) photos array — same contract as
/// `OnThisDayYearSection`, so tap/paging/swipe-select keep flat-index math.
struct PhotoGridSection: Equatable, Identifiable, Sendable {
    enum Kind: Hashable, Sendable {
        /// Normalized to start-of-day (`.day`) or start-of-month (`.month`).
        case date(Date)
        case undated
    }

    let kind: Kind
    let range: Range<Int>

    var id: String {
        switch kind {
        case .date(let date): String(Int(date.timeIntervalSince1970))
        case .undated: "undated"
        }
    }
}

/// Groups a date-sorted photo list into day/month sections in one pass.
enum PhotoGridSectionBuilder {
    /// - Parameter creationDates: `photos.map(\.creationDateValue)`, already
    ///   sorted newest-first or oldest-first. nil dates are grouped into one
    ///   `.undated` run (they arrive consecutively — SQL sorts NULLS LAST).
    /// - Note: order-agnostic — only *consecutive runs* of the same
    ///   day/month are merged, so both sort directions work.
    static func sections(
        creationDates: [Date?],
        granularity: PhotoGridDateGranularity,
        calendar: Calendar = .current
    ) -> [PhotoGridSection] {
        var sections: [PhotoGridSection] = []
        var runStart = 0
        var runKind: PhotoGridSection.Kind?

        for (index, date) in creationDates.enumerated() {
            let kind = kind(for: date, granularity: granularity, calendar: calendar)
            if kind != runKind {
                if let runKind {
                    sections.append(PhotoGridSection(kind: runKind, range: runStart..<index))
                }
                runStart = index
                runKind = kind
            }
        }
        if let runKind {
            sections.append(PhotoGridSection(kind: runKind, range: runStart..<creationDates.count))
        }
        return sections
    }

    private static func kind(
        for date: Date?,
        granularity: PhotoGridDateGranularity,
        calendar: Calendar
    ) -> PhotoGridSection.Kind {
        guard let date else { return .undated }
        switch granularity {
        case .day:
            return .date(calendar.startOfDay(for: date))
        case .month:
            let components = calendar.dateComponents([.year, .month], from: date)
            return .date(calendar.date(from: components) ?? calendar.startOfDay(for: date))
        }
    }
}
