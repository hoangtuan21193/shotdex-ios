import Foundation
import ShotDexKit
import Testing
@testable import ShotDex

/// FS-12.09 §4: count = rows = uses — the mark on a Media cell and the
/// number on the In Video tab come from one rule.
struct MediaUsageTests {
    /// AC-6 (first half): Falls at clip 1 and again at clip 6 is "×2".
    @Test func twoUsesShowTimesTwo() {
        var recipe = VideoStudioModelFixture.mediaSampleRecipe()
        recipe.clips.append(recipe.clips[0].copyWithNewID())
        recipe.syncTransitionsWithClips()
        let uses = MediaUsage.uses(in: recipe)
        #expect(uses["Falls"] == 2)
        #expect(MediaUsage.badge(forUses: uses["Falls"] ?? 0) == .times(2))
        #expect(MediaUsage.badge(forUses: uses["Coast"] ?? 0) == .check)
        #expect(MediaUsage.badge(forUses: uses["Unused"] ?? 0) == .none)
    }

    /// AC-6 (second half): delete clip 6 → back to ✓; delete clip 1 too →
    /// no mark at all.
    @Test func deletingBackToOneShowsCheck() {
        var recipe = VideoStudioModelFixture.mediaSampleRecipe()
        recipe.clips.append(recipe.clips[0].copyWithNewID())
        recipe.clips.removeLast()
        #expect(MediaUsage.badge(forUses: MediaUsage.uses(in: recipe)["Falls"] ?? 0) == .check)
        recipe.clips.removeFirst()
        #expect(MediaUsage.badge(forUses: MediaUsage.uses(in: recipe)["Falls"] ?? 0) == .none)
    }

    /// AC-18: Falls at clip 1, clip 6 and as a sticker is "×3" — a sticker
    /// is a use like a clip; one with no library id is not.
    @Test func stickerCountsAsAUse() {
        var recipe = VideoStudioModelFixture.mediaSampleRecipe()
        recipe.clips.append(recipe.clips[0].copyWithNewID())
        recipe.overlays.append(TimedOverlay(overlay: .image(id: UUID(), assetIdentifier: "Falls")))
        recipe.overlays.append(TimedOverlay(overlay: .image(id: UUID(), assetIdentifier: nil)))
        recipe.overlays.append(TimedOverlay(overlay: PhotoOverlay(kind: .text)))
        #expect(MediaUsage.badge(forUses: MediaUsage.uses(in: recipe)["Falls"] ?? 0) == .times(3))
    }

    /// The tab counts every use: the sample's five clips and its sticker
    /// are "In Video · 6"; a split clip is two.
    @Test func tabCountIsEveryUse() throws {
        var recipe = VideoStudioModelFixture.mediaSampleRecipe()
        #expect(MediaUsage.useCount(in: recipe) == 6)
        let (first, second) = try #require(VideoSplitMath.split(recipe.clips[1], atLocalTime: 2))
        recipe.clips.replaceSubrange(1...1, with: [first, second])
        #expect(MediaUsage.useCount(in: recipe) == 7)
    }
}

extension VideoClip {
    /// The same media again, as a separate clip.
    func copyWithNewID() -> VideoClip {
        var copy = VideoClip(assetID: assetID, kind: kind)
        copy.photoDuration = photoDuration
        copy.trimStart = trimStart
        copy.trimEnd = trimEnd
        copy.sourceDuration = sourceDuration
        return copy
    }
}
