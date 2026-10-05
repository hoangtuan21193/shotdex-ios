import Foundation
import ShotDexKit
import Testing
@testable import ShotDex

/// The pure rules of a multi-select group (FS-12.11), on FS-12.11 §9's
/// sample project: 3.0s photo · 6.2s video · 5.0s video · 3.0s photo ·
/// 6.8s video, every boundary a straight cut.
struct VideoClipGroupEditingTests {
    private let recipe = VideoStudioModelFixture.mediaSampleRecipe()
    private var ids: [UUID] { recipe.clips.map(\.id) }

    /// AC-2's lines: clips 2, 3, 4 are 14.2s of two videos and a photo;
    /// clips 2 and 3 are all video, so the count of kinds is left off.
    @Test func summaryCountsKinds() {
        let three = VideoClipGroupEditing.summary(of: [ids[1], ids[2], ids[3]], in: recipe)
        #expect(three == .init(count: 3, seconds: 14.2, videos: 2, photos: 1))
        #expect(VideoStudioCopy.groupDetail(three) == "14.2s · 2 videos + 1 photo")
        #expect(VideoStudioCopy.groupDetail(three, includesKinds: false) == "14.2s")
        #expect(VideoStudioCopy.selectedCount(3) == "3 selected")
        #expect(VideoStudioCopy.clipCount(3) == "3 Clips")

        let videos = VideoClipGroupEditing.summary(of: [ids[1], ids[2]], in: recipe)
        #expect(VideoStudioCopy.groupDetail(videos) == "11.2s")
        let photosAndOneVideo = VideoClipGroupEditing.summary(of: [ids[0], ids[1], ids[3]], in: recipe)
        #expect(VideoStudioCopy.groupDetail(photosAndOneVideo) == "12.2s · 1 video + 2 photos")
    }

    /// The group is held in timeline order whatever order it was tapped in,
    /// and Shift-click's run includes both ends.
    @Test func orderAndRangeFollowTheTimeline() {
        #expect(VideoClipGroupEditing.ordered([ids[3], ids[1], UUID()], in: recipe) == [ids[1], ids[3]])
        #expect(VideoClipGroupEditing.range(from: ids[3], to: ids[1], in: recipe) == [ids[1], ids[2], ids[3]])
    }
}
