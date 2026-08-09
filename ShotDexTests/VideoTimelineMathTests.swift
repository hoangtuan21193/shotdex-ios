import Foundation
import Testing
@testable import ShotDex

struct VideoTimelineMathTests {
    private func isClose(_ a: Double, _ b: Double, tolerance: Double = 1e-9) -> Bool {
        abs(a - b) <= tolerance
    }

    // MARK: - Placements

    @Test func placementsWithoutOverlapsAreContiguous() {
        let placements = VideoTimelineMath.placements(durations: [3, 5, 2], overlaps: [0, 0])
        #expect(placements.map(\.start) == [0, 3, 8])
        #expect(isClose(VideoTimelineMath.totalDuration(durations: [3, 5, 2], overlaps: [0, 0]), 10))
    }

    @Test func placementsWithUniformOverlapsStartEarly() {
        let placements = VideoTimelineMath.placements(durations: [3, 5, 2], overlaps: [0.5, 0.5])
        #expect(placements.map(\.start) == [0, 2.5, 7])
        #expect(isClose(VideoTimelineMath.totalDuration(durations: [3, 5, 2], overlaps: [0.5, 0.5]), 9))
    }

    @Test func mixedBoundariesPlaceIndependently() {
        let placements = VideoTimelineMath.placements(durations: [3, 5, 2], overlaps: [0.5, 0])
        #expect(placements.map(\.start) == [0, 2.5, 7.5])
        #expect(isClose(VideoTimelineMath.totalDuration(durations: [3, 5, 2], overlaps: [0.5, 0]), 9.5))
    }

    @Test func totalDurationSubtractsEachOverlapOnce() {
        let durations = [4.0, 6, 3, 5]
        let overlaps = [0.5, 1, 0.25]
        let total = VideoTimelineMath.totalDuration(durations: durations, overlaps: overlaps)
        let expected = durations.reduce(0, +) - overlaps.reduce(0, +)
        #expect(isClose(total, expected))
    }

    // MARK: - Effective overlaps

    /// A fade must never consume a clip: each boundary caps at half its
    /// shorter neighbour, independently of the other boundaries.
    @Test func effectiveOverlapsClampToHalfTheShorterNeighbourPerBoundary() {
        #expect(VideoTimelineMath.effectiveOverlaps(requested: [2, 2], durations: [10, 1, 10]) == [0.5, 0.5])
        #expect(VideoTimelineMath.effectiveOverlaps(requested: [0.3, 2], durations: [10, 10, 10]) == [0.3, 2])
        #expect(VideoTimelineMath.effectiveOverlaps(requested: [2], durations: [10]) == [])
        #expect(VideoTimelineMath.effectiveOverlaps(requested: [], durations: []) == [])
        #expect(VideoTimelineMath.effectiveOverlaps(requested: [-1], durations: [10, 10]) == [0])
    }

    @Test func noneBoundaryStaysAButtJoint() {
        let overlaps = VideoTimelineMath.effectiveOverlaps(requested: [0, 1], durations: [4, 4, 4])
        #expect(overlaps == [0, 1])
        let placements = VideoTimelineMath.placements(durations: [4, 4, 4], overlaps: overlaps)
        let fades = VideoTimelineMath.crossfades(placements: placements, overlaps: overlaps)
        #expect(fades.count == 1)
        #expect(fades[0].fromIndex == 1)
    }

    /// The forward pass guarantees a clip is never inside two fades at once,
    /// keeping the builder's alternating A/B tracks valid.
    @Test func adjacentOverlapsNeverExceedTheMiddleClip() {
        let overlaps = VideoTimelineMath.effectiveOverlaps(requested: [0.5, 0.5], durations: [10, 1, 10])
        #expect(overlaps[0] + overlaps[1] <= 1)

        // Pathological: first boundary takes its full half, second must shrink
        // below its own half-limit to fit the remainder of the middle clip.
        let tight = VideoTimelineMath.effectiveOverlaps(requested: [1, 1], durations: [10, 1.6, 10])
        #expect(isClose(tight[0], 0.8))
        #expect(isClose(tight[1], 0.8))
        #expect(tight[0] + tight[1] <= 1.6 + 1e-9)

        let tighter = VideoTimelineMath.effectiveOverlaps(requested: [1, 1], durations: [10, 1.2, 10])
        #expect(isClose(tighter[0], 0.6))
        #expect(isClose(tighter[1], 0.6))
    }

