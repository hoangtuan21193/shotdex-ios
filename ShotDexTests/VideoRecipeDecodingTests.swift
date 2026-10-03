import Foundation
import Testing
@testable import ShotDex

/// The Video Studio project as stored JSON (FS-12.04 §7, FS-12.18 §5): it
/// reads leniently. A key this build no longer writes is ignored, a key it
/// has added since is defaulted, and one unreadable clip, overlay or music
/// bed costs that element only — never the project, which the model would
/// otherwise quietly rebuild from scratch.
struct VideoRecipeDecodingTests {
    private func decode(_ json: String) throws -> VideoProjectRecipe {
        try JSONDecoder().decode(VideoProjectRecipe.self, from: Data(json.utf8))
    }

    private let clipA = "11111111-1111-1111-1111-111111111111"
    private let clipB = "22222222-2222-2222-2222-222222222222"
    private let clipC = "33333333-3333-3333-3333-333333333333"

    /// FS-12.04 AC-15: a project saved with a Master level of 0.5 opens, and
    /// the level it had is nowhere in what the project now holds.
    @Test func aMasterKeyIsIgnored() throws {
        let recipe = try decode("""
        {"clips":[{"id":"\(clipA)","assetID":"a","kind":"video","trimStart":0,"trimEnd":10,"sourceDuration":10}],
         "videoVolume":1,"masterVolume":0.5}
        """)
        #expect(recipe.clips.count == 1)
        #expect(recipe.videoVolume == 1)
        // Round trip: the key is gone from what this build writes.
        let written = String(decoding: try JSONEncoder().encode(recipe), as: UTF8.self)
        #expect(!written.contains("masterVolume"))
    }

    /// A draft from an older build has none of the keys added since — not
    /// even the ones every recipe now writes. It opens with their defaults.
    @Test func aProjectMissingNewerKeysStillOpens() throws {
        let recipe = try decode("""
        {"clips":[{"id":"\(clipA)","assetID":"a","kind":"photo"},
                  {"id":"\(clipB)","assetID":"b","kind":"video"}]}
        """)
        #expect(recipe.clips.map(\.assetID) == ["a", "b"])
        #expect(recipe.clips[0].photoDuration == VideoClip.defaultPhotoDuration)
        #expect(recipe.clips[1].speed == 1)
        #expect(recipe.clips[1].trimEnd == nil)
        #expect(recipe.transitions.count == 1)
        #expect(recipe.nodes.count == 1)
        #expect(recipe.aspect == .r16x9)
        #expect(recipe.videoVolume == 1)
        #expect(recipe.musicTracks.isEmpty)
        #expect(recipe.overlays.isEmpty)
    }

    /// FS-12.18 AC-10: one clip this build cannot read is dropped and the
    /// rest of the project — the other clips, the boundaries between them,
    /// music, captions — opens as it was.
    @Test func oneBrokenClipKeepsTheRest() throws {
        let recipe = try decode("""
        {"clips":[{"id":"\(clipA)","assetID":"a","kind":"photo","photoDuration":2},
                  {"id":"\(clipB)","assetID":"b","kind":"hologram"},
                  {"id":"\(clipC)","assetID":"c","kind":"photo","photoDuration":4}],
         "transitions":[{"kind":"crossfade","duration":0.5},{"kind":"none","duration":0.5}],
         "musicTracks":[{"id":"\(clipA)","source":{"bundled":{"id":"calm"}},"volume":0.6},
                        {"id":"\(clipB)","source":{"streamed":{"url":"x"}}}],
         "overlays":[{"overlay":{"broken":true}}],
         "aspect":"r9x16","videoVolume":0.4}
        """)
        #expect(recipe.clips.map(\.assetID) == ["a", "c"])
        #expect(recipe.clips[1].photoDuration == 4)
        #expect(recipe.transitions.count == 1)
        #expect(recipe.musicTracks.count == 1)
        #expect(recipe.musicTracks[0].volume == 0.6)
        #expect(recipe.overlays.isEmpty)
        #expect(recipe.aspect == .r9x16)
        #expect(recipe.videoVolume == 0.4)
    }

    /// A value this build does not know falls back to the default for that
    /// one field; the clip stays.
    @Test func anUnknownEffectKeepsTheClip() throws {
        let recipe = try decode("""
        {"clips":[{"id":"\(clipA)","assetID":"a","kind":"video","effect":"hyperspace","speed":2}],
         "aspect":"r7x3"}
        """)
        #expect(recipe.clips.count == 1)
        #expect(recipe.clips[0].effect == .none)
        #expect(recipe.clips[0].speed == 2)
        #expect(recipe.aspect == .r16x9)
    }

    /// What this build writes, it reads back unchanged.
    @Test func aRecipeRoundTrips() throws {
        var recipe = VideoProjectRecipe(clips: VideoStudioModelFixture.videoClips(2))
        recipe.syncTransitionsWithClips()
        recipe.clips[1].speed = 2
        recipe.clips[0].fadeIn = 0.5
        recipe.musicTracks = [MusicTrack(source: .bundled(id: "calm"))]
        recipe.markers = [TimedMarker(time: 3)]
        recipe.videoVolume = 0.7
        let data = try JSONEncoder().encode(recipe)
        #expect(try JSONDecoder().decode(VideoProjectRecipe.self, from: data) == recipe)
    }
}
