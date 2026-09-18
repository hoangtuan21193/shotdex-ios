import Foundation
import Testing
@testable import ShotDex

struct VideoTrimMathTests {

    @Test func handlesStayInsideTheClip() {
        let result = VideoTrimMath.clamped(start: -5, end: 99, duration: 10, movingStart: true)
        #expect(result.start == 0)
        #expect(result.end == 10)
    }

    /// Dragging the start into the end pushes the end along rather than
    /// inverting the range.
    @Test func startPushesEndAhead() {
        let result = VideoTrimMath.clamped(start: 9.9, end: 10, duration: 10, movingStart: true)
        #expect(result.start < result.end)
        #expect(result.end - result.start >= VideoTrimMath.minimumDuration - 0.0001)
    }

    @Test func endPushesStartBack() {
        let result = VideoTrimMath.clamped(start: 0, end: 0.1, duration: 10, movingStart: false)
        #expect(result.start == 0)
        #expect(result.end >= VideoTrimMath.minimumDuration)
    }

    /// A start handle can never be dragged so far right that no room is left
    /// for the minimum clip.
    @Test func startCannotReachTheVeryEnd() {
        let result = VideoTrimMath.clamped(start: 10, end: 10, duration: 10, movingStart: true)
        #expect(result.start <= 10 - VideoTrimMath.minimumDuration + 0.0001)
        #expect(result.end == 10)
    }

    /// A clip already shorter than the minimum is left whole — there is
    /// nothing to trim, and clamping it would produce a negative range.
    @Test func veryShortClipIsLeftWhole() {
        let result = VideoTrimMath.clamped(start: 0.1, end: 0.2, duration: 0.2, movingStart: true)
        #expect(result.start == 0)
        #expect(result.end == 0.2)
    }

    @Test func untouchedRangeIsNotATrim() {
        #expect(!VideoTrimMath.isTrimmed(start: 0, end: 10, duration: 10))
        #expect(VideoTrimMath.isTrimmed(start: 1, end: 10, duration: 10))
        #expect(VideoTrimMath.isTrimmed(start: 0, end: 9, duration: 10))
    }

    @Test func thumbnailTimesSpanTheClip() {
        let times = VideoTrimMath.thumbnailTimes(count: 5, duration: 10)
        #expect(times.count == 5)
        #expect(times.first == 0)
        // The last frame stops just short of the end: a generator asked for the
        // final timestamp of a clip often has nothing to give.
        #expect(times.last! < 10)
        #expect(times.last! > 9)
        #expect(times == times.sorted())
    }

    @Test func thumbnailTimesSurviveAZeroLengthClip() {
        #expect(VideoTrimMath.thumbnailTimes(count: 5, duration: 0) == [0])
        #expect(VideoTrimMath.thumbnailTimes(count: 1, duration: 10) == [0])
    }
}
