import Testing
@testable import ShotDex

/// FS-18 AC-22 / FS-02.01b §2 — one key rule on every device.
struct ViewerKeyMapTests {
    @Test func periodIsFavoriteEverywhere() {
        for (isVideo, isPlaying) in [(false, false), (true, false), (true, true)] {
            #expect(ViewerKeyMap.action(for: .period, isVideo: isVideo, isPlaying: isPlaying) == .toggleFavorite)
        }
    }

    /// A paused video at frame 120: → is frame 121, same video; playing,
    /// → is the next item; a photo pages either way.
    @Test func arrowsStepAPausedVideoAndPageOtherwise() {
        #expect(ViewerKeyMap.action(for: .right, isVideo: true, isPlaying: false) == .stepFrame(1))
        #expect(ViewerKeyMap.action(for: .left, isVideo: true, isPlaying: false) == .stepFrame(-1))
        #expect(ViewerKeyMap.action(for: .right, isVideo: true, isPlaying: true) == .page(1))
        #expect(ViewerKeyMap.action(for: .left, isVideo: false, isPlaying: false) == .page(-1))
    }
}