    @Test func touchingFadeWindowsStayDisjoint() {
        // Overlaps that sum to exactly the middle clip's duration: the two
        // fade windows abut but never overlap.
        let durations = [10.0, 2, 10]
        let overlaps = VideoTimelineMath.effectiveOverlaps(requested: [1, 1], durations: durations)
        let placements = VideoTimelineMath.placements(durations: durations, overlaps: overlaps)
        let fades = VideoTimelineMath.crossfades(placements: placements, overlaps: overlaps)
        #expect(fades.count == 2)
        #expect(fades[0].start + fades[0].duration <= fades[1].start + 1e-9)
    }

    @Test func mismatchedOverlapCountIsTolerated() {
        // Too few: missing boundaries are butt joints.
        let short = VideoTimelineMath.effectiveOverlaps(requested: [0.5], durations: [4, 4, 4])
        #expect(short == [0.5, 0])
        // Too many: extras are ignored.
        let long = VideoTimelineMath.effectiveOverlaps(requested: [0.5, 0.5, 9, 9], durations: [4, 4, 4])
        #expect(long == [0.5, 0.5])
        // placements/crossfades also tolerate a short array.
        let placements = VideoTimelineMath.placements(durations: [4, 4, 4], overlaps: [0.5])
        #expect(placements.map(\.start) == [0, 3.5, 7.5])
    }

    // MARK: - Clip index

    @Test func clipIndexPicksTheIncomingClipInsideAFade() {
        let placements = VideoTimelineMath.placements(durations: [3, 3], overlaps: [1])
        // Fade window is 2…3: both clips exist; the incoming (1) is on top.
        #expect(VideoTimelineMath.clipIndex(at: 1, placements: placements) == 0)
        #expect(VideoTimelineMath.clipIndex(at: 2.5, placements: placements) == 1)
        #expect(VideoTimelineMath.clipIndex(at: 5, placements: placements) == 1)
        #expect(VideoTimelineMath.clipIndex(at: 5.5, placements: placements) == nil)
        #expect(VideoTimelineMath.clipIndex(at: -1, placements: placements) == nil)
    }

    // MARK: - Crossfades

    @Test func crossfadeWindowsSitAtOverlappedBoundaries() {
        let placements = VideoTimelineMath.placements(durations: [3, 4, 5], overlaps: [0.5, 0.5])
        let fades = VideoTimelineMath.crossfades(placements: placements, overlaps: [0.5, 0.5])
        #expect(fades.count == 2)
        #expect(isClose(fades[0].start, 2.5))
        #expect(isClose(fades[0].duration, 0.5))
        #expect(fades[0].fromIndex == 0)
        #expect(isClose(fades[1].start, 6))
        #expect(isClose(fades[1].duration, 0.5))
    }

    @Test func noOverlapsMeansNoCrossfades() {
        let placements = VideoTimelineMath.placements(durations: [3, 4], overlaps: [0])
        #expect(VideoTimelineMath.crossfades(placements: placements, overlaps: [0]).isEmpty)
    }

    // MARK: - Music

    @Test func musicSegmentsLoopWithATrimmedTail() {
        let segments = VideoTimelineMath.musicSegments(sourceDuration: 4, totalDuration: 10)
        #expect(segments.count == 3)
        #expect(isClose(segments[2].insertAt, 8))
        #expect(isClose(segments[2].duration, 2))
        #expect(isClose(segments.reduce(0) { $0 + $1.duration }, 10))
    }

    @Test func musicLongerThanTheVideoIsASingleTrimmedSegment() {
        let segments = VideoTimelineMath.musicSegments(sourceDuration: 60, totalDuration: 10)
        #expect(segments.count == 1)
        #expect(isClose(segments[0].duration, 10))
    }

    @Test func exactFitMusicDoesNotGrowAnExtraSegment() {
        let segments = VideoTimelineMath.musicSegments(sourceDuration: 5, totalDuration: 10)
        #expect(segments.count == 2)
    }

    @Test func musicRampsCoverTheWholeBed() {
        let ramps = VideoTimelineMath.musicRamps(total: 10, volume: 0.8, fadeIn: 2, fadeOut: 3)
        #expect(ramps.count == 3)
        #expect(isClose(ramps[0].duration, 2))
        #expect(ramps[0].fromVolume == 0)
        #expect(isClose(ramps[0].toVolume, 0.8))
        #expect(isClose(ramps[1].start, 2))
        #expect(isClose(ramps[1].duration, 5))
        #expect(isClose(ramps[2].start, 7))
        #expect(ramps[2].toVolume == 0)
    }

    /// fadeIn + fadeOut longer than the video: both shrink proportionally so
    /// the envelope stays continuous instead of the ramps overlapping.
    @Test func oversizedFadesShrinkProportionally() {
        let ramps = VideoTimelineMath.musicRamps(total: 3, volume: 1, fadeIn: 2, fadeOut: 4)
        let inRamp = ramps.first!
        let outRamp = ramps.last!
        #expect(isClose(inRamp.duration, 1))
        #expect(isClose(outRamp.duration, 2))
        #expect(isClose(inRamp.duration + outRamp.duration, 3))
    }

