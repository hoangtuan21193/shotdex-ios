import Foundation
import ShotDexKit
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

extension VideoItemTitleTests {
    @Test func captionsAndMusicSayWhatAndWhen() {
        var overlay = PhotoOverlay.text()
        overlay.text = "GOLDEN HOUR"
        let caption = TimedOverlay(overlay: overlay, start: 1, duration: 4)
        #expect(VideoItemTitle.overlay(caption, totalDuration: 24, locale: locale) == .init(name: "GOLDEN HOUR", detail: "Text · 1.0 → 5.0s"))
        let open = TimedOverlay(overlay: overlay, start: 20)
        #expect(VideoItemTitle.overlay(open, totalDuration: 24, locale: locale).detail == "Text · 20.0 → 24.0s")
        var music = MusicTrack(source: .imported(url: URL(fileURLWithPath: "/m.m4a"), displayName: "Morning Drive"))
        music.start = 0
        #expect(VideoItemTitle.music(music, end: 18.4, locale: locale) == .init(name: "Morning Drive", detail: "Music · 0.0 → 18.4s"))
    }

    /// FS-12.04 AC-6: clip 2 at 2×, then a tap on the GOLDEN HOUR caption —
    /// clip 2 keeps 2×, the footer names the caption, and the panel is the
    /// same height for either (it depends on the window, not the item).
    @Test func switchingItemsKeepsTheFirstItemsEdits() {
        var overlay = PhotoOverlay.text()
        overlay.text = "GOLDEN HOUR"
        let model = VideoStudioModelFixture.model { recipe in
            recipe.overlays = [TimedOverlay(overlay: overlay, start: 1, duration: 4)]
        }
        let clip2 = model.recipe.clips[1].id
        model.selectClip(clip2)
        model.beginUndoGroup()
        model.setSpeed(2, for: clip2)
        model.endUndoGroup()

        model.selectOverlay(overlay.id)
        #expect(model.recipe.clips[1].speed == 2)
        #expect(model.selectionTitle?.name == "GOLDEN HOUR")
        #expect(model.session?.target == .overlay(overlay.id))
        model.cancelSession()
        #expect(model.recipe.clips[1].speed == 2)
        // One panel height for every item: the sheet is a constant of the
        // window, never of what is selected.
        #expect(VideoStudioMetrics.sheetHeight == 264)
    }
}
