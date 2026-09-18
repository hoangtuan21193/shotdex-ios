import CoreGraphics
import Testing
@testable import ShotDex

/// The preview / timeline split (`VideoStudioMetrics.stackLayout`): the preview
/// takes its aspect-fit height, the timeline the rest, and the stack lifts under
/// the contextual panel so the lanes stay visible.
struct VideoStudioLayoutTests {
    // iPhone 17 Pro: 402×874, Dynamic Island band 59, home inset 34.
    private let screen = CGSize(width: 402, height: 874)
    private let band: CGFloat = 59
    private let inset: CGFloat = 34

    private var usable: CGFloat {
        screen.height - band - VideoStudioMetrics.previewTimelineGap
            - VideoStudioMetrics.toolbarHeight - VideoStudioMetrics.bottomBarHeight - inset
    }

    @Test func landscapeCanvasGivesTheTimelineTheLeftover() {
        let layout = VideoStudioMetrics.stackLayout(
            screen: screen, bandHeight: band, bottomInset: inset,
            canvas: CGSize(width: 3, height: 2), presentsSheet: false
        )
        #expect(layout.preview == 268)
        #expect(layout.timeline == usable - 268)
        #expect(layout.timeline > VideoStudioMetrics.timelineMinimumHeight)
        #expect(layout.lift == 0)
    }

    @Test func portraitCanvasIsCappedSoTheTimelineKeepsItsMinimum() {
        let layout = VideoStudioMetrics.stackLayout(
            screen: screen, bandHeight: band, bottomInset: inset,
            canvas: CGSize(width: 9, height: 16), presentsSheet: false
        )
        #expect(layout.timeline == VideoStudioMetrics.timelineMinimumHeight)
        #expect(layout.preview == usable - VideoStudioMetrics.timelineMinimumHeight)
    }

    @Test func sheetLiftsTheStackAndTakesFromTheTimelineFirst() {
        let idle = VideoStudioMetrics.stackLayout(
            screen: screen, bandHeight: band, bottomInset: inset,
            canvas: CGSize(width: 3, height: 2), presentsSheet: false
        )
        let up = VideoStudioMetrics.stackLayout(
            screen: screen, bandHeight: band, bottomInset: inset,
            canvas: CGSize(width: 3, height: 2), presentsSheet: true
        )
        #expect(up.lift == VideoStudioMetrics.sheetLift)
        #expect(up.lift == 152)
        // Landscape has timeline slack, so the timeline shrinks before the preview.
        #expect(up.timeline == VideoStudioMetrics.timelineMinimumHeight)
        #expect(up.preview == idle.preview - (152 - (idle.timeline - VideoStudioMetrics.timelineMinimumHeight)))
        #expect(up.preview + up.timeline + up.lift == idle.preview + idle.timeline)
    }

    @Test func previewNeverDropsBelowItsMinimum() {
        let layout = VideoStudioMetrics.stackLayout(
            screen: CGSize(width: 375, height: 667), bandHeight: 48, bottomInset: 0,
            canvas: CGSize(width: 9, height: 16), presentsSheet: true
        )
        #expect(layout.preview >= VideoStudioMetrics.previewMinimumHeight)
        #expect(layout.preview + layout.timeline + layout.lift
            == 667 - 48 - VideoStudioMetrics.previewTimelineGap
                - VideoStudioMetrics.toolbarHeight - VideoStudioMetrics.bottomBarHeight)
    }
}
