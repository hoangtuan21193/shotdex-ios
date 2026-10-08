import CoreGraphics
import Foundation
import Testing
@testable import ShotDex

/// The frame trim's geometry (FS-12.17 §4–5, board F6_P_PreciseTrim).
extension VideoStudioLayoutTests {
    /// FS-12.17 AC-1: the pill is 248×48, centred, 14 over the footer —
    /// (77, 728) on the board's 402pt screen with its footer at 790.
    @Test func frameTrimPillAt77x728() {
        let metrics = VideoStudioMetrics.FrameTrim.self
        #expect(metrics.pill == CGSize(width: 248, height: 48))
        #expect(metrics.pillButton == CGSize(width: 76, height: 40))
        #expect(metrics.pillOrigin(width: 402, floor: 790) == CGPoint(x: 77, y: 728))
        // The Duo cover: centred in the 382 content, 14 over 644 (AC-16).
        #expect(metrics.pillOrigin(width: 382, floor: 644) == CGPoint(x: 67, y: 582))
    }

    /// The loupe: Ø124 centred on the edge, its foot 2 over the clip; at a
    /// screen edge it slides in and stops 8 from it.
    @Test func loupeClearsClipBy2pt() {
        let metrics = VideoStudioMetrics.FrameTrim.self
        let bounds = CGRect(x: 0, y: 0, width: 402, height: 874)
        let frame = metrics.loupeFrame(edgeX: 216, clipTop: 406, diameter: 124, gap: 2, bounds: bounds)
        #expect(frame == CGRect(x: 154, y: 280, width: 124, height: 124))   // the board's loupe
        #expect(frame.maxY + 2 == 406)
        let atLeft = metrics.loupeFrame(edgeX: 20, clipTop: 406, diameter: 124, gap: 2, bounds: bounds)
        #expect(atLeft.minX == 8)
        let atRight = metrics.loupeFrame(edgeX: 400, clipTop: 406, diameter: 124, gap: 2, bounds: bounds)
        #expect(atRight.maxX == 394)
    }
}
