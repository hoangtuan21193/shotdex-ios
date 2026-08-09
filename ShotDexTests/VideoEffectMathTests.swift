import CoreGraphics
import Foundation
import Testing
@testable import ShotDex

struct VideoEffectMathTests {
    private let canvas = CGSize(width: 1920, height: 1080)

    private func isClose(_ a: Double, _ b: Double, tolerance: Double = 1e-9) -> Bool {
        abs(a - b) <= tolerance
    }

    private func transform(
        _ effect: VideoClipEffect,
        progress: Double,
        time: Double = 0,
        clipStart: Double = 0,
        clipDuration: Double = 5,
        clipIndex: Int = 0
    ) -> CGAffineTransform {
        VideoEffectMath.effectTransform(
            effect: effect,
            progress: progress,
            time: time,
            clipStart: clipStart,
            clipDuration: clipDuration,
            clipIndex: clipIndex,
            renderSize: canvas
        )
    }

    // MARK: - Easing & progress

    @Test func easedIsASmoothstep() {
        #expect(VideoEffectMath.eased(0) == 0)
        #expect(VideoEffectMath.eased(0.5) == 0.5)
        #expect(VideoEffectMath.eased(1) == 1)
        #expect(VideoEffectMath.eased(-2) == 0)
        #expect(VideoEffectMath.eased(3) == 1)
        // Monotone rising.
        #expect(VideoEffectMath.eased(0.3) < VideoEffectMath.eased(0.6))
    }

    @Test func clipProgressClampsToTheClipWindow() {
        #expect(VideoEffectMath.clipProgress(time: 2, clipStart: 2, clipDuration: 4) == 0)
        #expect(VideoEffectMath.clipProgress(time: 4, clipStart: 2, clipDuration: 4) == 0.5)
        #expect(VideoEffectMath.clipProgress(time: 9, clipStart: 2, clipDuration: 4) == 1)
        #expect(VideoEffectMath.clipProgress(time: 0, clipStart: 2, clipDuration: 4) == 0)
        #expect(VideoEffectMath.clipProgress(time: 1, clipStart: 0, clipDuration: 0) == 1)
    }

    // MARK: - Zoom effects

    @Test func zoomInScalesFrom1To1_12AboutTheCanvasCentre() {
        let start = transform(.zoomIn, progress: 0)
        #expect(start.isIdentity)

        let end = transform(.zoomIn, progress: 1)
        #expect(isClose(end.a, 1.12))
        #expect(isClose(end.d, 1.12))
        // The canvas centre is a fixed point.
        let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let mapped = center.applying(end)
        #expect(isClose(mapped.x, center.x, tolerance: 1e-6))
        #expect(isClose(mapped.y, center.y, tolerance: 1e-6))
    }

    @Test func zoomOutIsTheReverseRamp() {
        let start = transform(.zoomOut, progress: 0)
        #expect(isClose(start.a, 1.12))
        let end = transform(.zoomOut, progress: 1)
        #expect(end.isIdentity)
    }

    // MARK: - Pan effects

