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

    /// The preview's clamp has to reserve what the *lanes* need, not the
    /// phone's floor. At `Lanes.regular` one overlay and one music lane want
    /// 255pt; reserving 248 handed the preview the other 7 and left the lanes
    /// scrolling on every regular-width window.
    @Test func theClampReservesWhatTheLanesActuallyNeed() {
        let landscape = CGSize(width: 1376 - VideoStudioMetrics.railWidth, height: 1032)
        let content = VideoStudioMetrics.Lanes.regular.timelineContentHeight(overlayLanes: 1, musicLanes: 1)
        #expect(content > VideoStudioMetrics.timelineMinimumHeight, "the case this test is about")
        let layout = VideoStudioMetrics.stackLayout(
            screen: landscape, bandHeight: 48, bottomInset: 20,
            canvas: CGSize(width: 16, height: 9), presentsSheet: false,
            timelineContentHeight: content, usesToolRail: true, panelMayDock: true
        )
        #expect(layout.timeline >= content, "the lanes fit without scrolling")
    }

    /// Tablet tracks need a window that is tall as well as wide. The iPhone
    /// Duo's inner display is 867×669: wide enough by the rail's threshold,
    /// and far too short for 255pt of lanes.
    @Test func aShortRegularWindowKeepsThePhonesLanes() {
        #expect(VideoStudioMetrics.Lanes.for(size: CGSize(width: 867, height: 669)) == .compact)
        #expect(VideoStudioMetrics.Lanes.for(size: CGSize(width: 1032, height: 1376)) == .regular)
        #expect(VideoStudioMetrics.Lanes.for(size: CGSize(width: 1376, height: 1032)) == .regular)
        #expect(VideoStudioMetrics.Lanes.for(size: CGSize(width: 402, height: 874)) == .compact)
    }

    /// The lift is the panel's height less the bands it lands on. Take the
    /// tool row away and it grows by that much; take the bottom bar away too
    /// — which is what moving Back and Export into the top band does — and it
    /// is the whole panel.
    @Test func theLiftIsWhateverThePanelDoesNotLandOn() {
        #expect(
            VideoStudioMetrics.sheetLift(usesToolRail: true)
                == VideoStudioMetrics.sheetLift + VideoStudioMetrics.toolbarHeight
        )
        #expect(
            VideoStudioMetrics.sheetLift(usesToolRail: true, showsBottomBar: false)
                == VideoStudioMetrics.sheetHeight
        )
    }

    /// Wide windows spend width on the inspector, tall ones spend height.
    ///
    /// (The survey that proposed this claimed the iPhone Duo's inner display
    /// would take the column at 867×669. It does not: the iPhone target is
    /// portrait-locked, so the app's scene there is 669×951 and stays on the
    /// phone layout. The rule is right; that example was not.)
    @Test func theInspectorGoesBesideTheStageOnlyOnAWideWindow() {
        #expect(VideoStudioMetrics.usesInspectorColumn(size: CGSize(width: 1376, height: 1032)))
        #expect(!VideoStudioMetrics.usesInspectorColumn(size: CGSize(width: 669, height: 951)), "the Duo's real scene")
        #expect(!VideoStudioMetrics.usesInspectorColumn(size: CGSize(width: 1032, height: 1376)), "portrait docks instead")
        #expect(!VideoStudioMetrics.usesInspectorColumn(size: CGSize(width: 402, height: 874)), "the phone keeps its band")
        #expect(
            !VideoStudioMetrics.usesInspectorColumn(size: CGSize(width: 780, height: 500)),
            "a 368pt stage is narrower than a phone's screen"
        )
    }

    /// The column costs the stage width, and the drawer costs it height. On
    /// a landscape tablet the frame is height-limited, so the column is the
    /// one that leaves a bigger picture — the whole reason to build it.
    @Test func theColumnLeavesABiggerFrameThanTheDrawerInLandscape() {
        let lanes = VideoStudioMetrics.Lanes.regular
        let content = lanes.timelineContentHeight(overlayLanes: 1, musicLanes: 1)
        func frameArea(width: CGFloat, presentsSheet: Bool) -> CGFloat {
            let layout = VideoStudioMetrics.stackLayout(
                screen: CGSize(width: width, height: 1032),
                bandHeight: 66, bottomInset: 20,
                canvas: CGSize(width: 16, height: 9), presentsSheet: presentsSheet,
                timelineContentHeight: content, usesToolRail: true,
                panelMayDock: !presentsSheet, showsBottomBar: false
            )
            let height = min(width * 9 / 16, layout.preview)
            return height * height * 16 / 9
        }
        let rail = VideoStudioMetrics.railWidth
        let drawer = frameArea(width: 1376 - rail, presentsSheet: true)
        let column = frameArea(width: 1376 - rail - VideoStudioMetrics.inspectorColumnWidth, presentsSheet: false)
        #expect(column > drawer * 1.5, "the column is worth the width it costs")
    }

    /// The iPhone Duo's cover display is 382×644. Opening the panel there
    /// used to put the preview on its 150pt floor *and* the timeline 108pt
    /// under its own — three regions, all broken, to edit one clip. The
    /// timeline stands down instead and the frame keeps the size it had.
    @Test func aWindowTooShortForEverythingStandsTheTimelineDown() {
        let cover = CGSize(width: 382, height: 644)
        let content = VideoStudioMetrics.Lanes.compact.timelineContentHeight(overlayLanes: 1, musicLanes: 1)
        func layout(open: Bool) -> VideoStudioMetrics.StackLayout {
            VideoStudioMetrics.stackLayout(
                screen: cover, bandHeight: 48, bottomInset: 34,
                canvas: CGSize(width: 16, height: 9), presentsSheet: open,
                timelineContentHeight: content
            )
        }
        let idle = layout(open: false)
        let open = layout(open: true)
        #expect(open.hidesTimeline)
        #expect(open.timeline == 0)
        #expect(open.preview == idle.preview, "the frame does not shrink to make room")
        #expect(open.preview > VideoStudioMetrics.previewMinimumHeight, "and is not on its floor")
    }

    /// A phone has the room, so its panel still slides over a timeline that
    /// stays where it was.
    @Test func aPhoneKeepsItsTimelineWhenThePanelOpens() {
        let content = VideoStudioMetrics.Lanes.compact.timelineContentHeight(overlayLanes: 1, musicLanes: 1)
        let open = VideoStudioMetrics.stackLayout(
            screen: CGSize(width: 402, height: 874), bandHeight: 59, bottomInset: 34,
            canvas: CGSize(width: 16, height: 9), presentsSheet: true,
            timelineContentHeight: content
        )
        #expect(!open.hidesTimeline)
        #expect(open.timeline >= VideoStudioMetrics.timelineMinimumHeight)
    }

    /// The playhead starts at the left edge and walks right with the clip;
    /// once it reaches the centre it pins and the row scrolls under it. The
    /// old behaviour put it in the middle of an empty half-screen the moment
    /// a project opened.
    @Test func thePlayheadWalksToTheCentreThenPins() {
        let width: CGFloat = 1032
        let gutter = VideoStudioMetrics.Lanes.regular.gutter
        let half = VideoStudioMetrics.rowAreaHalfWidth(screenWidth: width, gutter: gutter)
        let pps: CGFloat = 55
        func x(_ time: Double) -> CGFloat {
            VideoStudioMetrics.playheadX(screenWidth: width, gutter: gutter, time: time, pointsPerSecond: pps)
        }
        func offset(_ time: Double) -> CGFloat {
            VideoStudioMetrics.timelineOffsetX(time: time, pointsPerSecond: pps, screenWidth: width, gutter: gutter)
        }

        #expect(x(0) == gutter, "at zero it is on the first frame, at the left edge")
        #expect(offset(0) == 0, "and nothing has scrolled")

        let halfway = Double(half / pps) / 2
        #expect(x(halfway) > gutter && x(halfway) < gutter + half, "it walks")
        #expect(offset(halfway) == 0, "the row has still not moved")

        let pinned = Double(half / pps)
        #expect(x(pinned) == gutter + half, "it reaches the centre")
        #expect(x(pinned + 5) == gutter + half, "and stays there")
        #expect(offset(pinned + 5) > 0, "now the row scrolls instead")
        #expect(offset(pinned + 5) == 5 * pps, "by exactly the overflow")
    }

    /// The top band has to hold Back, the read-out and Export beside the
    /// command row on a regular-width window, which the phone's 48pt cannot.
    @Test func theTopBandGrowsWhereItCarriesTheProjectActions() {
        let phone = VideoStudioMetrics.topBandHeight(usesToolRail: false, safeAreaTop: 59)
        let tablet = VideoStudioMetrics.topBandHeight(usesToolRail: true, safeAreaTop: 24)
        #expect(phone == 59, "the phone's band is its safe-area inset")
        #expect(tablet >= 66)
        #expect(tablet > VideoStudioMetrics.topBandHeight(usesToolRail: false, safeAreaTop: 24))
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
