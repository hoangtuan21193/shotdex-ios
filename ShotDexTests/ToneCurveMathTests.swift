import Foundation
import Testing
@testable import ShotDex

struct ToneCurveMathTests {
    @Test func linearCurveIsAPassthroughRamp() {
        let lut = ToneCurveMath.lut(points: ToneCurveAdjustments.linear, count: 256)
        #expect(lut.count == 256)
        #expect(abs(lut[0]) < 0.001)
        #expect(abs(lut[255] - 1) < 0.001)
        for k in stride(from: 0, to: 256, by: 17) {
            #expect(abs(Double(lut[k]) - Double(k) / 255) < 0.01)
        }
    }

    @Test func endpointsStayAnchoredWhenAMidpointIsLifted() {
        let points = [
            CurvePoint(x: 0, y: 0),
            CurvePoint(x: 0.5, y: 0.7),
            CurvePoint(x: 1, y: 1),
        ]
        let lut = ToneCurveMath.lut(points: points)
        #expect(abs(lut[0]) < 0.001)
        #expect(abs(lut[255] - 1) < 0.001)
        // The middle is lifted well above the straight line.
        #expect(Double(lut[128]) > 0.6)
    }

    @Test func theCurveNeverReversesEvenAcrossASteepStep() {
        // A near-flat run then a jump: a naive cubic would overshoot and dip.
        let points = [
            CurvePoint(x: 0, y: 0),
            CurvePoint(x: 0.4, y: 0.05),
            CurvePoint(x: 0.5, y: 0.95),
            CurvePoint(x: 1, y: 1),
        ]
        let lut = ToneCurveMath.lut(points: points)
        var previous: Float = -1
        for value in lut {
            #expect(value >= previous - 0.0001)
            previous = value
        }
        #expect(lut.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    @Test func fewerThanTwoUsablePointsFallsBackToIdentity() {
        let lut = ToneCurveMath.lut(points: [CurvePoint(x: 0.3, y: 0.9)])
        #expect(abs(lut[0]) < 0.001)
        #expect(abs(lut[255] - 1) < 0.001)
        #expect(abs(Double(lut[128]) - 0.5) < 0.01)
    }

    @Test func aStraightCurveAddsNoKeyButAShapedOneRoundTrips() throws {
        var recipe = PhotoEditRecipe.identity
        #expect(recipe.curve.isIdentity)
        // Identity recipe encodes without a curve key — byte-compatible with
        // builds that predate the tone curve.
        let identityData = try JSONEncoder().encode(recipe)
        let identityJSON = String(decoding: identityData, as: UTF8.self)
        #expect(!identityJSON.contains("\"curve\""))

        recipe.curve.rgb = [
            CurvePoint(x: 0, y: 0),
            CurvePoint(x: 0.5, y: 0.6),
            CurvePoint(x: 1, y: 1),
        ]
        #expect(!recipe.curve.isIdentity)
        let data = try JSONEncoder().encode(recipe)
        let decoded = try JSONDecoder().decode(PhotoEditRecipe.self, from: data)
        #expect(decoded.curve == recipe.curve)
    }
}
