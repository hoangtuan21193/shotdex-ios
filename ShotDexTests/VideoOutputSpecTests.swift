import CoreGraphics
import Foundation
import Testing
@testable import ShotDex

/// Video Settings' arithmetic (FS-12.10 §5, FS-12.01 §9).
struct VideoOutputSpecTests {
    /// AC-4: the 18 frame sizes of §5's table — short edge by resolution,
    /// long edge by ratio, capped at 3840 — every edge even.
    @Test func everyRatioAndResolution() {
        let table: [VideoAspect: [VideoResolution: CGSize]] = [
            .r16x9: [.p720: .init(width: 1280, height: 720), .p1080: .init(width: 1920, height: 1080), .uhd4K: .init(width: 3840, height: 2160)],
            .r9x16: [.p720: .init(width: 720, height: 1280), .p1080: .init(width: 1080, height: 1920), .uhd4K: .init(width: 2160, height: 3840)],
            .r1x1: [.p720: .init(width: 720, height: 720), .p1080: .init(width: 1080, height: 1080), .uhd4K: .init(width: 2160, height: 2160)],
            .r4x5: [.p720: .init(width: 720, height: 900), .p1080: .init(width: 1080, height: 1350), .uhd4K: .init(width: 2160, height: 2700)],
            .r4x3: [.p720: .init(width: 960, height: 720), .p1080: .init(width: 1440, height: 1080), .uhd4K: .init(width: 2880, height: 2160)],
            .r21x9: [.p720: .init(width: 1680, height: 720), .p1080: .init(width: 2520, height: 1080), .uhd4K: .init(width: 3840, height: 1646)],
        ]
        #expect(table.count == VideoAspect.allCases.count)
        for aspect in VideoAspect.allCases {
            for resolution in VideoResolution.allCases {
                let size = VideoOutputSpec.frameSize(aspect: aspect, resolution: resolution)
                #expect(size == table[aspect]?[resolution], "\(aspect.displayName) \(resolution.displayName)")
                #expect(size.width.truncatingRemainder(dividingBy: 2) == 0 && size.height.truncatingRemainder(dividingBy: 2) == 0)
            }
        }
    }

    /// AC-15: a new project's ratio is the one nearest its first clip — a
    /// portrait video is 9:16, a 4032×3024 photo 4:3, a square 1:1.
    @Test func defaultAspectIsNearestToFirstClip() {
        #expect(VideoAspect.nearest(to: 1080.0 / 1920) == .r9x16)
        #expect(VideoAspect.nearest(to: 4032.0 / 3024) == .r4x3)
        #expect(VideoAspect.nearest(to: 1) == .r1x1)
        #expect(VideoAspect.nearest(to: 1920.0 / 1080) == .r16x9)
        #expect(VideoAspect.nearest(to: 2.4) == .r21x9)
        #expect(VideoAspect.nearest(to: 3.0 / 4) == .r4x5)
        #expect(VideoAspect.nearest(to: .nan) == .r16x9)
        let fresh = VideoProjectRecipe(clips: [])
        #expect(fresh.framing == .fit && fresh.background.kind == .colour && fresh.background.colour == .black)
        #expect(fresh.resolution == .p1080 && fresh.frameRate == .fps30 && fresh.codec == .h264)
    }
}
