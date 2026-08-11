import Foundation
import Testing
@testable import ShotDex

struct VideoSplitMathTests {
    private func isClose(_ a: Double, _ b: Double, tolerance: Double = 1e-9) -> Bool {
        abs(a - b) <= tolerance
    }

    // MARK: - Photo splits

    @Test func photoSplitsDurationInTwo() {
        var clip = VideoClip(assetID: "p", kind: .photo)
        clip.photoDuration = 4
        let result = VideoSplitMath.split(clip, atLocalTime: 1.5)
        #expect(result != nil)
        #expect(isClose(result!.0.photoDuration, 1.5))
        #expect(isClose(result!.1.photoDuration, 2.5))
        // Children are distinct clips.
        #expect(result!.0.id != result!.1.id)
        #expect(result!.0.id != clip.id)
    }

    @Test func photoSplitRefusesAtEdges() {
        var clip = VideoClip(assetID: "p", kind: .photo)
        clip.photoDuration = 4
        #expect(VideoSplitMath.split(clip, atLocalTime: 0) == nil)
        #expect(VideoSplitMath.split(clip, atLocalTime: 4) == nil)
        // Too close to an edge for a playable half.
        #expect(VideoSplitMath.split(clip, atLocalTime: 0.01) == nil)
    }

    // MARK: - Video splits

    @Test func videoSplitMapsThroughTrimAndSpeed() {
        var clip = VideoClip(assetID: "v", kind: .video)
        clip.sourceDuration = 10
        clip.trimStart = 2
        clip.trimEnd = 8          // 6s of source, 6s on the timeline at 1×
        let result = VideoSplitMath.split(clip, atLocalTime: 2)
        #expect(result != nil)
        // Source split time = trimStart + local * speed = 2 + 2 = 4.
        #expect(isClose(result!.0.trimStart, 2))
        #expect(isClose(result!.0.trimEnd ?? -1, 4))
        #expect(isClose(result!.1.trimStart, 4))
        #expect(isClose(result!.1.trimEnd ?? -1, 8))
    }

    @Test func videoSplitAccountsForSpeed() {
        var clip = VideoClip(assetID: "v", kind: .video)
        clip.sourceDuration = 12
        clip.trimStart = 0
        clip.trimEnd = 12
        clip.speed = 2            // 12s source → 6s timeline
        #expect(isClose(clip.effectiveDuration, 6))
        // Split at timeline t=3 → source 0 + 3*2 = 6.
        let result = VideoSplitMath.split(clip, atLocalTime: 3)
        #expect(result != nil)
        #expect(isClose(result!.0.trimEnd ?? -1, 6))
        #expect(isClose(result!.1.trimStart, 6))
        #expect(result!.0.speed == 2 && result!.1.speed == 2)
    }
}

struct VideoClipSpeedTests {
    @Test func speedShortensEffectiveDuration() {
        var clip = VideoClip(assetID: "v", kind: .video)
        clip.sourceDuration = 8
        clip.trimStart = 0
        clip.trimEnd = 8
        clip.speed = 4
        #expect(abs(clip.effectiveDuration - 2) < 1e-9)
    }

    @Test func slowSpeedLengthensEffectiveDuration() {
        var clip = VideoClip(assetID: "v", kind: .video)
        clip.sourceDuration = 4
        clip.trimStart = 0
        clip.trimEnd = 4
        clip.speed = 0.5
        #expect(abs(clip.effectiveDuration - 8) < 1e-9)
    }

    @Test func freezeUsesPhotoDuration() {
        var clip = VideoClip(assetID: "v", kind: .freeze)
        clip.photoDuration = 2.5
        #expect(abs(clip.effectiveDuration - 2.5) < 1e-9)
    }
}

struct VideoAspectTests {
    @Test func landscapeKeepsLongEdgeAsWidth() {
        let size = VideoAspect.r16x9.canvasSize(longEdge: 1920)
        #expect(size.width == 1920)
        #expect(size.height == 1080)
    }

    @Test func portraitPutsLongEdgeOnHeight() {
        let size = VideoAspect.r9x16.canvasSize(longEdge: 1920)
        #expect(size.width == 1080)
        #expect(size.height == 1920)
    }

    @Test func squareIsEqualSided() {
        let size = VideoAspect.r1x1.canvasSize(longEdge: 1080)
        #expect(size.width == 1080)
        #expect(size.height == 1080)
    }

    @Test func fourFifthsIsPortrait() {
        let size = VideoAspect.r4x5.canvasSize(longEdge: 1080)
        #expect(size.width == 864)   // 1080 * 4/5, even
        #expect(size.height == 1080)
    }

    @Test func recipeCanvasUsesPresetLongEdge() {
        var recipe = VideoProjectRecipe(clips: [])
        recipe.renderPreset = .uhd4K
        recipe.aspect = .r1x1
        let size = recipe.canvasSize()
        #expect(size.width == 3840 && size.height == 3840)
    }
}

struct VideoMusicLoopTests {
    @Test func nonLoopingMusicIsOneTrimmedSegment() {
        let segments = VideoTimelineMath.musicSegments(
            sourceDuration: 5, totalDuration: 12, loops: false
        )
        #expect(segments.count == 1)
        #expect(segments.first?.duration == 5)
    }

    @Test func nonLoopingMusicTrimsToVideoWhenShorter() {
        let segments = VideoTimelineMath.musicSegments(
            sourceDuration: 20, totalDuration: 8, loops: false
        )
        #expect(segments.count == 1)
        #expect(segments.first?.duration == 8)
    }

    @Test func loopingMusicTilesToFill() {
        let segments = VideoTimelineMath.musicSegments(
            sourceDuration: 5, totalDuration: 12, loops: true
        )
        #expect(segments.count == 3)   // 5 + 5 + 2
        #expect(segments.last?.duration == 2)
    }
}
