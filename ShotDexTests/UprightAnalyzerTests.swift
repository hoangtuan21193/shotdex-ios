import CoreGraphics
import Foundation
import Testing
@testable import ShotDexKit

/// Upright in two halves: the geometry that turns lines into geo values (most
/// of these — pure, exact), and the detector that finds those lines in pixels
/// (the last few, on synthetic images with known edges in them).
struct UprightAnalyzerTests {

    /// A segment at `degrees` from horizontal, centred at `midX`.
    private func segment(degrees: Double, midX: Double = 0.5, weight: Double = 1) -> UprightSegment {
        let radians = degrees * .pi / 180
        let half = 0.3
        let dx = cos(radians) * half
        let dy = sin(radians) * half
        return UprightSegment(
            start: CGPoint(x: midX - dx, y: 0.5 - dy),
            end: CGPoint(x: midX + dx, y: 0.5 + dy),
            weight: weight
        )
    }

    // MARK: Level

    /// A horizon tilted 5° up to the right needs a rotation back the other way,
    /// in the units `applyGeo` multiplies by 0.35 radians.
    @Test func aTiltedHorizonRotatesBack() {
        let rotate = UprightAnalyzer.levelRotation(from: [segment(degrees: 5)])
        let expected = -(5 * Double.pi / 180) / 0.35
        #expect(abs(rotate - expected) < 0.001)
        #expect(rotate < 0)
    }

    /// Tilt is tilt whichever way it leans.
    @Test func theCorrectionFollowsTheSignOfTheTilt() {
        #expect(UprightAnalyzer.levelRotation(from: [segment(degrees: -4)]) > 0)
        #expect(UprightAnalyzer.levelRotation(from: [segment(degrees: 4)]) < 0)
    }

    /// A door frame says as much about tilt as a horizon does: 87° off
    /// horizontal is 3° off vertical, and the frame is tilted by 3°.
    @Test func aNearVerticalLineMeasuresTiltToo() {
        let rotate = UprightAnalyzer.levelRotation(from: [segment(degrees: 87)])
        let expected = -(-3 * Double.pi / 180) / 0.35
        #expect(abs(rotate - expected) < 0.001)
    }

    /// One strong diagonal must not drag the answer off the majority — the
    /// reason this is a median and not a mean.
    @Test func aStaircaseDoesNotOutvoteThreeLevelEdges() {
        let segments = [
            segment(degrees: 2),
            segment(degrees: 2.5),
            segment(degrees: 2),
            segment(degrees: 18, weight: 6),
        ]
        let rotate = UprightAnalyzer.levelRotation(from: segments)
        let expected = -(2.5 * Double.pi / 180) / 0.35
        #expect(abs(rotate - expected) < 0.2)
    }

    /// A real diagonal — a road, a roofline at 35° — is part of the picture,
    /// not a mistake to correct.
    @Test func aRealDiagonalIsIgnoredEntirely() {
        #expect(UprightAnalyzer.levelRotation(from: [segment(degrees: 35)]) == 0)
        #expect(UprightAnalyzer.levelRotation(from: []) == 0)
    }

    // MARK: Vertical

    /// A building shot from the pavement: the left edge leans right, the right
    /// edge leans left, and the correction is non-zero and signed.
    @Test func convergingVerticalsProduceAKeystone() {
        let segments = [
            segment(degrees: 82, midX: 0.15),
            segment(degrees: -82, midX: 0.85),
        ]
        let keystone = UprightAnalyzer.verticalKeystone(from: segments)
        #expect(keystone != 0)
        // Shot from below, the same photo shot from above must correct the
        // other way.
        let flipped = UprightAnalyzer.verticalKeystone(from: [
            segment(degrees: -82, midX: 0.15),
            segment(degrees: 82, midX: 0.85),
        ])
        #expect(keystone * flipped < 0)
    }

    /// Verticals that are merely *tilted* — both leaning the same way — are a
    /// level problem, not a keystone one, and Vertical must leave them alone.
    @Test func aUniformTiltIsNotConvergence() {
        let segments = [
            segment(degrees: 85, midX: 0.15),
            segment(degrees: 85, midX: 0.85),
        ]
        #expect(abs(UprightAnalyzer.verticalKeystone(from: segments)) < 0.001)
    }

