import Foundation
import Testing
@testable import ShotDex

/// FS-12.09 §5: a tap inserts at the playhead — cutting the clip under it,
/// or at an edge without a cut — and the playhead moves to the end of what
/// went in.
struct MediaInsertMathTests {
    private func photo(_ id: String) -> VideoClip {
        var clip = VideoClip(assetID: id, kind: .photo)
        clip.photoDuration = 3
        return clip
    }

    private func ends(_ recipe: VideoProjectRecipe) -> [Double] {
        MediaInsertMath.placements(of: recipe).map { ($0.end * 10).rounded() / 10 }
    }

    /// AC-1: the sample project, playhead 8.4 inside Coast (3.0–9.2): Coast
    /// is cut at 8.4, the photo goes in between, 7 clips over 27.0 s, the
    /// playhead lands at 11.4, and the tab reads "In Video · 8" (7 clips +
    /// the sticker).
    @Test func tapSplitsCoastAt8_4() {
        let sample = VideoStudioModelFixture.mediaSampleRecipe()
        let result = MediaInsertMath.insert([photo("New")], into: sample, at: 8.4)
        let recipe = result.recipe
        #expect(recipe.clips.map(\.assetID) == ["Falls", "Coast", "New", "Coast", "Lake", "Night", "Forest"])
        #expect(ends(recipe) == [3, 8.4, 11.4, 12.2, 17.2, 20.2, 27])
        #expect(abs(result.playhead - 11.4) < 0.0001)
        #expect(result.firstIndex == 2)
        #expect(result.split?.original == sample.clips[1].id)
        #expect(recipe.transitions.count == 6)
        #expect(MediaUsage.useCount(in: recipe) == 8)
    }

    /// A playhead on an edge (9.2, Coast | Lake) cuts nothing: the photo
    /// goes between the two as plain cuts, and a transition further on
    /// stays on its own pair (Lake | Night) instead of sliding a boundary.
    @Test func edgeInsertsWithoutSplit() {
        var sample = VideoStudioModelFixture.mediaSampleRecipe()
        sample.transitions[2] = .defaultCrossfade
        let result = MediaInsertMath.insert([photo("New")], into: sample, at: 9.2)
        #expect(result.split == nil)
        #expect(result.recipe.clips.map(\.assetID) == ["Falls", "Coast", "New", "Lake", "Night", "Forest"])
        #expect(result.recipe.transitions.map(\.kind) == [.none, .none, .none, .crossfade, .none])

        let start = MediaInsertMath.insert([photo("First")], into: sample, at: 0)
        #expect(start.recipe.clips.first?.assetID == "First")
        #expect(start.playhead == 3)
        let end = MediaInsertMath.insert([photo("Last")], into: sample, at: 24)
        #expect(end.recipe.clips.last?.assetID == "Last")
    }

    /// Three taps in a row are three clips in tap order, each after the one
    /// before: the playhead walks along with them.
    @Test func threeTapsKeepOrder() {
        var recipe = VideoStudioModelFixture.mediaSampleRecipe()
        var playhead = 8.4
        for name in ["A", "B", "C"] {
            let result = MediaInsertMath.insert([photo(name)], into: recipe, at: playhead)
            recipe = result.recipe
            playhead = result.playhead
        }
        #expect(recipe.clips.map(\.assetID) == ["Falls", "Coast", "A", "B", "C", "Coast", "Lake", "Night", "Forest"])
        #expect(abs(playhead - 17.4) < 0.0001)
        #expect(recipe.transitions.count == recipe.clips.count - 1)
    }

    /// Several at once (Add (N)) go in the order given, one result.
    @Test func severalGoInInTheOrderGiven() {
        let sample = VideoStudioModelFixture.mediaSampleRecipe()
        let result = MediaInsertMath.insert([photo("1"), photo("2"), photo("3")], into: sample, at: 8.4)
        #expect(result.recipe.clips.map(\.assetID) == ["Falls", "Coast", "1", "2", "3", "Coast", "Lake", "Night", "Forest"])
        #expect(abs(result.playhead - 17.4) < 0.0001)
    }
}
