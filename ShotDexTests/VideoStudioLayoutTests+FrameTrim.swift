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

extension VideoStudioLayoutTests {
    /// FS-12.17 §13: a filmstrip builds only the frames on screen and one
    /// either side — a minute of clip at Frame zoom is 400 cells of 54pt,
    /// a 402pt window shows 9 of them.
    @Test func filmstripBuildsOnlyVisibleCells() {
        #expect(ClipFilmstrip.drawnCells(count: 400, side: 54, visible: 1000...1402) == 17...26)
        #expect(ClipFilmstrip.drawnCells(count: 400, side: 54, visible: -500 ... -200) == nil)
        #expect(ClipFilmstrip.drawnCells(count: 400, side: 54, visible: -500 ... -10) == 0...0)
        #expect(ClipFilmstrip.drawnCells(count: 3, side: 54, visible: nil) == 0...2)
        #expect(ClipFilmstrip.drawnCells(count: 3, side: 54, visible: -100...20) == 0...1)
    }
}

extension VideoStudioLayoutTests {
    /// FS-12.17b AC-8 (board F6_P_Keyboard): the list stands in the Look
    /// panel's 340 slot over the tool row; the head 46, then 6 and the
    /// 36pt "Keyboard connected" row, the twelve rows 32 each.
    @Test func keyboardCardTakesPanelSlot() {
        #expect(VideoStudioMetrics.lookSheetHeight == 340)
        let list = VideoStudioMetrics.ShortcutList.self
        #expect(list.headerHeight == 46)
        #expect(list.firstRowTop == 88)
        #expect(list.rowHeight == 32)
        #expect(list.keycapSide == 24 && list.keycapGap == 3)
        // On the board the card is at 450: rows start at 538.
        #expect(450 + list.firstRowTop == 538)
        // The frame keeps its idle height; the timeline pays for the panel.
        let screen = CGSize(width: 402, height: 874)
        let idle = VideoStudioMetrics.stackLayout(
            screen: screen, bandHeight: 60, bottomInset: 34, canvas: CGSize(width: 1920, height: 1080),
            presentsSheet: false, timelineContentHeight: 200, showsBottomBar: false, deskChromeHeight: 36
        )
        let open = VideoStudioMetrics.stackLayout(
            screen: screen, bandHeight: 60, bottomInset: 34, canvas: CGSize(width: 1920, height: 1080),
            presentsSheet: true, timelineContentHeight: 200, showsBottomBar: false, deskChromeHeight: 36,
            sheetHeight: VideoStudioMetrics.lookSheetHeight + VideoStudioMetrics.toolbarHeight
        )
        let natural: CGFloat = 402 * 1080 / 1920
        #expect(idle.preview >= natural)
        #expect(open.preview < natural)   // what the Look panel's layout does
        let kept = open.keepingPicture(of: idle, natural: natural)
        #expect(kept.preview == natural)  // a 402×226 picture, as idle
        #expect(kept.preview + kept.timeline == open.preview + open.timeline)
    }
}
