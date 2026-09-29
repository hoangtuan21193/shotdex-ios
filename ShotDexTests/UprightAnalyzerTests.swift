import CoreGraphics
import CoreImage
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
        // The whole frame tilted 4°, its sides converging 8° each way. (Until
        // 2026-09-29 the sides were left untilted, which only worked because
        // Level read their convergence as tilt; with it taken out they say
        // the frame is level and outvote the one horizon.)
        let segments = [
            segment(degrees: 4),
            segment(degrees: 82 + 4, midX: 0.15),
            segment(degrees: -82 + 4, midX: 0.85),
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

    /// FS-03.15b AC-23. A building whose edges converge 8° in all, the
    /// whole frame tilted 2°: Auto levels it to within 0.5° and straightens
    /// 60% of the convergence, leaving 3°…4°.
    @Test func autoLevelsAndPartlyStraightens() {
        let tilt = 2.0
        let segments = [
            segment(degrees: tilt),
            segment(degrees: tilt, midX: 0.3),
            segment(degrees: tilt, midX: 0.7),
            // Converging tops: the left edge leans right 4°, the right edge
            // left 4°, then the frame's tilt on both.
            segment(degrees: 86 + tilt, midX: 0.15),
            segment(degrees: -86 + tilt, midX: 0.85),
        ]
        let auto = UprightAnalyzer.suggestion(from: segments, mode: .auto)

        let levelled = tilt + auto.rotate * 0.35 * 180 / .pi
        #expect(abs(levelled) <= 0.5, "tilt left \(levelled)°")

        // What is left is read off the transform itself — the two edges
        // followed through `GeoForwardMap` on a square frame, the space these
        // segments are written in — not off a degrees-per-unit constant: the
        // old 26° one was never measured against a keystone that moved pixels.
        let left = Self.convergence(of: [segments[3], segments[4]], after: auto.transform(for: .auto))
        #expect(left >= 3 && left <= 4, "convergence left \(left)°")
        let fullLeft = Self.convergence(of: [segments[3], segments[4]], after: UprightAnalyzer
            .suggestion(from: segments, mode: .full).transform(for: .full))
        #expect(abs(fullLeft) <= 0.3, "Full leaves \(fullLeft)°")

        let full = UprightAnalyzer.suggestion(from: segments, mode: .full)
        #expect(abs(full.vertical * 0.6 - auto.vertical) < 1e-9, "Auto is 60% of Full's keystone")
        #expect(PhotoUprightMode(UprightMode.auto) == .auto)
    }

    /// Degrees the left edge leans right plus the right edge leans left —
    /// the total convergence of `edges` — once `transform` has moved them on
    /// a square frame.
    private static func convergence(of edges: [UprightSegment], after transform: PhotoUprightTransform) -> Double {
        let extent = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let map = GeoForwardMap(adjustments: .zero, upright: transform, extent: extent)
        let leans = edges.map { edge -> Double in
            var a = map.apply(CGPoint(x: edge.start.x * 1000, y: edge.start.y * 1000))
            var b = map.apply(CGPoint(x: edge.end.x * 1000, y: edge.end.y * 1000))
            if b.y < a.y { swap(&a, &b) }
            return atan2(Double(b.x - a.x), Double(b.y - a.y)) * 180 / .pi
        }
        return leans[0] - leans[1]
    }

    /// Vision's horizon, when it has one, sets the rotation in place of the
    /// lines' own reading.
    @Test func aVisionHorizonOverridesTheLines() {
        let segments = [segment(degrees: 5)]
        let fromVision = UprightAnalyzer.suggestion(from: segments, mode: .level, horizonTilt: 2 * .pi / 180)
        #expect(abs(fromVision.rotate - (-(2 * Double.pi / 180) / 0.35)) < 1e-9)
    }

    @Test func aModeKeepsOnlyTheCorrectionItMakes() {
        let level = UprightSuggestion(rotate: 0.3, vertical: 0.2).transform(for: .level)
        #expect(level.rotate == 0.3)
        #expect(level.vertical == 0, "Level must not touch the keystone")

        let vertical = UprightSuggestion(rotate: 0.5, vertical: 0.2).transform(for: .vertical)
        #expect(vertical.rotate == 0, "Vertical must not touch the rotation")
        #expect(vertical.vertical == 0.2)
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

    // MARK: Keystone on pixels

    /// A 1200×800 building on a textured ground: six edges through one
    /// vanishing point above the centre — the pair crossing mid-height at
    /// x = 0.15 and 0.85 leans `lean`° each way — plus four window sills,
    /// the lot turned by `tilt`°. Returns the frame and the drawn edges in
    /// its pixels, left to right, so the result can be checked against the
    /// drawing and not only against the detector that made the suggestion.
    private static func drawnBuilding(lean: Double, tilt: Double) -> (image: CIImage, edges: [(CGPoint, CGPoint)]) {
        let width = 1200, height = 800
        let w = Double(width), h = Double(height)
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Blotches and grain, so the gradient threshold sees texture the way
        // it does in a photo. A fixed-seed generator keeps it repeatable.
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func random() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let fx = Double(x) / w, fy = Double(y) / h
                let value = 0.42 + 0.05 * sin(fx * 13 + 1) * cos(fy * 9 + 2) + 0.04 * sin(fx * 31 + fy * 17)
                    + 0.03 * cos(fx * 57 - fy * 43) + (random() - 0.5) * 0.1
                let byte = UInt8(max(0, min(255, value * 255)))
                let index = (y * width + x) * 4
                pixels[index] = byte
                pixels[index + 1] = byte
                pixels[index + 2] = byte
                pixels[index + 3] = 255
            }
        }
        let turn = tilt * .pi / 180
        func turned(_ p: CGPoint) -> CGPoint {
            let dx = Double(p.x) - w / 2, dy = Double(p.y) - h / 2
            return CGPoint(x: w / 2 + dx * cos(turn) - dy * sin(turn), y: h / 2 + dx * sin(turn) + dy * cos(turn))
        }
        context.setStrokeColor(CGColor(gray: 0.12, alpha: 1))
        context.setLineWidth(4)
        for row in [0.2, 0.4, 0.6, 0.8] {
            context.move(to: turned(CGPoint(x: -0.2 * w, y: row * h)))
            context.addLine(to: turned(CGPoint(x: 1.2 * w, y: row * h)))
            context.strokePath()
        }
        let vanishing = CGPoint(x: w / 2, y: h / 2 + 0.35 * w / tan(lean * .pi / 180))
        var edges: [(CGPoint, CGPoint)] = []
        context.setStrokeColor(CGColor(gray: 0.92, alpha: 1))
        context.setLineWidth(6)
        for midX in [0.06, 0.15, 0.26, 0.74, 0.85, 0.94] {
            let mid = CGPoint(x: midX * w, y: h / 2)
            let dx = Double(vanishing.x - mid.x), dy = Double(vanishing.y - mid.y)
            let reach = 0.75 * h / (dx * dx + dy * dy).squareRoot()
            let foot = turned(CGPoint(x: Double(mid.x) - dx * reach, y: Double(mid.y) - dy * reach))
            let top = turned(CGPoint(x: Double(mid.x) + dx * reach, y: Double(mid.y) + dy * reach))
            context.move(to: foot)
            context.addLine(to: top)
            context.strokePath()
            edges.append((foot, top))
        }
        return (CIImage(cgImage: context.makeImage()!), edges)
    }

    /// Degrees a drawn edge leans right at the top once `transform` has
    /// moved it on a 1200×800 frame.
    private static func lean(of edge: (CGPoint, CGPoint), after transform: PhotoUprightTransform) -> Double {
        let map = GeoForwardMap(adjustments: .zero, upright: transform, extent: CGRect(x: 0, y: 0, width: 1200, height: 800))
        let a = map.apply(edge.0), b = map.apply(edge.1)
        return atan2(Double(b.x - a.x), Double(b.y - a.y)) * 180 / .pi
    }

    /// FS-03.15b AC-23 on pixels. A drawn building is analysed, the
    /// suggestion is rendered through `applyGeo`, and the lines are found
    /// again: Full leaves no convergence and Auto 40% of it, both by the
    /// analyzer's own reading of the output and by the drawn edges followed
    /// through the transform; both level the frame to within 0.5°.
    ///
    /// Until 2026-09-29 the keystone read convergence as an angle over "26°
    /// per unit" that nothing had measured — the perspective filter it
    /// fed had never moved a pixel (FS-03.15b AC-29). On this frame Full
    /// straightened 19–34% of the convergence, and Level turned an upright
    /// frame by up to 1.5° because it read the converging edges as tilt.
    @Test(arguments: [(lean: 4.0, tilt: 2.0), (lean: 6.0, tilt: 0.0), (lean: 2.0, tilt: 0.0)])
    func theKeystoneStraightensADrawnBuilding(lean: Double, tilt: Double) throws {
        let context = CIContext()
        let (image, edges) = Self.drawnBuilding(lean: lean, tilt: tilt)
        let before = try #require(UprightAnalyzer.keystoneSpread(from: UprightAnalyzer.segments(in: image, context: context)))
        #expect(before > 0, "tops leaning in read as a positive spread")

        for (mode, share) in [(UprightMode.full, 0.0), (.auto, 0.4)] {
            let suggestion = try #require(UprightAnalyzer.analyze(image, mode: mode, context: context))
            let transform = suggestion.transform(for: mode)
            #expect(transform.vertical > 0, "\(mode): the tops are spread, not pulled in")
            let output = PhotoRenderService.applyGeo(.zero, upright: transform, to: image)
            let after = try #require(UprightAnalyzer.keystoneSpread(from: UprightAnalyzer.segments(in: output, context: context)))
            #expect(abs(after / before - share) <= 0.06,
                    "\(mode) left \(after / before) of the convergence re-detected (\(after) of \(before))")

            let left = Self.lean(of: edges[1], after: transform)
            let right = Self.lean(of: edges[4], after: transform)
            let convergence = (left - right) / 2
            #expect(abs(convergence - share * lean) <= 0.06 * lean,
                    "\(mode) left \(convergence)° a side of the drawn \(lean)°")
            #expect(abs((left + right) / 2) <= 0.5, "\(mode) left the frame tilted \((left + right) / 2)°")
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