    // MARK: - Trim

    @Test func trimClampsIntoTheSourceWithAMinimumLength() {
        let clamped = VideoTimelineMath.clampedTrim(start: -2, end: 100, sourceDuration: 10)
        #expect(clamped.start == 0)
        #expect(clamped.end == 10)

        let tiny = VideoTimelineMath.clampedTrim(start: 5, end: 5.01, sourceDuration: 10)
        #expect(isClose(tiny.end - tiny.start, VideoClip.minimumClipDuration))

        let tail = VideoTimelineMath.clampedTrim(start: 9.99, end: 10, sourceDuration: 10)
        #expect(isClose(tail.end - tail.start, VideoClip.minimumClipDuration))
        #expect(tail.end == 10)
    }

    // MARK: - Fade progress

    @Test func fadeProgressIsClampedAtTheEndpoints() {
        #expect(VideoTimelineMath.fadeProgress(at: 1, fadeStart: 2, duration: 1) == 0)
        #expect(VideoTimelineMath.fadeProgress(at: 2.5, fadeStart: 2, duration: 1) == 0.5)
        #expect(VideoTimelineMath.fadeProgress(at: 4, fadeStart: 2, duration: 1) == 1)
        #expect(VideoTimelineMath.fadeProgress(at: 3, fadeStart: 2, duration: 0) == 1)
        #expect(VideoTimelineMath.fadeProgress(at: 1, fadeStart: 2, duration: 0) == 0)
    }

    // MARK: - Reorder

    @Test func dropIndexFollowsTileMidpoints() {
        let widths = [100.0, 100, 100]
        #expect(VideoTimelineMath.dropIndex(forOffset: 0, widths: widths) == 0)
        #expect(VideoTimelineMath.dropIndex(forOffset: 60, widths: widths) == 1)
        #expect(VideoTimelineMath.dropIndex(forOffset: 160, widths: widths) == 2)
        #expect(VideoTimelineMath.dropIndex(forOffset: 900, widths: widths) == 2)
        #expect(VideoTimelineMath.dropIndex(forOffset: 0, widths: []) == 0)
    }

    // MARK: - Clip model

    @Test func effectiveDurationFollowsTheClipKind() {
        var photo = VideoClip(assetID: "a", kind: .photo)
        photo.photoDuration = 4
        #expect(photo.effectiveDuration == 4)

        var video = VideoClip(assetID: "b", kind: .video)
        video.sourceDuration = 12
        #expect(video.effectiveDuration == 12)
        video.trimStart = 2
        video.trimEnd = 7
        #expect(video.effectiveDuration == 5)
    }

    // MARK: - Recipe transitions sync

    @Test func syncTransitionsMatchesTheBoundaryCount() {
        var recipe = VideoProjectRecipe(clips: [
            VideoClip(assetID: "a", kind: .photo),
            VideoClip(assetID: "b", kind: .photo),
            VideoClip(assetID: "c", kind: .photo),
        ])
        recipe.syncTransitionsWithClips()
        #expect(recipe.transitions.count == 2)
        #expect(recipe.transitions.allSatisfy { $0.kind == .none })

        recipe.transitions[0] = .defaultCrossfade
        recipe.clips.removeLast()
        recipe.syncTransitionsWithClips()
        #expect(recipe.transitions.count == 1)
        #expect(recipe.transitions[0].kind == .crossfade)

        recipe.clips.removeAll()
        recipe.syncTransitionsWithClips()
        #expect(recipe.transitions.isEmpty)
    }

    // MARK: - Timed overlays

    @Test func timedOverlayActiveWindow() {
        var timed = TimedOverlay(overlay: .text(), start: 2, duration: 3)
        #expect(!timed.isActive(at: 1.9, total: 10))
        #expect(timed.isActive(at: 2, total: 10))     // start-inclusive
        #expect(timed.isActive(at: 4.9, total: 10))
        #expect(!timed.isActive(at: 5, total: 10))    // end-exclusive

        timed.duration = nil                           // until the end
        #expect(timed.isActive(at: 9.9, total: 10))
        #expect(!timed.isActive(at: 10, total: 10))

        timed.start = 12                               // past the total: never fires
        #expect(!timed.isActive(at: 9, total: 10))

        timed.start = 5
        timed.duration = 0                             // zero-length: never fires
        #expect(!timed.isActive(at: 5, total: 10))
    }
}
