import AVFoundation
import Foundation
import Testing
@testable import ShotDex

/// What the audio mix asks of each track (FS-12.08 §2): a clip's own sound at
/// the project's Video sound level, a music bed at its own volume — and no
/// third, project-wide gain on top of either.
struct VideoAudioMixTests {
    private func volume(of mix: AVAudioMix, track: CMPersistentTrackID, at seconds: Double) -> Float? {
        guard let parameters = mix.inputParameters.first(where: { $0.trackID == track }) else { return nil }
        var start: Float = -1
        var end: Float = -1
        var range = CMTimeRange.invalid
        guard parameters.getVolumeRamp(
            for: CMTime(seconds: seconds, preferredTimescale: 600),
            startVolume: &start,
            endVolume: &end,
            timeRange: &range
        ) else { return nil }
        return start
    }

    /// FS-12.04 AC-15: a project that still carries a Master of 0.5 mixes
    /// clip 2 at its Video sound level, not at half of it.
    @Test func clipGainIsVideoSoundOnly() throws {
        let clipID = "22222222-2222-2222-2222-222222222222"
        let recipe = try JSONDecoder().decode(VideoProjectRecipe.self, from: Data("""
        {"clips":[{"id":"\(clipID)","assetID":"b","kind":"video","trimStart":0,"trimEnd":10,"sourceDuration":10}],
         "videoVolume":1,"masterVolume":0.5}
        """.utf8))
        var layout = VideoCompositionBuilder.Layout()
        layout.clipAudio = [VideoCompositionBuilder.Layout.ClipAudio(
            clipID: try #require(UUID(uuidString: clipID)),
            trackID: 7,
            range: CMTimeRange(start: .zero, duration: CMTime(seconds: 10, preferredTimescale: 600))
        )]
        layout.totalDuration = 10
        let mix = VideoCompositionBuilder.audioMix(recipe: recipe, layout: layout)
        #expect(volume(of: mix, track: 7, at: 1) == 1)
    }

    /// Video sound is the one project-wide level: 40 puts clip audio at 0.4.
    @Test func videoSoundScalesClipAudio() throws {
        var recipe = VideoProjectRecipe(clips: VideoStudioModelFixture.videoClips(1))
        recipe.videoVolume = 0.4
        var layout = VideoCompositionBuilder.Layout()
        layout.clipAudio = [VideoCompositionBuilder.Layout.ClipAudio(
            clipID: recipe.clips[0].id,
            trackID: 3,
            range: CMTimeRange(start: .zero, duration: CMTime(seconds: 10, preferredTimescale: 600))
        )]
        let mix = VideoCompositionBuilder.audioMix(recipe: recipe, layout: layout)
        let level = try #require(volume(of: mix, track: 3, at: 1))
        #expect(abs(level - 0.4) < 0.0001)
    }
}

extension VideoAudioMixTests {
    /// FS-12.08 §2: a clip's own Volume multiplies Video sound — 60 × 50
    /// plays at 0.3; the clip next to it stays at Video sound.
    @Test func clipVolumeMultipliesVideoSound() throws {
        var recipe = VideoProjectRecipe(clips: VideoStudioModelFixture.videoClips(2))
        recipe.videoVolume = 0.5
        recipe.clips[0].volume = 0.6
        var layout = VideoCompositionBuilder.Layout()
        layout.clipAudio = recipe.clips.enumerated().map { index, clip in
            VideoCompositionBuilder.Layout.ClipAudio(
                clipID: clip.id,
                trackID: CMPersistentTrackID(index + 1),
                range: CMTimeRange(start: .zero, duration: CMTime(seconds: 10, preferredTimescale: 600))
            )
        }
        let mix = VideoCompositionBuilder.audioMix(recipe: recipe, layout: layout)
        #expect(abs(try #require(volume(of: mix, track: 1, at: 1)) - 0.3) < 0.0001)
        #expect(abs(try #require(volume(of: mix, track: 2, at: 1)) - 0.5) < 0.0001)
    }
}
