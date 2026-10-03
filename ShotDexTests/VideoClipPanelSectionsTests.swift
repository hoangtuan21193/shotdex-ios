import Testing
@testable import ShotDex

/// What a selected clip's panel holds (FS-12.04b §6, FS-12.05 §3).
@MainActor
struct VideoClipPanelSectionsTests {
    /// FS-12.04b AC-11 / FS-12.05 AC-13: a video has no Duration — Speed,
    /// Volume, Fade, Motion — and says "6.2s · video" under its name.
    @Test func videoClipHasNoDurationSection() {
        #expect(VideoClipPanelSections.sections(for: .video) == [.speed, .volume, .fade, .motion])
        #expect(!VideoClipPanelSections.sections(for: .video).contains(.duration))
        let clip = VideoStudioModelFixture.videoClips(1, seconds: 6.2)[0]
        #expect(VideoItemTitle.clip(clip, index: 0, locale: .init(identifier: "en_US")).detail == "6.2s · video")
        #expect(VideoClipPanelSections.speedPresets == [0.5, 1, 2, 4])
    }

    /// A still keeps Duration, 0.5–10 s, and has no Speed or Volume.
    @Test func photoClipKeepsDuration() {
        for kind in [VideoClipKind.photo, .freeze] {
            let sections = VideoClipPanelSections.sections(for: kind)
            #expect(sections.first == .duration)
            #expect(!sections.contains(.speed))
            #expect(!sections.contains(.volume))
        }
        #expect(VideoClip.photoDurationRange == 0.5...10)
    }
}
