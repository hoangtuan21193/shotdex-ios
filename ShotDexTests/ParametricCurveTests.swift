import CoreImage
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

    /// AC-9. The region curve and the RGB point curve are baked into the one
    /// curve pass: a grey ramp through it matches the hand-made "region, then
    /// point" table to 1/255.
    @Test func regionThenPointIsOneTable() throws {
        var curve = ToneCurveAdjustments()
        curve.region.lights = 0.3
        curve.rgb = try #require(ToneCurveAdjustments.presets.first { $0.id == "softS" }).points

        let width = 256
        var ramp = [UInt8](repeating: 255, count: width * 4)
        for x in 0..<width {
            ramp[x * 4] = UInt8(x); ramp[x * 4 + 1] = UInt8(x); ramp[x * 4 + 2] = UInt8(x)
        }
        let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let input = CIImage(
            bitmapData: Data(ramp),
            bytesPerRow: width * 4,
            size: CGSize(width: width, height: 1),
            format: .RGBA8,
            colorSpace: sRGB
        )
        let output = PhotoRenderService.applyCurve(curve, to: input)
        var result = [UInt8](repeating: 0, count: width * 4)
        CIContext().render(
            output, toBitmap: &result, rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: 1),
            format: .RGBA8, colorSpace: sRGB
        )

        let expected = ParametricCurveMath.combinedLUT(region: curve.region, points: curve.rgb)
        var worst = 0
        for x in 0..<width {
            worst = max(worst, abs(Int(result[x * 4]) - Int((expected[x] * 255).rounded())))
        }
        #expect(worst <= 1, "curve pass differs from region-then-point by \(worst)/255")

        // One pass: the curve stage builds a single colour-curves filter.
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("ShotDexKit/Render/PhotoRenderService+Curve.swift"),
            encoding: .utf8
        )
        #expect(source.components(separatedBy: "\"CIColorCurves\"").count - 1 == 1)
    }
}
