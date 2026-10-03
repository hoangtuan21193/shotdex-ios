import Foundation
import Testing
@testable import ShotDex

/// What a selected item is called (FS-12.04 §5).
@MainActor
struct VideoItemTitleTests {
    private let locale = Locale(identifier: "en_US")

    @Test func clipsAreNamedByTheirPlaceOnTheTrack() {
        var clips = VideoStudioModelFixture.photoClips(2) + VideoStudioModelFixture.videoClips(1, seconds: 6.2)
        clips[1].photoDuration = 3
        #expect(VideoItemTitle.clip(clips[0], index: 0, locale: locale) == .init(name: "Photo 1", detail: "3.0s · photo"))
        #expect(VideoItemTitle.clip(clips[2], index: 2, locale: locale) == .init(name: "Clip 3", detail: "6.2s · video"))
        let model = VideoStudioModelFixture.model(clips: clips)
        model.selectClip(clips[0].id)
        #expect(model.selectionTitle?.name == "Photo 1")
    }
}
