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

    /// An iPad leaves 600pt over after the preview. All of it went to the
    /// timeline, which drew three lanes at the top of an empty black field
    /// with the playhead ruled down the middle of the nothing.
    @Test func aBigScreenGivesTheSurplusToThePreviewNotTheTimeline() {
        let iPad = CGSize(width: 1032, height: 1376)
        let content = VideoStudioMetrics.timelineContentHeight(overlayLanes: 1, musicLanes: 1)
        let layout = VideoStudioMetrics.stackLayout(
            screen: iPad, bandHeight: 24, bottomInset: 20,
            canvas: CGSize(width: 16, height: 9), presentsSheet: false,
            timelineContentHeight: content
        )
        #expect(layout.timeline == max(VideoStudioMetrics.timelineMinimumHeight, content))
        #expect(layout.preview > iPad.width * 9 / 16, "the surplus goes to the preview band")
    }

    /// Capping is opt-in. Left out — which is what the phone does — the
    /// timeline still takes the whole leftover, because a landscape project
    /// getting a tall timeline instead of black bars is the documented choice
    /// on a screen that small.
    @Test func withoutAContentHeightTheTimelineStillTakesTheLeftover() {
        let layout = VideoStudioMetrics.stackLayout(
            screen: screen, bandHeight: band, bottomInset: inset,
            canvas: CGSize(width: 3, height: 2), presentsSheet: false
        )
        #expect(layout.timeline == usable - 268)
        #expect(layout.timeline > VideoStudioMetrics.timelineContentHeight(
            overlayLanes: 1, musicLanes: 1
        ))
    }

    /// The rail takes the tool row out of the vertical stack, so the 62pt it
    /// used to cost goes back to the preview and the timeline — the whole
    /// reason to move the tools to the side on a screen that is short, not
    /// narrow.
    @Test func theToolRailGivesItsHeightBackToTheStack() {
        let iPad = CGSize(width: 1032, height: 1376)
        let content = VideoStudioMetrics.timelineContentHeight(overlayLanes: 1, musicLanes: 1)
        let row = VideoStudioMetrics.stackLayout(
            screen: iPad, bandHeight: 24, bottomInset: 20,
            canvas: CGSize(width: 16, height: 9), presentsSheet: false,
            timelineContentHeight: content
        )
        let rail = VideoStudioMetrics.stackLayout(
            screen: iPad, bandHeight: 24, bottomInset: 20,
            canvas: CGSize(width: 16, height: 9), presentsSheet: false,
            timelineContentHeight: content, usesToolRail: true
        )
        #expect(rail.preview == row.preview + VideoStudioMetrics.toolbarHeight)
        #expect(rail.timeline == row.timeline)
    }

    /// A portrait iPad showing a 16:9 project pads the frame with ~470pt of
    /// black. The panel takes its place in the stack out of that padding
    /// rather than sliding over the bars: nothing is covered, and the
    /// timeline keeps the height and the position it had.
    @Test func aWindowWithSlackDocksThePanelInsteadOfLiftingTheStack() {
        let iPad = CGSize(width: 1032 - VideoStudioMetrics.railWidth, height: 1376)
        let lanes = VideoStudioMetrics.Lanes.regular
        let content = lanes.timelineContentHeight(overlayLanes: 1, musicLanes: 1)
        let closed = VideoStudioMetrics.stackLayout(
            screen: iPad, bandHeight: 48, bottomInset: 20,
            canvas: CGSize(width: 16, height: 9), presentsSheet: false,
            timelineContentHeight: content, usesToolRail: true, panelMayDock: true
        )
        let open = VideoStudioMetrics.stackLayout(
            screen: iPad, bandHeight: 48, bottomInset: 20,
            canvas: CGSize(width: 16, height: 9), presentsSheet: true,
            timelineContentHeight: content, usesToolRail: true, panelMayDock: true
        )
        #expect(open.dockedPanel == VideoStudioMetrics.sheetHeight + 20)
        #expect(open.lift == 0)
        #expect(open.timeline == closed.timeline, "the timeline does not move for a docked panel")
        #expect(open.preview == closed.preview - open.dockedPanel)
        #expect(open.preview >= iPad.width * 9 / 16, "the frame keeps its natural size")
    }

    /// A phone has no slack to dock into, so the panel still slides over the
    /// bars and the stack still lifts.
    @Test func aPhoneKeepsTheSlidingPanel() {
        let layout = VideoStudioMetrics.stackLayout(
            screen: screen, bandHeight: band, bottomInset: inset,
            canvas: CGSize(width: 16, height: 9), presentsSheet: true,
            timelineContentHeight: VideoStudioMetrics.timelineContentHeight(overlayLanes: 1, musicLanes: 1),
            panelMayDock: false
        )
        #expect(layout.dockedPanel == 0)
        #expect(layout.lift == VideoStudioMetrics.sheetLift)
    }

    /// With no tool row under it, the panel covers that much more of the
    /// stack, so the lift has to grow by the same amount.
    @Test func theRailMakesThePanelLiftFurther() {
        #expect(
            VideoStudioMetrics.sheetLift(usesToolRail: true)
                == VideoStudioMetrics.sheetLift + VideoStudioMetrics.toolbarHeight
        )
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
