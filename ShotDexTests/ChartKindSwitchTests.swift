import Foundation
import Testing
@testable import ShotDex

/// The Donut · Bars switch on a Statistics card (DUO_LOOP 13b): offered only
/// where both kinds draw the same data, and a switch changes the kind alone.
struct ChartKindSwitchTests {
    @Test func countedCategoricalChartsSwitchBothWays() throws {
        let donut = ChartSpec(title: "Top Camera", kind: .donut, dimension: .cameraBody)
        #expect(donut.switchesBetweenDonutAndBars)

        let bars = try #require(donut.switched(to: .bar))
        #expect(bars.kind == .bar)
        #expect(bars.id == donut.id)
        #expect(bars.title == donut.title)
        #expect(bars.dimension == donut.dimension)
        #expect(bars.topN == donut.topN)
        #expect(bars.scope == donut.scope)

        #expect(bars.switched(to: .donut)?.kind == .donut)
    }

    @Test func barsWithNoDonutShapeHaveNoSwitch() {
        // An average has no share to draw.
        let average = ChartSpec(
            title: "Average ISO by lens", kind: .bar, dimension: .lens,
            metric: ChartMetric(aggregation: .average, field: .iso)
        )
        #expect(!average.switchesBetweenDonutAndBars)
        #expect(average.switched(to: .donut) == nil)

        // Binned and cyclic axes are not shares of a whole either.
        #expect(!ChartSpec(title: "ISO", kind: .bar, dimension: .iso).switchesBetweenDonutAndBars)
        #expect(!ChartSpec(title: "Hours", kind: .bar, dimension: .hourOfDay).switchesBetweenDonutAndBars)
    }

    @Test func otherKindsHaveNoSwitch() {
        #expect(!ChartSpec(title: "Total", kind: .kpi, dimension: nil).switchesBetweenDonutAndBars)
        let donut = ChartSpec(title: "Top Lens", kind: .donut, dimension: .lens)
        #expect(donut.switched(to: .line) == nil)
        #expect(donut.switched(to: .kpi) == nil)
    }
}
