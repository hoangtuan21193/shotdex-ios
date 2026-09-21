import CoreGraphics
import Foundation
import Testing
@testable import ShotDex
@testable import ShotDexKit

/// The arithmetic a window track lives or dies by.
///
/// Every failure mode here looks like "the tracker is bad" on screen and is
/// actually a sign or an axis: a window that runs away from the subject, one
/// that moves the wrong way vertically, one that snaps home the frame after
/// the track ends.
struct MaskTrackMathTests {
    private func radial(center: (Double, Double), radius: Double) -> PhotoMask {
        var component = PhotoMaskComponent(kind: .radialGradient)
        component.center = NormalizedPoint(x: center.0, y: center.1)
        component.radiusX = radius
        component.radiusY = radius
        return PhotoMask(name: "Window", component: component)
    }

    // MARK: Which windows can be followed

    @Test func onlyWindowsWithAPlaceCanBeTracked() {
        #expect(MaskTrackMath.isTrackable(.radialGradient))
        #expect(MaskTrackMath.isTrackable(.linearGradient))
        // A qualifier selects by value, everywhere at once.
        #expect(!MaskTrackMath.isTrackable(.luminanceRange))
        #expect(!MaskTrackMath.isTrackable(.colorRange))
    }

    // MARK: Interpolation

    @Test func aTrackHoldsItsEndsRatherThanSnappingHome() {
        let track = MaskTrack(maskID: UUID(), keyframes: [
            MaskKeyframe(time: 1, offsetX: 0.1, scale: 1),
            MaskKeyframe(time: 2, offsetX: 0.3, scale: 1.5),
        ])
        // Before the track and after it, the window stays where the track
        // left it — a window that jumps back on the next frame reads as a
        // glitch, not as "the track ended".
        #expect(track.keyframe(at: 0).offsetX == 0.1)
        #expect(track.keyframe(at: 99).offsetX == 0.3)
        #expect(track.keyframe(at: 99).scale == 1.5)
    }

    @Test func aTimeBetweenSamplesIsInterpolated() {
        let track = MaskTrack(maskID: UUID(), keyframes: [
            MaskKeyframe(time: 0, offsetX: 0, offsetY: 0, scale: 1),
            MaskKeyframe(time: 2, offsetX: 0.4, offsetY: -0.2, scale: 2),
        ])
        let mid = track.keyframe(at: 1)
        #expect(abs(mid.offsetX - 0.2) < 0.0001)
        #expect(abs(mid.offsetY + 0.1) < 0.0001)
        #expect(abs(mid.scale - 1.5) < 0.0001)
    }

    /// The search has to find the right pair in a track with hundreds of
    /// samples, not just in a two-sample one.
    @Test func theRightPairIsFoundInALongTrack() {
        let keyframes = (0..<240).map {
            MaskKeyframe(time: Double($0) / 12, offsetX: Double($0) / 240)
        }
        let track = MaskTrack(maskID: UUID(), keyframes: keyframes)
        let sample = track.keyframe(at: 10)
        #expect(abs(sample.offsetX - 0.5) < 0.01)
    }

    @Test func anEmptyTrackIsIdentity() {
        let track = MaskTrack(maskID: UUID(), keyframes: [])
        #expect(track.keyframe(at: 5) == .identity)
        #expect(track.timeRange == nil)
    }

    // MARK: Moving the window

    @Test func aRadialWindowFollowsOffsetAndSize() {
        let mask = radial(center: (0.5, 0.5), radius: 0.2)
        let moved = MaskTrackMath.tracked(
            mask, by: MaskKeyframe(time: 0, offsetX: 0.1, offsetY: -0.2, scale: 1.5)
        )
        let component = moved.components[0]
        #expect(abs(component.center.x - 0.6) < 0.0001)
        #expect(abs(component.center.y - 0.3) < 0.0001)
        #expect(abs(component.radiusX - 0.3) < 0.0001)
        #expect(abs(component.radiusY - 0.3) < 0.0001)
    }

    /// A linear window has no centre, so it scales about the midpoint of its
    /// handles — the only point on it that means anything.
    @Test func aLinearWindowScalesAboutItsMidpoint() {
        var component = PhotoMaskComponent(kind: .linearGradient)
        component.startPoint = NormalizedPoint(x: 0.5, y: 0.2)
        component.endPoint = NormalizedPoint(x: 0.5, y: 0.6)
        let mask = PhotoMask(name: "Sky", component: component)

        let moved = MaskTrackMath.tracked(mask, by: MaskKeyframe(time: 0, scale: 2))
        // Midpoint 0.4, so the handles move to 0.0 and 0.8 and the midpoint
        // stays put.
        #expect(abs(moved.components[0].startPoint.y - 0.0) < 0.0001)
        #expect(abs(moved.components[0].endPoint.y - 0.8) < 0.0001)
    }

    /// A window never shrinks to a point: a zero radius grades one pixel and
    /// looks like the window vanished.
    @Test func aWindowKeepsSomeSize() {
        let mask = radial(center: (0.5, 0.5), radius: 0.2)
        let moved = MaskTrackMath.tracked(mask, by: MaskKeyframe(time: 0, scale: 0))
        #expect(moved.components[0].radiusX > 0)
        #expect(moved.components[0].radiusY > 0)
    }

    // MARK: Vision's coordinates

    /// Vision's y runs from the bottom, the window's from the top. Getting
    /// this backwards sends the window the wrong way and looks exactly like
    /// a tracker that failed.
    @Test func aSubjectRisingOnScreenMovesTheWindowUp() {
        let start = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        // Vision box moved UP the screen = larger y in Vision's frame.
        let higher = CGRect(x: 0.4, y: 0.6, width: 0.2, height: 0.2)
        let keyframe = VideoMaskTracker.keyframe(from: start, to: higher, at: 1)
        // Top-left coordinates: up the screen is a SMALLER y, so the offset
        // is negative.
        #expect(keyframe.offsetY < 0)
        #expect(abs(keyframe.offsetX) < 0.0001)
    }

    @Test func aSubjectGrowingGivesAScaleAboveOne() {
        let start = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        let bigger = CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3)
        let keyframe = VideoMaskTracker.keyframe(from: start, to: bigger, at: 1)
        #expect(keyframe.scale > 1.4 && keyframe.scale < 1.6)
    }

    /// Vision rejects a seed box that leaves the unit square, so a window
    /// half off frame has to be clamped into it rather than refused.
    @Test func aSeedBoxIsAlwaysInsideTheUnitSquare() {
        var component = PhotoMaskComponent(kind: .radialGradient)
        component.center = NormalizedPoint(x: 0.05, y: 0.95)
        component.radiusX = 0.4
        component.radiusY = 0.4
        let rect = VideoMaskTracker.visionRect(for: component, renderSize: CGSize(width: 1920, height: 1080))
        #expect(rect.minX >= 0)
        #expect(rect.minY >= 0)
        #expect(rect.maxX <= 1.0001)
        #expect(rect.maxY <= 1.0001)
        #expect(rect.width > 0)
        #expect(rect.height > 0)
    }
}