    /// Lines through the middle say nothing about which side the camera was
    /// on, so they cannot carry the estimate on their own.
    @Test func theMiddleThirdDoesNotVote() {
        let segments = [segment(degrees: 82, midX: 0.5), segment(degrees: -82, midX: 0.52)]
        #expect(UprightAnalyzer.verticalKeystone(from: segments) == 0)
    }

    /// Evidence from one side only is not convergence — it could be a leaning
    /// tree — so it produces nothing rather than half an answer.
    @Test func oneSidedEvidenceIsRefused() {
        #expect(UprightAnalyzer.verticalKeystone(from: [segment(degrees: 82, midX: 0.15)]) == 0)
    }

    @Test func correctionsStayInRange() {
        let extreme = [
            segment(degrees: 70, midX: 0.1),
            segment(degrees: -70, midX: 0.9),
        ]
        #expect(abs(UprightAnalyzer.verticalKeystone(from: extreme)) <= 1)
        #expect(abs(UprightAnalyzer.levelRotation(from: [segment(degrees: 19)])) <= 1)
    }

    // MARK: Modes

    @Test func eachModeTouchesOnlyItsOwnControls() {
        let segments = [
            segment(degrees: 4),
            segment(degrees: 82, midX: 0.15),
            segment(degrees: -82, midX: 0.85),
        ]
        let level = UprightAnalyzer.suggestion(from: segments, mode: .level)
        #expect(level.rotate != 0)
        #expect(level.vertical == 0)

        let vertical = UprightAnalyzer.suggestion(from: segments, mode: .vertical)
        #expect(vertical.rotate == 0)
        #expect(vertical.vertical != 0)

        let full = UprightAnalyzer.suggestion(from: segments, mode: .full)
        #expect(full.rotate != 0)
        #expect(full.vertical != 0)
    }

    @Test func applyingASuggestionLeavesTheOtherGeoControlsAlone() {
        var adjustments = PhotoAdjustments.zero
        adjustments.geoScale = 0.4
        adjustments.geoVertical = 0.9

        UprightSuggestion(rotate: 0.3, vertical: 0.2).apply(to: &adjustments, mode: .level)
        #expect(adjustments.geoRotate == 0.3)
        #expect(adjustments.geoVertical == 0.9, "Level must not touch the keystone")
        #expect(adjustments.geoScale == 0.4)

        UprightSuggestion(rotate: 0.5, vertical: 0.2).apply(to: &adjustments, mode: .vertical)
        #expect(adjustments.geoRotate == 0.3, "Vertical must not touch the rotation")
        #expect(adjustments.geoVertical == 0.2)
    }

    @Test func anEmptySuggestionKnowsItIsEmpty() {
        #expect(UprightSuggestion().isEmpty)
        #expect(!UprightSuggestion(rotate: 0.2).isEmpty)
    }

    // MARK: Detection

    /// A 256×192 frame with one bright line drawn across it at a known angle.
    private func frame(width: Int, height: Int, lineDegrees: Double) -> [Float] {
        var pixels = [Float](repeating: 0.15, count: width * height)
        let radians = lineDegrees * .pi / 180
        let steps = max(width, height) * 3
        let cx = Double(width) / 2
        let cy = Double(height) / 2
        let reach = Double(max(width, height))
        for step in 0...steps {
            let t = (Double(step) / Double(steps) - 0.5) * reach
            let x = cx + cos(radians) * t
            // Rows run top-down; the analyzer reports bottom-up, so the drawn
            // angle is negated here to keep the test's wording honest.
            let y = cy - sin(radians) * t
            for dx in -1...1 {
                for dy in -1...1 {
                    let px = Int(x.rounded()) + dx
                    let py = Int(y.rounded()) + dy
                    guard px >= 0, px < width, py >= 0, py < height else { continue }
                    pixels[py * width + px] = 0.95
                }
            }
        }
        return pixels
    }

