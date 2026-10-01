import Foundation
import Testing
@testable import ShotDex

/// FS-07.02 Insights: the pure selection rules, the sentence copy, and the
/// SQL that feeds them (in-memory GRDB).
struct StatisticsInsightsTests {

    // MARK: Selector (AC-7 and the thresholds of §2–§5)

    /// The AC-7 numbers: focal 85% at 26mm, top pair 40%, 18% slow, August
    /// 2026 with 1,240 photos against a 300 median.
    private func ac7Inputs() -> InsightInputs {
        var inputs = InsightInputs()
        inputs.photosWithCamera = 1000
        inputs.equivalentFocalCounts = [26: 850, 77: 150]
        inputs.focalAngleCounts = [.wide: 850, .portrait: 150]
        inputs.actualFocalCount = 1000
        inputs.topPairs = [
            .init(body: "EOS R6", lens: "RF 85mm F1.2 L USM", count: 400),
            .init(body: "iPhone 15 Pro", lens: "iPhone 15 Pro back triple camera 6.765mm f/1.78", count: 380),
        ]
        inputs.photosWithCameraAndLens = 1000
        inputs.slowShutterCount = 180
        inputs.shutterAndFocalCount = 1000
        inputs.monthCounts = [
            .init(year: 2026, month: 5, count: 300), .init(year: 2026, month: 6, count: 300),
            .init(year: 2026, month: 7, count: 280), .init(year: 2026, month: 8, count: 1240),
            .init(year: 2026, month: 9, count: 320),
        ]
        return inputs
    }

