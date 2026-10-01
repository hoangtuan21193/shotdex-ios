import Foundation

/// One sentence of the Insights card: what it says (the numbers the copy is
/// built from) and the Library filter a tap opens, `nil` when it has none.
struct Insight: Equatable, Sendable {
    var kind: Kind
    /// The photos the sentence talks about, as a Library filter. `nil` makes
    /// the sentence untappable (the slow-shutter one — the filter cannot
    /// compare two columns).
    var filter: FilterCriteria?

    enum Kind: Equatable, Sendable {
        /// One rounded equivalent focal length holds `count` of `denominator`.
        case focalValue(millimetres: Int, count: Int, denominator: Int, namesDenominator: Bool)
        /// One angle-of-view group, or two adjacent ones merged.
        case focalGroup(buckets: [FocalAngleBucket], count: Int, denominator: Int, namesDenominator: Bool)
        case pair(body: String, lens: String, count: Int, denominator: Int, namesDenominator: Bool)
        case slowShutter(count: Int, denominator: Int, namesDenominator: Bool)
        case busiestMonth(year: Int, month: Int, count: Int)
    }

    /// The SF Symbol that heads the sentence's row, one per kind.
    var systemImage: String {
        switch kind {
        case .focalValue, .focalGroup: "scope"
        case .pair: "camera"
        case .slowShutter: "tortoise"
        case .busiestMonth: "calendar"
        }
    }
}

/// What the Insights card shows (FS-07.02 §6).
enum InsightsCardState: Equatable, Sendable {
    /// Nothing indexed: the dashboard shows "No Indexed Photos" and no card.
    case hidden
    /// Under the shared threshold: one line saying how far along it is.
    case belowThreshold(photosWithCamera: Int)
    /// Up to three sentences, plus the unknown-sensor footer when it applies.
    /// Never both empty — no sentence and no footer is `.hidden`.
    case insights([Insight], unknownSensorCount: Int?)
}

/// The rules that turn grouped counts into sentences (FS-07.02 §2–§5). Pure:
/// no clock, no database — the same inputs always give the same list.
enum InsightSelector {
    /// Photos with a camera name needed before any sentence is considered.
    static let minimumPhotos = 50
    static let maximumSentences = 3
    /// Below this share of the photos with a camera, a sentence says what it
    /// counted ("…of your photos with a known equivalent focal length…").
    static let denominatorCoverage = 0.9

    static func cardState(indexedRows: Int, inputs: InsightInputs) -> InsightsCardState {
        guard indexedRows > 0 else { return .hidden }
        guard inputs.photosWithCamera >= minimumPhotos else {
            return .belowThreshold(photosWithCamera: inputs.photosWithCamera)
        }
        let sentences = select(inputs)
        let unknownSensor = unknownSensorSuppressesFocal(inputs) ? inputs.unknownSensorCount : nil
        if sentences.isEmpty && unknownSensor == nil { return .hidden }
        return .insights(sentences, unknownSensorCount: unknownSensor)
    }

    /// The sentences that pass their thresholds, in the fixed order focal →
    /// pair → slow shutter → busiest month, at most three.
    static func select(_ inputs: InsightInputs) -> [Insight] {
        guard inputs.photosWithCamera >= minimumPhotos else { return [] }
        let candidates = [focal(inputs), pair(inputs), slowShutter(inputs), busiestMonth(inputs)]
        return Array(candidates.compactMap { $0 }.prefix(maximumSentences))
    }

    // MARK: Focal length (§5)

    /// Half or more of the photos with a real focal length have no equivalent
    /// (a camera with an unknown sensor): a focal sentence would describe the
    /// minority, so there is none, and the footer says why.
    static func unknownSensorSuppressesFocal(_ inputs: InsightInputs) -> Bool {
        inputs.actualFocalCount > 0 && inputs.unknownSensorCount * 2 >= inputs.actualFocalCount
    }