    @Test func aDrawnLineIsFoundAtTheAngleItWasDrawn() throws {
        let width = 256
        let height = 192
        let found = UprightAnalyzer.segments(
            luminance: frame(width: width, height: height, lineDegrees: 6),
            width: width,
            height: height
        )
        let strongest = try #require(found.first)
        let degrees = strongest.angle * 180 / .pi
        // The segments are normalized to 0…1 on both axes, so a 6° line in a
        // 4:3 frame reads steeper in that space; what matters is the sign and
        // that it is small.
        #expect(degrees > 1)
        #expect(degrees < 20)
    }

    /// End to end on pixels: a frame ruled with parallel lines at a known
    /// tilt must come back with a correction that undoes that tilt. This is
    /// the test that would catch a sign error between the detector's
    /// coordinate space and the geometry's — the two halves are written in
    /// different spaces (rows run down, segments run up) and agreeing about
    /// it is the whole contract.
    @Test(arguments: [-6.0, -3.0, 3.0, 6.0])
    func aRuledFrameIsLevelledBackTheOtherWay(tilt: Double) throws {
        let width = 256
        let height = 256
        var pixels = [Float](repeating: 0.12, count: width * height)
        // Five parallel lines, so the median has a majority to find.
        for line in 0..<5 {
            let offset = Double(line - 2) * 40
            drawLine(
                into: &pixels, width: width, height: height,
                degrees: tilt, offset: offset
            )
        }
        let segments = UprightAnalyzer.segments(
            luminance: pixels, width: width, height: height
        )
        #expect(!segments.isEmpty)

        let rotate = UprightAnalyzer.levelRotation(from: segments)
        // The correction runs against the tilt.
        #expect(rotate * tilt < 0, "tilt \(tilt)° corrected by \(rotate)")
        // And it is the right size: `applyGeo` turns this into
        // `rotate * 0.35` radians.
        let appliedDegrees = rotate * 0.35 * 180 / .pi
        #expect(abs(appliedDegrees + tilt) < 2.5, "tilt \(tilt)° met with \(appliedDegrees)°")
    }

    /// One bright line across a frame at `degrees`, offset perpendicular to
    /// itself. Rows run top-down, which is why the y step is negated: the
    /// analyzer reports angles in a bottom-up space.
    private func drawLine(
        into pixels: inout [Float],
        width: Int,
        height: Int,
        degrees: Double,
        offset: Double
    ) {
        let radians = degrees * .pi / 180
        let cx = Double(width) / 2 - sin(radians) * offset
        let cy = Double(height) / 2 - cos(radians) * offset
        let reach = Double(max(width, height)) * 1.5
        let steps = Int(reach * 3)
        for step in 0...steps {
            let t = (Double(step) / Double(steps) - 0.5) * reach
            let x = cx + cos(radians) * t
            let y = cy - sin(radians) * t
            for dx in -1...1 {
                for dy in -1...1 {
                    let px = Int(x.rounded()) + dx
                    let py = Int(y.rounded()) + dy
                    guard px >= 0, px < width, py >= 0, py < height else { continue }
                    pixels[py * width + px] = 0.95
                }
            }
        }
    }

    @Test func aFlatFrameHasNoLines() {
        let pixels = [Float](repeating: 0.5, count: 64 * 64)
        #expect(UprightAnalyzer.segments(luminance: pixels, width: 64, height: 64).isEmpty)
    }

    @Test func detectionRefusesMalformedBuffers() {
        #expect(UprightAnalyzer.segments(luminance: [0, 1], width: 256, height: 192).isEmpty)
        #expect(UprightAnalyzer.segments(luminance: [], width: 0, height: 0).isEmpty)
    }

    @Test func weightedMedianSitsWhereHalfTheEvidenceIs() {
        let values: [(value: Double, weight: Double)] = [
            (1, 1), (2, 1), (10, 10),
        ]
        #expect(UprightAnalyzer.weightedMedian(values) == 10)
        #expect(UprightAnalyzer.weightedMedian([]) == nil)
        #expect(UprightAnalyzer.weightedMedian([(5, 0)]) == nil)
    }
}