    /// AC-7: three sentences, focal → pair → slow, the month dropped as the
    /// fourth; a second run gives the identical list.
    @Test func selectorKeepsFixedOrderAndDropsFourth() {
        let inputs = ac7Inputs()
        #expect(InsightSelector.median(inputs.monthCounts.map(\.count)) == 300)
        #expect(InsightSelector.busiestMonth(inputs) != nil, "the month qualifies on its own")

        let sentences = InsightSelector.select(inputs)
        #expect(sentences.count == 3)
        guard sentences.count == 3 else { return }
        #expect(sentences[0].kind == .focalValue(millimetres: 26, count: 850, denominator: 1000, namesDenominator: false))
        #expect(sentences[1].kind == .pair(
            body: "EOS R6", lens: "RF 85mm F1.2 L USM", count: 400, denominator: 1000, namesDenominator: false
        ))
        #expect(sentences[2].kind == .slowShutter(count: 180, denominator: 1000, namesDenominator: false))
        #expect(!sentences.contains { if case .busiestMonth = $0.kind { true } else { false } })
    }

    @Test func selectorIsDeterministic() {
        let inputs = ac7Inputs()
        let first = InsightSelector.select(inputs)
        for _ in 0..<5 { #expect(InsightSelector.select(inputs) == first) }
        #expect(InsightSelector.cardState(indexedRows: 1000, inputs: inputs)
            == InsightSelector.cardState(indexedRows: 1000, inputs: inputs))
    }

    @Test func sharedThresholdIsFiftyPhotosWithCamera() {
        var inputs = ac7Inputs()
        inputs.photosWithCamera = 49
        #expect(InsightSelector.select(inputs).isEmpty)
        #expect(InsightSelector.cardState(indexedRows: 279, inputs: inputs) == .belowThreshold(photosWithCamera: 49))
        inputs.photosWithCamera = 50
        #expect(!InsightSelector.select(inputs).isEmpty)
        #expect(InsightSelector.cardState(indexedRows: 0, inputs: inputs) == .hidden)
    }

    @Test func pairNeedsTwentyPercentTwoPairsAndFiftyPhotos() {
        var inputs = InsightInputs()
        inputs.photosWithCamera = 1000
        inputs.photosWithCameraAndLens = 1000
        inputs.topPairs = [.init(body: "A", lens: "x", count: 199), .init(body: "B", lens: "y", count: 150)]
        #expect(InsightSelector.pair(inputs) == nil, "19.9% stays out")
        inputs.topPairs[0].count = 200
        #expect(InsightSelector.pair(inputs) != nil, "20% is in")
        inputs.topPairs.removeLast()
        #expect(InsightSelector.pair(inputs) == nil, "one pair is not a habit")
        inputs.topPairs = [.init(body: "A", lens: "x", count: 30), .init(body: "B", lens: "y", count: 19)]
        inputs.photosWithCameraAndLens = 49
        #expect(InsightSelector.pair(inputs) == nil, "49 photos with both names")
    }

    @Test func pairTieGoesToNameOrder() {
        var inputs = InsightInputs()
        inputs.photosWithCamera = 100
        inputs.photosWithCameraAndLens = 100
        inputs.topPairs = [.init(body: "Z9", lens: "a", count: 50), .init(body: "A7", lens: "b", count: 50)]
        guard case .pair(let body, _, _, _, _) = InsightSelector.pair(inputs)?.kind else {
            Issue.record("no pair sentence"); return
        }
        #expect(body == "A7")
    }

    @Test func slowShutterNeedsFivePercent() {
        var inputs = InsightInputs()
        inputs.photosWithCamera = 1000
        inputs.shutterAndFocalCount = 1000
        inputs.slowShutterCount = 49
        #expect(InsightSelector.slowShutter(inputs) == nil, "4.9% stays out")
        inputs.slowShutterCount = 50
        #expect(InsightSelector.slowShutter(inputs) != nil, "5% is in")
        #expect(InsightSelector.slowShutter(inputs)?.filter == nil, "no filter can say it")
    }

    @Test func busiestMonthNeedsTwiceTheMedian() {
        var inputs = InsightInputs()
        inputs.photosWithCamera = 1000
        inputs.monthCounts = [
            .init(year: 2026, month: 1, count: 100), .init(year: 2026, month: 2, count: 100),
            .init(year: 2026, month: 3, count: 199),
        ]
        #expect(InsightSelector.busiestMonth(inputs) == nil, "1.99 × the median")
        inputs.monthCounts[2].count = 200
        #expect(InsightSelector.busiestMonth(inputs)?.kind == .busiestMonth(year: 2026, month: 3, count: 200))
        inputs.monthCounts.removeFirst()
        #expect(InsightSelector.busiestMonth(inputs) == nil, "two months are not enough")
    }

    @Test func busiestMonthTieGoesToTheRecentOne() {
        var inputs = InsightInputs()
        inputs.photosWithCamera = 1000
        inputs.monthCounts = [
            .init(year: 2025, month: 3, count: 400), .init(year: 2026, month: 1, count: 10),
            .init(year: 2026, month: 2, count: 10), .init(year: 2026, month: 3, count: 400),
            .init(year: 2026, month: 4, count: 10),
        ]
        #expect(InsightSelector.busiestMonth(inputs)?.kind == .busiestMonth(year: 2026, month: 3, count: 400))
        // An even number of months: the median is the mean of the middle two.
        #expect(InsightSelector.median([300, 280, 1240, 320]) == 310)
    }

    /// §5: a value with half → that value (shorter on a tie); else the
    /// fullest Library angle group; else that group with its fuller
    /// neighbour; else nothing.
    @Test func focalFallsBackFromValueToGroupToMergedGroups() {
        var inputs = InsightInputs()
        inputs.photosWithCamera = 100
        inputs.actualFocalCount = 100

        inputs.equivalentFocalCounts = [24: 50, 50: 50]
        inputs.focalAngleCounts = [.wide: 50, .standard: 50]
        #expect(InsightSelector.focal(inputs)?.kind
            == .focalValue(millimetres: 24, count: 50, denominator: 100, namesDenominator: false))

        inputs.equivalentFocalCounts = [24: 30, 28: 30, 85: 40]
        inputs.focalAngleCounts = [.wide: 60, .portrait: 40]
        let group = InsightSelector.focal(inputs)
        #expect(group?.kind == .focalGroup(buckets: [.wide], count: 60, denominator: 100, namesDenominator: false))
        #expect(group?.filter?.focalRange == FocalAngleBucket.wide.range)
        #expect(group?.filter?.focalLengthMode == .equivalent)

        inputs.equivalentFocalCounts = [16: 10, 24: 40, 50: 20, 85: 30]
        inputs.focalAngleCounts = [.ultraWide: 10, .wide: 40, .standard: 20, .portrait: 30]
        let merged = InsightSelector.focal(inputs)
        #expect(merged?.kind == .focalGroup(buckets: [.wide, .standard], count: 60, denominator: 100, namesDenominator: false))
        #expect(merged?.filter?.focalRange == NumericRangeFilter(lowerBound: 20, upperBound: 69.999))

        inputs.equivalentFocalCounts = [16: 25, 50: 25, 100: 25, 400: 25]
        inputs.focalAngleCounts = [.ultraWide: 25, .standard: 25, .portrait: 25, .superTelephoto: 25]
        #expect(InsightSelector.focal(inputs) == nil)
    }

    /// The value sentence's filter covers exactly the SQL ROUND() bucket.
    @Test func focalValueFilterIsTheRoundingBucket() {
        var inputs = InsightInputs()
        inputs.photosWithCamera = 1000
        inputs.actualFocalCount = 1000
        inputs.equivalentFocalCounts = [26: 850, 77: 150]
        let range = InsightSelector.focal(inputs)?.filter?.focalRange
        #expect(range?.contains(25.5) == true)
        #expect(range?.contains(26.4999) == true)
        #expect(range?.contains(26.5) == false)
        #expect(range?.contains(25.4999) == false)
    }

    @Test func unknownSensorHalfSuppressesFocalAndShowsFooter() {
        var inputs = InsightInputs()
        inputs.photosWithCamera = 200
        inputs.actualFocalCount = 200
        inputs.unknownSensorCount = 180
        inputs.equivalentFocalCounts = [50: 20]
        inputs.focalAngleCounts = [.standard: 20]
        #expect(InsightSelector.focal(inputs) == nil)
        #expect(InsightSelector.cardState(indexedRows: 200, inputs: inputs) == .insights([], unknownSensorCount: 180))

        inputs.unknownSensorCount = 99
        inputs.equivalentFocalCounts = [50: 101]
        #expect(InsightSelector.focal(inputs) != nil)
    }
}