    static func focal(_ inputs: InsightInputs) -> Insight? {
        guard !unknownSensorSuppressesFocal(inputs) else { return nil }
        let total = inputs.equivalentFocalTotal
        guard total > 0 else { return nil }
        let namesDenominator = namesDenominator(total, inputs)

        // 1. One value holds half or more — the shortest wins a tie.
        if let (millimetres, count) = inputs.equivalentFocalCounts
            .sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key })
            .first, isHalfOrMore(count, of: total) {
            var filter = FilterCriteria()
            // The rounding bucket of the SQL count: ROUND() sends 25.5 to 26
            // and 26.5 to 27, so the upper bound stops just below n + 0.5.
            filter.focalRange = NumericRangeFilter(
                lowerBound: Double(millimetres) - 0.5,
                upperBound: Double(millimetres) + 0.5 - 0.0001
            )
            filter.focalLengthMode = .equivalent
            return Insight(
                kind: .focalValue(millimetres: millimetres, count: count, denominator: total, namesDenominator: namesDenominator),
                filter: filter
            )
        }

        // 2. The fullest angle-of-view group of the Library filter — the
        // shorter group wins a tie (allCases runs short to long).
        let buckets = FocalAngleBucket.allCases
        let counts = buckets.map { inputs.focalAngleCounts[$0] ?? 0 }
        guard let best = counts.indices.max(by: { counts[$0] < counts[$1] || (counts[$0] == counts[$1] && $0 > $1) }),
              counts[best] > 0 else { return nil }
        if isHalfOrMore(counts[best], of: total) {
            return groupInsight([buckets[best]], count: counts[best], total: total, namesDenominator: namesDenominator)
        }

        // 3. Merged with its fuller neighbour (the shorter one on a tie).
        let neighbours = [best - 1, best + 1].filter { counts.indices.contains($0) }
        guard let neighbour = neighbours.max(by: { counts[$0] < counts[$1] || (counts[$0] == counts[$1] && $0 > $1) }) else {
            return nil
        }
        let merged = counts[best] + counts[neighbour]
        guard isHalfOrMore(merged, of: total) else { return nil }
        let pair = [min(best, neighbour), max(best, neighbour)].map { buckets[$0] }
        return groupInsight(pair, count: merged, total: total, namesDenominator: namesDenominator)
    }

    private static func groupInsight(
        _ buckets: [FocalAngleBucket], count: Int, total: Int, namesDenominator: Bool
    ) -> Insight {
        var filter = FilterCriteria()
        filter.focalRange = NumericRangeFilter(
            lowerBound: buckets.first?.range.lowerBound,
            upperBound: buckets.last?.range.upperBound
        )
        filter.focalLengthMode = .equivalent
        return Insight(
            kind: .focalGroup(buckets: buckets, count: count, denominator: total, namesDenominator: namesDenominator),
            filter: filter
        )
    }

    // MARK: Body + lens

    /// ≥ 50 photos with both names, ≥ 2 pairs, the first ≥ 20%.
    static func pair(_ inputs: InsightInputs) -> Insight? {
        let total = inputs.photosWithCameraAndLens
        guard total >= minimumPhotos, inputs.topPairs.count >= 2 else { return nil }
        let top = inputs.topPairs.sorted {
            ($0.count, $1.body, $1.lens) > ($1.count, $0.body, $0.lens)
        }[0]
        guard top.count * 5 >= total else { return nil }
        var filter = FilterCriteria()
        filter.cameraBodies = [top.body]
        filter.lenses = [top.lens]
        filter.mediaKinds = [.photo]
        return Insight(
            kind: .pair(body: top.body, lens: top.lens, count: top.count, denominator: total,
                        namesDenominator: namesDenominator(total, inputs)),
            filter: filter
        )
    }

    // MARK: Slow shutter

    /// ≥ 50 photos with a shutter speed and an equivalent, ≥ 5% slow. No
    /// filter: "slower than 1/focal length" compares two columns.
    static func slowShutter(_ inputs: InsightInputs) -> Insight? {
        let total = inputs.shutterAndFocalCount
        guard total >= minimumPhotos, inputs.slowShutterCount * 20 >= total else { return nil }
        return Insight(
            kind: .slowShutter(count: inputs.slowShutterCount, denominator: total,
                               namesDenominator: namesDenominator(total, inputs)),
            filter: nil
        )
    }

    // MARK: Busiest month

    /// ≥ 3 months with photos; the busiest has ≥ 50 and ≥ 2 × the median
    /// month. A tie goes to the more recent month.
    static func busiestMonth(_ inputs: InsightInputs) -> Insight? {
        let months = inputs.monthCounts.filter { $0.count > 0 }
        guard months.count >= 3 else { return nil }
        let busiest = months.max {
            ($0.count, $0.year, $0.month) < ($1.count, $1.year, $1.month)
        }!
        guard busiest.count >= minimumPhotos,
              Double(busiest.count) >= 2 * median(months.map(\.count)) else { return nil }
        return Insight(
            kind: .busiestMonth(year: busiest.year, month: busiest.month, count: busiest.count),
            filter: monthFilter(year: busiest.year, month: busiest.month)
        )
    }

    /// The Library filter for one month's photos, or `nil` while the filter
    /// has no month condition.
    static func monthFilter(year: Int, month: Int) -> FilterCriteria? {
        nil
    }

    /// The middle value; with an even count, the mean of the two middle ones.
    static func median(_ values: [Int]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? Double(sorted[middle - 1] + sorted[middle]) / 2
            : Double(sorted[middle])
    }

    // MARK: Helpers

    private static func isHalfOrMore(_ count: Int, of total: Int) -> Bool {
        total > 0 && count * 2 >= total
    }

    /// A sentence names its denominator when that covers under 90% of the
    /// photos with a camera name.
    private static func namesDenominator(_ denominator: Int, _ inputs: InsightInputs) -> Bool {
        Double(denominator) < denominatorCoverage * Double(inputs.photosWithCamera)
    }
}
