import CoreGraphics
import Testing
@testable import ShotDex

/// FS-12.06c AC-14 (the numbers half): the Look panel's geometry on each
/// window, against the F5 boards.
struct VideoLookLayoutTests {
    /// Tiles 70 / 60 / 66 / 103×50, Amount 40 / 36 / 34 / 44; a row on the
    /// phone and the cover, three columns in the Duo's 264 column and the
    /// iPad inspector.
    @Test func lookPanelFitsEveryDevice() {
        let phone = VideoLookPanelStyle.for(.phone)
        #expect(phone.tile == CGSize(width: 70, height: 70) && phone.columns == nil && phone.amountHeight == 40)
        let cover = VideoLookPanelStyle.for(.duoCover)
        #expect(cover.tile == CGSize(width: 60, height: 60) && cover.columns == nil && cover.amountHeight == 36)
        let inner = VideoLookPanelStyle.for(.duoInner)
        #expect(inner.tile == CGSize(width: 66, height: 66) && inner.columns == 3 && inner.amountHeight == 34)
        // Three 66 tiles, two 10 gaps and 14 either side fit the 264 column.
        #expect(3 * inner.tile.width + 2 * inner.tileGap + 2 * inner.inset <= 264)
        for windowClass in [VideoStudioWindowClass.iPadLandscape, .iPadPortrait] {
            let iPad = VideoLookPanelStyle.for(windowClass)
            #expect(iPad.tile.height == 50 && iPad.columns == 3 && iPad.amountHeight == 44 && iPad.segmented)
            // 103-wide tiles in the 360 inspector: 3 × 102.67 + 2 × 10 + 2 × 16.
            #expect(abs(3 * iPad.tile.width + 2 * iPad.tileGap + 2 * iPad.inset - 360) < 1)
        }
        // The phone's panel: 340 tall, standing on the 62 tool row.
        #expect(VideoStudioMetrics.lookSheetHeight == 340)
        #expect(VideoStudioMetrics.toolbarHeight == 62)
    }

    /// With the Look panel open the phone's stack lifts by the panel's
    /// height, so the timeline stays clear above it.
    @Test func phoneStackLiftsForTheLookPanel() {
        let screen = CGSize(width: 402, height: 874)
        let look = VideoStudioMetrics.stackLayout(
            screen: screen, bandHeight: 62, bottomInset: 34, canvas: CGSize(width: 1920, height: 1080),
            presentsSheet: true, timelineContentHeight: 200, showsBottomBar: false,
            sheetHeight: VideoStudioMetrics.lookSheetHeight + VideoStudioMetrics.toolbarHeight
        )
        #expect(look.lift == VideoStudioMetrics.lookSheetHeight)
        let other = VideoStudioMetrics.stackLayout(
            screen: screen, bandHeight: 62, bottomInset: 34, canvas: CGSize(width: 1920, height: 1080),
            presentsSheet: true, timelineContentHeight: 200, showsBottomBar: false
        )
        #expect(other.lift == VideoStudioMetrics.sheetHeight - VideoStudioMetrics.toolbarHeight)
    }
}
