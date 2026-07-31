import Foundation
import Testing

@testable import ShotDex

struct ColorRenderMathTests {
    // MARK: - Band weights

    @Test func bandWeightsSumToOneAcrossTheWheel() {
        for hue in stride(from: 0.0, to: 360, by: 1) {
            let sum = ColorRenderMath.bandWeights(hueDegrees: hue).reduce(0, +)
            #expect(abs(sum - 1) < 0.0001, "hue \(hue)")
        }
    }

    @Test func bandWeightIsOneAtEveryCenter() {
        for (index, band) in ColorMixerBand.allCases.enumerated() {
            let weights = ColorRenderMath.bandWeights(hueDegrees: band.centerDegrees)
            #expect(abs(weights[index] - 1) < 0.0001, "\(band)")
        }
    }

    @Test func redWeightIsSymmetricAcrossTheWrap() {
        // Magenta sits at 320°, red at 0°/360°: 350° is 30° past magenta and
        // 10° short of red; 10° must mirror it exactly on the other side of red
        // relative to orange's 30° span scaled to the segment widths.
        let below = ColorRenderMath.bandWeights(hueDegrees: 350)
        let above = ColorRenderMath.bandWeights(hueDegrees: 10)
        #expect(below[0] > 0 && below[7] > 0)
        #expect(above[0] > 0 && above[1] > 0)
        // 350° is 3/4 through the magenta→red segment; 10° is 1/3 through
        // red→orange. Both must give red the smoothstep of their fraction.
        #expect(abs(below[0] - smoothstep(0.75)) < 0.0001)
        #expect(abs(above[0] - (1 - smoothstep(1.0 / 3.0))) < 0.0001)
    }

    @Test func exactlyTwoBandsCarryWeightBetweenCenters() {
        let weights = ColorRenderMath.bandWeights(hueDegrees: 90)
        let nonZero = weights.filter { $0 > 0.0001 }
        #expect(nonZero.count == 2)
    }

    private func smoothstep(_ t: Double) -> Double {
        t * t * (3 - 2 * t)
    }

    // MARK: - Region weights

    @Test func regionWeightsAtTheExtremes() {
        let dark = ColorRenderMath.regionWeights(luma: 0, blending: 0.5, balance: 0)
        #expect(dark.shadows > 0.99)
        #expect(dark.highlights < 0.01)

        let bright = ColorRenderMath.regionWeights(luma: 1, blending: 0.5, balance: 0)
        #expect(bright.highlights > 0.99)
        #expect(bright.shadows < 0.01)

        let middle = ColorRenderMath.regionWeights(luma: 0.5, blending: 0.5, balance: 0)
        #expect(middle.midtones > middle.shadows)
        #expect(middle.midtones > middle.highlights)
    }

    @Test func positiveBalanceGrowsTheShadowRegion() {
        let neutral = ColorRenderMath.regionWeights(luma: 0.45, blending: 0.5, balance: 0)
        let pushed = ColorRenderMath.regionWeights(luma: 0.45, blending: 0.5, balance: 1)
        #expect(pushed.shadows > neutral.shadows)
    }

    @Test func higherBlendingWidensTheOverlap() {
        // With a wider feather, a pixel just outside the shadow pivot keeps
        // more shadow membership.
        let narrow = ColorRenderMath.regionWeights(luma: 0.45, blending: 0, balance: 0)
        let wide = ColorRenderMath.regionWeights(luma: 0.45, blending: 1, balance: 0)
        #expect(wide.shadows > narrow.shadows)
    }

    // MARK: - Point weight

    @Test func pointWeightIsFullAtTheReference() {
        let reference = ColorRenderMath.HSV(hue: 210, saturation: 0.7, value: 0.5)
        #expect(ColorRenderMath.pointWeight(pixel: reference, reference: reference, range: 0.5) == 1)
    }

    @Test func pointWeightFallsWithHueDistance() {
        let reference = ColorRenderMath.HSV(hue: 210, saturation: 0.7, value: 0.5)
        var previous = 1.0
        for offset in stride(from: 0.0, through: 60, by: 5) {
            let pixel = ColorRenderMath.HSV(hue: 210 + offset, saturation: 0.7, value: 0.5)
            let weight = ColorRenderMath.pointWeight(pixel: pixel, reference: reference, range: 0.5)
            #expect(weight <= previous + 0.0001, "offset \(offset)")
            previous = weight
        }
    }

    @Test func pointWeightIsZeroFarOutsideTheRange() {
        let reference = ColorRenderMath.HSV(hue: 0, saturation: 1, value: 0.5)
        let opposite = ColorRenderMath.HSV(hue: 180, saturation: 1, value: 0.5)
        #expect(ColorRenderMath.pointWeight(pixel: opposite, reference: reference, range: 1) == 0)
    }

    @Test func widerRangeMatchesMore() {
        let reference = ColorRenderMath.HSV(hue: 210, saturation: 0.7, value: 0.5)
        let pixel = ColorRenderMath.HSV(hue: 230, saturation: 0.6, value: 0.6)
        let tight = ColorRenderMath.pointWeight(pixel: pixel, reference: reference, range: 0)
        let wide = ColorRenderMath.pointWeight(pixel: pixel, reference: reference, range: 1)
        #expect(wide >= tight)
        #expect(wide > 0)
    }

    @Test func hueDistanceWrapsAroundTheWheel() {
        #expect(ColorRenderMath.circularHueDistance(350, 10) == 20)
        #expect(ColorRenderMath.circularHueDistance(0, 180) == 180)
        #expect(ColorRenderMath.circularHueDistance(90, 90) == 0)
    }

    // MARK: - HSV conversion

    @Test func hsvRoundTripsPrimariesAndGrays() {
        let samples: [(Double, Double, Double)] = [
            (1, 0, 0), (0, 1, 0), (0, 0, 1),
            (1, 1, 0), (0, 1, 1), (1, 0, 1),
            (0, 0, 0), (1, 1, 1), (0.5, 0.5, 0.5),
            (0.8, 0.3, 0.1), (0.2, 0.6, 0.9),
        ]
        for (red, green, blue) in samples {
            let hsv = ColorRenderMath.hsv(fromRed: red, green: green, blue: blue)
            let rgb = ColorRenderMath.rgb(from: hsv)
            #expect(abs(rgb.red - red) < 0.0001, "\(red),\(green),\(blue)")
            #expect(abs(rgb.green - green) < 0.0001, "\(red),\(green),\(blue)")
            #expect(abs(rgb.blue - blue) < 0.0001, "\(red),\(green),\(blue)")
        }
    }

    @Test func knownHues() {
        #expect(ColorRenderMath.hsv(fromRed: 1, green: 0, blue: 0).hue == 0)
        #expect(ColorRenderMath.hsv(fromRed: 0, green: 1, blue: 0).hue == 120)
        #expect(ColorRenderMath.hsv(fromRed: 0, green: 0, blue: 1).hue == 240)
        #expect(ColorRenderMath.hsv(fromRed: 0, green: 0, blue: 0).saturation == 0)
    }
}