    @Test func panTravelStaysInsideThePreScaleMargin() {
        // Pre-scale 1.06 leaves 3% of width margin per side; the pan travels
        // at most 2%, so a full-bleed source never exposes a gap.
        let margin = (VideoEffectMath.panPreScale - 1) / 2 * canvas.width
        for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
            for effect in [VideoClipEffect.panLeft, .panRight] {
                let t = transform(effect, progress: progress)
                #expect(isClose(t.a, VideoEffectMath.panPreScale))
                let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                let drift = center.applying(t).x - center.x
                #expect(abs(drift) <= margin + 1e-6)
            }
        }
    }

    @Test func panLeftAndRightMirror() {
        let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let left = center.applying(transform(.panLeft, progress: 1)).x - center.x
        let right = center.applying(transform(.panRight, progress: 1)).x - center.x
        #expect(isClose(left, -right, tolerance: 1e-6))
        #expect(isClose(abs(left), VideoEffectMath.panTravel * canvas.width, tolerance: 1e-6))
    }

    // MARK: - Shake

    @Test func shakeIsDeterministicPerFrameAndClip() {
        func offset(_ time: Double, clipIndex: Int) -> CGVector {
            VideoEffectMath.shakeOffset(
                time: time, clipStart: 0, clipDuration: 10,
                clipIndex: clipIndex, renderSize: canvas
            )
        }
        // Same frame (1/30s buckets) → identical vector.
        let a = offset(0.501, clipIndex: 0)
        let b = offset(0.510, clipIndex: 0)
        #expect(a == b)
        // Different clip → different vector.
        let other = offset(0.501, clipIndex: 1)
        #expect(a != other)
        // Bounded by the amplitude.
        let bound = VideoEffectMath.shakeAmplitude * Double(min(canvas.width, canvas.height))
        #expect(abs(a.dx) <= bound && abs(a.dy) <= bound)
    }

    @Test func shakeAmplitudeWindowsToZeroAtClipEdges() {
        let atStart = VideoEffectMath.shakeOffset(
            time: 5, clipStart: 5, clipDuration: 4, clipIndex: 0, renderSize: canvas
        )
        #expect(atStart == .zero)
        let atEnd = VideoEffectMath.shakeOffset(
            time: 9, clipStart: 5, clipDuration: 4, clipIndex: 0, renderSize: canvas
        )
        #expect(atEnd == .zero)
    }

    // MARK: - Blur ramps

    @Test func blurInRampReachesZeroAfterTheRampWindow() {
        func radius(_ time: Double) -> Double {
            VideoEffectMath.effectBlurRadius(
                effect: .blurIn, time: time, clipStart: 0, clipDuration: 5, renderSize: canvas
            )
        }
        #expect(isClose(radius(0), VideoEffectMath.blurBaseRadius))
        #expect(isClose(radius(0.4), VideoEffectMath.blurBaseRadius / 2))
        #expect(radius(0.8) == 0)
        #expect(radius(3) == 0)
    }

    @Test func blurOutRampMirrorsAtTheTail() {
        func radius(_ time: Double) -> Double {
            VideoEffectMath.effectBlurRadius(
                effect: .blurOut, time: time, clipStart: 0, clipDuration: 5, renderSize: canvas
            )
        }
        #expect(radius(0) == 0)
        #expect(radius(4.2) <= 1e-9)   // ramp boundary: float epsilon, not exact 0
        #expect(isClose(radius(4.6), VideoEffectMath.blurBaseRadius / 2))
        #expect(isClose(radius(5), VideoEffectMath.blurBaseRadius))
    }

    @Test func shortClipShrinksTheBlurWindow() {
        let radius = VideoEffectMath.effectBlurRadius(
            effect: .blurIn, time: 0.25, clipStart: 0, clipDuration: 0.5, renderSize: canvas
        )
        #expect(isClose(radius, VideoEffectMath.blurBaseRadius / 2))
    }

    @Test func radiiScaleWithTheRenderShortEdge() {
        let uhd = CGSize(width: 3840, height: 2160)
        let hdRadius = VideoEffectMath.effectBlurRadius(
            effect: .blurIn, time: 0, clipStart: 0, clipDuration: 5, renderSize: canvas
        )
        let uhdRadius = VideoEffectMath.effectBlurRadius(
            effect: .blurIn, time: 0, clipStart: 0, clipDuration: 5, renderSize: uhd
        )
        #expect(isClose(uhdRadius, hdRadius * 2))
        #expect(isClose(VideoEffectMath.glowRadius(renderSize: uhd),
                        VideoEffectMath.glowRadius(renderSize: canvas) * 2))
    }

    @Test func nonBlurEffectsHaveZeroRadius() {
        for effect in VideoClipEffect.allCases where effect != .blurIn && effect != .blurOut {
            let radius = VideoEffectMath.effectBlurRadius(
                effect: effect, time: 0, clipStart: 0, clipDuration: 5, renderSize: canvas
            )
            #expect(radius == 0, "\(effect.rawValue)")
        }
    }

    // MARK: - Vignette pulse

    @Test func vignettePulseHasAFourSecondPeriodAndStartsAtTheTrough() {
        #expect(isClose(VideoEffectMath.vignettePulseIntensity(localTime: 0), 0.2))
        #expect(isClose(VideoEffectMath.vignettePulseIntensity(localTime: 2), 0.8))
        #expect(isClose(
            VideoEffectMath.vignettePulseIntensity(localTime: 1.3),
            VideoEffectMath.vignettePulseIntensity(localTime: 5.3)
        ))
        for t in stride(from: 0.0, through: 8, by: 0.25) {
            let value = VideoEffectMath.vignettePulseIntensity(localTime: t)
            #expect(value >= 0.2 - 1e-9 && value <= 0.8 + 1e-9)
        }
    }

    // MARK: - Identity for non-geometric effects

    @Test func effectTransformIsIdentityForNonGeometricEffects() {
        for effect in [VideoClipEffect.none, .blurIn, .blurOut, .softGlow, .vignettePulse] {
            #expect(transform(effect, progress: 0.5, time: 2.5).isIdentity, "\(effect.rawValue)")
        }
    }

    // MARK: - Slide transition

    @Test func slideOffsetsMoveBothImagesAFullWidth() {
        let width = Double(canvas.width)

        let startLeft = VideoEffectMath.slideOffsets(kind: .slideLeft, progress: 0, renderSize: canvas)
        #expect(isClose(startLeft.front.dx, width))   // incoming waits offscreen right
        #expect(startLeft.back.dx == 0)
        let endLeft = VideoEffectMath.slideOffsets(kind: .slideLeft, progress: 1, renderSize: canvas)
        #expect(endLeft.front.dx == 0)
        #expect(isClose(endLeft.back.dx, -width))     // outgoing exits left

        let startRight = VideoEffectMath.slideOffsets(kind: .slideRight, progress: 0, renderSize: canvas)
        #expect(isClose(startRight.front.dx, -width))
        let endRight = VideoEffectMath.slideOffsets(kind: .slideRight, progress: 1, renderSize: canvas)
        #expect(endRight.front.dx == 0)
        #expect(isClose(endRight.back.dx, width))
    }

    // MARK: - Zoom transition

    @Test func zoomTransitionScaleRampsTo1_3() {
        #expect(VideoEffectMath.zoomTransitionScale(progress: 0) == 1)
        #expect(isClose(VideoEffectMath.zoomTransitionScale(progress: 1), 1.3))
        #expect(VideoEffectMath.zoomTransitionScale(progress: 0.3)
            < VideoEffectMath.zoomTransitionScale(progress: 0.7))
    }

    // MARK: - Wipe transition

    @Test func wipeEdgeSweepsBeyondBothEdgesBySoftness() {
        let width = 1920.0
        let soft = VideoEffectMath.wipeSoftness * width

        let start = VideoEffectMath.wipeGradientX(progress: 0, width: width)
        #expect(start.blackX <= 0 + 1e-9)             // no incoming frame visible yet
        #expect(isClose(start.blackX - start.whiteX, 2 * soft))

        let end = VideoEffectMath.wipeGradientX(progress: 1, width: width)
        #expect(end.whiteX >= width - 1e-9)           // incoming frame fully revealed

        // Monotone sweep.
        var previous = start.whiteX
        for p in stride(from: 0.1, through: 1.0, by: 0.1) {
            let x = VideoEffectMath.wipeGradientX(progress: p, width: width).whiteX
            #expect(x >= previous - 1e-9)
            previous = x
        }
    }

    // MARK: - Fade to black

    @Test func fadeBlackStageSplitsAtHalf() {
        let quarter = VideoEffectMath.fadeBlackStage(progress: 0.25)
        #expect(quarter.stage == .out)
        #expect(isClose(quarter.t, 0.5))

        let threeQuarters = VideoEffectMath.fadeBlackStage(progress: 0.75)
        #expect(threeQuarters.stage == .in)
        #expect(isClose(threeQuarters.t, 0.5))

        let boundary = VideoEffectMath.fadeBlackStage(progress: 0.5)
        #expect(boundary.stage == .in)
        #expect(boundary.t == 0)

        #expect(VideoEffectMath.fadeBlackStage(progress: 0).t == 0)
        #expect(VideoEffectMath.fadeBlackStage(progress: 1).t == 1)
    }
}
