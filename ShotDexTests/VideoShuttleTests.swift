import Foundation
import Testing
@testable import ShotDex

/// J / K / L (FS-12.17b §3).
struct VideoShuttleTests {
    /// FS-12.17b AC-2: stopped, L, L — rate 2.0 and "2×" on the play button.
    @Test func lTwiceIsTwoX() {
        let once = VideoShuttle.rate(after: .l, from: 0)
        let twice = VideoShuttle.rate(after: .l, from: once)
        #expect(once == 1)
        #expect(twice == 2)
        #expect(VideoShuttle.label(for: twice) == "2×")
        #expect(VideoShuttle.label(for: once) == nil)
        #expect(VideoShuttle.rate(after: .l, from: twice) == 4)
        #expect(VideoShuttle.rate(after: .l, from: 4) == 4)
    }

    /// K stops from anywhere; L while going backwards goes forward at 1×.
    @Test func kStops() {
        #expect(VideoShuttle.rate(after: .k, from: 4) == 0)
        #expect(VideoShuttle.rate(after: .k, from: -2) == 0)
        #expect(VideoShuttle.rate(after: .l, from: -2) == 1)
        #expect(VideoShuttle.rate(after: .j, from: 2) == -1)
        #expect(VideoShuttle.rate(after: .j, from: -1) == -2)
    }

    /// Sound at 1× and 2×; none at 4× or backwards.
    @Test func fourXAndReverseAreMuted() {
        #expect(!VideoShuttle.isMuted(1))
        #expect(!VideoShuttle.isMuted(2))
        #expect(VideoShuttle.isMuted(4))
        #expect(VideoShuttle.isMuted(-1))
        #expect(VideoShuttle.label(for: -4) == "4×")
    }

    /// Through the model, with no player: K is safe and the rate reads 0.
    @MainActor
    @Test func theModelKeepsTheRate() {
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.frameTrimSampleClips())
        model.shuttle(.k)
        #expect(model.shuttleRate == 0)
    }
}
