import Foundation
import Testing
@testable import ShotDex

struct VideoTransportMathTests {

    // MARK: seekTarget

    @Test func seekForwardInsideClip() {
        #expect(VideoTransportMath.seekTarget(current: 5, duration: 60, delta: 10) == 15)
    }

    @Test func seekBackwardClampsToStart() {
        #expect(VideoTransportMath.seekTarget(current: 4, duration: 60, delta: -10) == 0)
    }

    @Test func seekForwardClampsToDuration() {
        #expect(VideoTransportMath.seekTarget(current: 58, duration: 60, delta: 10) == 60)
    }

    /// iCloud items report `indefinite` duration until AVFoundation resolves
    /// them; only the lower bound can be enforced until then.
    @Test func seekWithUnresolvedDurationKeepsTargetButNeverGoesNegative() {
        #expect(VideoTransportMath.seekTarget(current: 5, duration: .nan, delta: 10) == 15)
        #expect(VideoTransportMath.seekTarget(current: 5, duration: 0, delta: 10) == 15)
        #expect(VideoTransportMath.seekTarget(current: 5, duration: .nan, delta: -10) == 0)
    }

    @Test func seekFromNonFiniteCurrentStartsAtZero() {
        #expect(VideoTransportMath.seekTarget(current: .nan, duration: 60, delta: 10) == 10)
    }

    // MARK: frameStepTarget

    @Test func frameStepForwardUsesTrackFrameRate() {
        let target = VideoTransportMath.frameStepTarget(
            current: 1,
            frameRate: 50,
            direction: 1,
            duration: 60
        )
        #expect(abs(target - 1.02) < 0.0001)
    }

    @Test func frameStepHandlesFractionalRates() {
        let ntsc = VideoTransportMath.frameStepTarget(
            current: 0,
            frameRate: 23.976,
            direction: 1,
            duration: 60
        )
        #expect(abs(ntsc - 1 / 23.976) < 0.000001)

        let fast = VideoTransportMath.frameStepTarget(
            current: 0,
            frameRate: 59.94,
            direction: 1,
            duration: 60
        )
        #expect(abs(fast - 1 / 59.94) < 0.000001)
    }

    @Test func frameStepFallsBackWhenTrackHasNoRate() {
        let target = VideoTransportMath.frameStepTarget(
            current: 0,
            frameRate: 0,
            direction: 1,
            duration: 60
        )
        #expect(abs(target - 1 / VideoTransportMath.fallbackFrameRate) < 0.000001)
    }

    @Test func frameStepBackAtStartStaysAtZero() {
        let target = VideoTransportMath.frameStepTarget(
            current: 0,
            frameRate: 30,
            direction: -1,
            duration: 60
        )
        #expect(target == 0)
    }

    @Test func frameStepForwardAtEndStaysAtDuration() {
        let target = VideoTransportMath.frameStepTarget(
            current: 60,
            frameRate: 30,
            direction: 1,
            duration: 60
        )
        #expect(target == 60)
    }

    // MARK: timelineUpperBound

    @Test func timelineUpperBoundUsesDurationOnceResolved() {
        #expect(VideoTransportMath.timelineUpperBound(duration: 42, current: 3, scrub: 0) == 42)
    }

    /// Playback can lead an unresolved duration; the bound must follow the
    /// value, otherwise `Slider` gets a value outside its range.
    @Test func timelineUpperBoundFollowsCurrentTimeWhenDurationUnknown() {
        #expect(VideoTransportMath.timelineUpperBound(duration: .nan, current: 7, scrub: 0) == 7)
        #expect(VideoTransportMath.timelineUpperBound(duration: 0, current: 0, scrub: 9) == 9)
    }

    @Test func timelineUpperBoundNeverCollapsesToZero() {
        #expect(VideoTransportMath.timelineUpperBound(duration: 0, current: 0, scrub: 0) == 0.1)
        #expect(
            VideoTransportMath.timelineUpperBound(
                duration: .infinity,
                current: .nan,
                scrub: .nan
            ) == 0.1
        )
    }

    // MARK: remainingSeconds

    @Test func remainingSeconds() {
        #expect(VideoTransportMath.remainingSeconds(current: 10, duration: 60) == 50)
        #expect(VideoTransportMath.remainingSeconds(current: 61, duration: 60) == 0)
        #expect(VideoTransportMath.remainingSeconds(current: 0, duration: .nan) == nil)
        #expect(VideoTransportMath.remainingSeconds(current: 0, duration: 0) == nil)
    }

    // MARK: frameFilename

    @Test func frameFilenameDropsOriginalExtension() {
        let name = VideoTransportMath.frameFilename(
            base: "IMG_4021.MOV",
            seconds: 7.5,
            frameRate: 30,
            fileExtension: "heic"
        )
        #expect(name == "IMG_4021-00-07-15.heic")
    }

    @Test func frameFilenameIncludesMinutes() {
        let name = VideoTransportMath.frameFilename(
            base: "clip",
            seconds: 132.0,
            frameRate: 30,
            fileExtension: "jpg"
        )
        #expect(name == "clip-02-12-00.jpg")
    }

    @Test func frameFilenameFallsBackWithoutOriginalName() {
        #expect(
            VideoTransportMath.frameFilename(
                base: nil,
                seconds: 0,
                frameRate: 30,
                fileExtension: "heic"
            ) == "Frame-00-00-00.heic"
        )
        #expect(
            VideoTransportMath.frameFilename(
                base: "",
                seconds: 0,
                frameRate: 30,
                fileExtension: "heic"
            ) == "Frame-00-00-00.heic"
        )
    }

    /// A time a hair under the next second must not report frame 30 of a 30 fps
    /// clip — frame numbering inside a second is 0…rate-1.
    @Test func frameFilenameClampsFrameIndexAtSecondBoundary() {
        let name = VideoTransportMath.frameFilename(
            base: "IMG_1.MOV",
            seconds: 1.9999,
            frameRate: 30,
            fileExtension: "heic"
        )
        #expect(name == "IMG_1-00-01-29.heic")
    }

    @Test func frameFilenameHandlesNonFiniteInputs() {
        let name = VideoTransportMath.frameFilename(
            base: "IMG_1.MOV",
            seconds: .nan,
            frameRate: 0,
            fileExtension: "heic"
        )
        #expect(name == "IMG_1-00-00-00.heic")
    }
}
