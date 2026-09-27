import Foundation
import Testing
@testable import ShotDexKit

/// FS-03.15 AC-7, AC-8 — the region curve.
struct ParametricCurveTests {

    private func output(_ table: [Float], at input: Double) -> Double {
        let position = input * Double(table.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(table.count - 1, lower + 1)
        let t = position - Double(lower)
        return Double(table[lower]) * (1 - t) + Double(table[upper]) * t
    }

    /// AC-7. Shadows +50 with the default splits lifts the dark quarter and
    /// leaves the ends and the top of the range alone.
    @Test func shadowsLiftTheDarkQuarterOnly() {
        var curve = ParametricCurve()
        curve.shadows = 0.5
        let table = ParametricCurveMath.lut(curve)

        let lift = output(table, at: 0.15) - 0.15
        #expect(lift >= 0.02 && lift <= 0.08, "lift at 0.15 was \(lift)")
        #expect(abs(output(table, at: 0)) <= 1.0 / 255)
        #expect(abs(output(table, at: 1) - 1) <= 1.0 / 255)
        for input in stride(from: 0.85, through: 1.0, by: 0.01) {
            #expect(abs(output(table, at: input) - input) <= 2.0 / 255, "moved at \(input)")
        }
    }

    /// AC-8. Every sign combination of the four regions at ±100, with the splits
    /// pushed to 10 / 50 / 90, gives a table that never goes down and keeps its
    /// ends.
    @Test func everyExtremeStaysMonotone() {
        for combination in 0..<16 {
            var curve = ParametricCurve()
            curve.shadows = combination & 1 == 0 ? 1 : -1
            curve.darks = combination & 2 == 0 ? 1 : -1
            curve.lights = combination & 4 == 0 ? 1 : -1
            curve.highlights = combination & 8 == 0 ? 1 : -1
            curve.shadowSplit = 0.1
            curve.midtoneSplit = 0.5
            curve.highlightSplit = 0.9
            let table = ParametricCurveMath.lut(curve)
            for index in 1..<table.count {
                #expect(table[index] >= table[index - 1], "combination \(combination) falls at \(index)")
            }
            #expect(abs(table.first! - 0) <= 1.0 / 255)
            #expect(abs(table.last! - 1) <= 1.0 / 255)
        }
    }

    /// An untouched region curve is the identity whatever its splits say.
    @Test func untouchedIsTheIdentity() {
        var curve = ParametricCurve()
        curve.midtoneSplit = 0.7
        let table = ParametricCurveMath.lut(curve)
        for (index, value) in table.enumerated() {
            #expect(abs(Double(value) - Double(index) / 255) <= 1e-6)
        }
    }
}
