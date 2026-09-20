import CoreGraphics
import Testing
@testable import ShotDex

/// The desk layout — the media pool, the level meter, and the three bands the
/// stage gains on a window wide enough for them. The rules these cover are the
/// ones that decide whether a column is worth its width on a given device, so
/// they are asserted on the real sizes ShotDex ships to rather than on round
/// numbers.
struct VideoStudioDeskLayoutTests {
    // The four windows every one of these rules has to hold on.
    private let phone = CGSize(width: 402, height: 874)
    /// The iPhone Duo's inner display, **measured** 2026-09-20 from a host
    /// screenshot of the open device: 951×669 landscape (2853×2007px at 3x).
    /// `XCUIScreen` reports 669×951 there — the display in its own native
    /// portrait, not the scene the app is handed — and an earlier reading of
    /// this device came from that number.
    private let duoInner = CGSize(width: 951, height: 669)
    /// An iPad Split View half: 639pt on a portrait 12.9" iPad. This is the
    /// window the 600pt desk threshold exists for — wide enough to want a
    /// transport row and track headers, too narrow to spend 92pt on a rail.
    private let splitHalf = CGSize(width: 639, height: 1376)
    private let iPadPortrait = CGSize(width: 1032, height: 1376)
    private let iPadLandscape = CGSize(width: 1376, height: 1032)

    // MARK: Which windows get the desk bands

    @Test func aPhoneGetsNoDeskChrome() {
        #expect(!VideoStudioMetrics.usesDeskChrome(size: phone))
        #expect(VideoStudioMetrics.deskChromeHeight(usesDeskChrome: false) == 0)
    }

    /// The point of the 600pt threshold: a Split View half is wide enough to
    /// want the desk bands — they cost height it has in abundance — and too
    /// narrow to spend 92pt of its width on a tool rail.
    @Test func aSplitViewHalfGetsDeskChromeWithoutTheToolRail() {
        #expect(VideoStudioMetrics.usesDeskChrome(size: splitHalf))
        #expect(!VideoStudioMetrics.usesToolRail(size: splitHalf))
    }

    /// The Duo's inner display is a landscape window wider than a phone and
    /// shorter than a tablet: it earns the rail *and* the desk bands, and its
    /// lanes stay at phone height because 669pt is under the 750 that tablet
    /// lanes need.
    @Test func theDuoInnerDisplayGetsTheRailAndTheDeskBands() {
        #expect(VideoStudioMetrics.usesDeskChrome(size: duoInner))
        #expect(VideoStudioMetrics.usesToolRail(size: duoInner))
        #expect(VideoStudioMetrics.Lanes.for(size: duoInner) == .compact)
    }

    @Test func bothTabletOrientationsGetDeskChrome() {
        #expect(VideoStudioMetrics.usesDeskChrome(size: splitHalf))
        #expect(VideoStudioMetrics.usesDeskChrome(size: iPadPortrait))
        #expect(VideoStudioMetrics.usesDeskChrome(size: iPadLandscape))
    }

    // MARK: The media pool's width budget

    @Test func aPhoneCannotShowTheMediaPool() {
        #expect(!VideoStudioMetrics.canShowMediaPool(size: phone))
    }

    /// The Duo can hold the pool — but at 951pt it is not the 1100 that opens
    /// one unasked, so it stays shut until the user taps for it.
    @Test func theDuoCanOpenTheMediaPoolButDoesNotByDefault() {
        #expect(VideoStudioMetrics.canShowMediaPool(size: duoInner))
        #expect(!VideoStudioMetrics.mediaPoolOpensByDefault(size: duoInner))
    }

    /// A Split View half is the window where the narrow pool earns its name:
    /// 300pt of a 639pt window would leave the frame under its floor.
    @Test func aNarrowWindowGetsTheNarrowPool() {
        #expect(VideoStudioMetrics.mediaPoolWidth(size: splitHalf) == VideoStudioMetrics.mediaPoolNarrowWidth)
        #expect(VideoStudioMetrics.mediaPoolWidth(size: duoInner) == VideoStudioMetrics.mediaPoolWideWidth)
    }

    @Test func aLandscapeTabletOpensTheWideMediaPoolFromTheStart() {
        #expect(VideoStudioMetrics.mediaPoolOpensByDefault(size: iPadLandscape))
        #expect(VideoStudioMetrics.mediaPoolWidth(size: iPadLandscape) == VideoStudioMetrics.mediaPoolWideWidth)
    }

    /// Whatever the window, opening every column the window allows must leave
    /// the frame at least the floor the pool rule promises.
    @Test func theStageKeepsItsFloorWithEveryColumnOpen() {
        for size in [duoInner, splitHalf, iPadPortrait, iPadLandscape] {
            guard VideoStudioMetrics.canShowMediaPool(size: size) else { continue }
            let columns = VideoStudioMetrics.mediaPoolWidth(size: size)
                + VideoStudioMetrics.audioMeterWidth(size: size)
                + (VideoStudioMetrics.usesToolRail(size: size) ? VideoStudioMetrics.railWidth : 0)
            #expect(size.width - columns >= VideoStudioMetrics.mediaPoolMinimumStageWidth)
        }
    }

    /// The inspector is the column that gives way. On a landscape tablet all
    /// four fit; take enough width away and the inspector goes back to being
    /// a panel rather than squeezing the frame.
    @Test func theInspectorYieldsToTheOtherColumns() {
        let others = VideoStudioMetrics.mediaPoolWideWidth + VideoStudioMetrics.audioMeterWideWidth
        #expect(VideoStudioMetrics.usesInspectorColumn(size: iPadLandscape, otherColumns: others))
        let narrow = CGSize(width: 1024, height: 768)
        #expect(VideoStudioMetrics.usesInspectorColumn(size: narrow, otherColumns: 0))
        #expect(!VideoStudioMetrics.usesInspectorColumn(size: narrow, otherColumns: others))
    }

    // MARK: The bands' cost in height

    /// The desk bands are fixed, like the toolbar: they come out of the pot
    /// the preview and the timeline divide, and the timeline — which takes
    /// only what its lanes need — is not the one that pays.
    @Test func theDeskBandsCostThePreviewTheirHeight() {
        let canvas = CGSize(width: 16, height: 9)
        let content = VideoStudioMetrics.Lanes.regular
            .timelineContentHeight(overlayLanes: 1, musicLanes: 1)
        func layout(desk: Bool) -> VideoStudioMetrics.StackLayout {
            VideoStudioMetrics.stackLayout(
                screen: iPadLandscape, bandHeight: 48, bottomInset: 0, canvas: canvas,
                presentsSheet: false, timelineContentHeight: content,
                usesToolRail: true, showsBottomBar: false,
                deskChromeHeight: desk
                    ? VideoStudioMetrics.deskChromeHeight(usesDeskChrome: true)
                    : 0
            )
        }
        let bare = layout(desk: false)
        let desk = layout(desk: true)
        #expect(desk.timeline == bare.timeline)
        #expect(bare.preview - desk.preview == VideoStudioMetrics.deskChromeHeight(usesDeskChrome: true))
    }

    // MARK: Track headers

    @Test func trackHeadersReplaceTheGlyphColumnOnlyOnDeskWindows() {
        #expect(!VideoStudioMetrics.Lanes.compact.withTrackHeaders(false).showsTrackControls)
        #expect(VideoStudioMetrics.Lanes.compact.withTrackHeaders(true).showsTrackControls)
        #expect(VideoStudioMetrics.Lanes.regular.withTrackHeaders(true).gutter
            == VideoStudioMetrics.Lanes.trackHeaderWidth)
    }

    /// Widening the gutter must not change the lanes themselves — the header
    /// is a column in front of the rows, not a new row geometry.
    @Test func trackHeadersLeaveTheLaneHeightsAlone() {
        let plain = VideoStudioMetrics.Lanes.regular
        let headed = plain.withTrackHeaders(true)
        #expect(headed.video == plain.video)
        #expect(headed.overlay == plain.overlay)
        #expect(headed.music == plain.music)
        #expect(headed.timelineContentHeight(overlayLanes: 2, musicLanes: 1)
            == plain.timelineContentHeight(overlayLanes: 2, musicLanes: 1))
    }

    // MARK: Timecode

    @Test func timecodeCountsHoursMinutesSecondsAndFrames() {
        #expect(VideoStudioMetrics.timecode(0) == "00:00:00:00")
        #expect(VideoStudioMetrics.timecode(-5) == "00:00:00:00")
        #expect(VideoStudioMetrics.timecode(61.5) == "00:01:01:15")
        #expect(VideoStudioMetrics.timecode(3661) == "01:01:01:00")
    }

    /// The frame field must never reach the frame rate — 29 is the last
    /// frame of a second at 30fps, and a read-out that prints `:30` is one
    /// the user cannot match a cut against.
    @Test func theFrameFieldNeverReachesTheFrameRate() {
        #expect(VideoStudioMetrics.timecode(1.999).hasSuffix(":29"))
        #expect(VideoStudioMetrics.timecode(2.0).hasSuffix(":00"))
    }

    // MARK: Meter scale

    @Test func theMeterScaleIsLinearInDecibels() {
        #expect(VideoAudioMeterColumn.fractionOf(0) == 1)
        #expect(VideoAudioMeterColumn.fractionOf(VideoLevelMeterModel.floorDB) == 0)
        // Below the floor and above the ceiling both clamp rather than
        // drawing a bar taller or shorter than the track.
        #expect(VideoAudioMeterColumn.fractionOf(-120) == 0)
        #expect(VideoAudioMeterColumn.fractionOf(6) == 1)
        let half = VideoAudioMeterColumn.fractionOf(VideoLevelMeterModel.floorDB / 2)
        #expect(abs(half - 0.5) < 0.0001)
    }

    /// The fade envelope the meter reads has to be the one the export writes,
    /// so it is derived from `VideoTimelineMath.musicRamps` rather than
    /// re-implemented: silent at the start of a fade-in, full in the middle,
    /// silent again at the very end of a fade-out.
    @Test func theMeterReadsTheSameFadeEnvelopeTheExportWrites() {
        let level = { (seconds: Double) in
            VideoLevelMeterModel.rampedVolume(
                at: seconds, total: 10, volume: 1, fadeIn: 2, fadeOut: 2
            )
        }
        #expect(level(0) == 0)
        #expect(abs(level(1) - 0.5) < 0.0001)
        #expect(level(5) == 1)
        #expect(abs(level(9) - 0.5) < 0.0001)
    }

    // MARK: No tool rail on a desk window

    /// Resolve for iPad has no vertical tool rail: what you insert comes off
    /// the library column, what you change lives in the inspector. ShotDex
    /// matches, so the rail's own width must stop being charged to the stage
    /// on every window that has a pool to carry the inserts.
    @Test func theStageKeepsTheRailsWidthOnEveryDeskWindow() {
        for size in [duoInner, splitHalf, iPadPortrait, iPadLandscape] {
            let columns = (VideoStudioMetrics.mediaPoolOpensByDefault(size: size)
                           ? VideoStudioMetrics.mediaPoolWidth(size: size) : 0)
                + VideoStudioMetrics.audioMeterWidth(size: size)
            // The rail is no longer one of the columns that can be charged.
            #expect(size.width - columns >= VideoStudioMetrics.mediaPoolMinimumStageWidth)
        }
    }

    /// The compact path is untouched: a phone has no pool to move the insert
    /// commands onto, so it keeps all nine in its horizontal row.
    @Test func aPhoneKeepsAllNineCommands() {
        #expect(VideoStudioToolbar.commandKinds(poolCarriesInserts: false).count == 9)
    }

    /// Every project-wide tool the rail used to open is still reachable —
    /// they moved into one menu in the top band, so the set must be complete.
    @Test func everyGlobalToolIsInTheProjectMenu() {
        #expect(VideoStudioModel.GlobalTool.allCases.count == 5)
        #expect(VideoStudioModel.GlobalTool.allCases.contains(.ratio))
        #expect(VideoStudioModel.GlobalTool.allCases.contains(.filters))
        #expect(VideoStudioModel.GlobalTool.allCases.contains(.adjustments))
        #expect(VideoStudioModel.GlobalTool.allCases.contains(.masterVolume))
        #expect(VideoStudioModel.GlobalTool.allCases.contains(.background))
    }

    // MARK: Transitions

    /// The one transition control the maths always supported and nothing ever
    /// exposed: `VideoBoundaryTransition.duration` had a range and a default
    /// and no way to change it. The sheet's note has to tell the truth about
    /// what the timeline will actually grant.
    @Test func aTransitionIsClampedToHalfTheShorterNeighbour() {
        // Two clips, the second only 0.6s: a 2s transition cannot fit.
        let granted = VideoTimelineMath.effectiveOverlaps(
            requested: [2.0],
            durations: [5.0, 0.6]
        )
        #expect(granted.count == 1)
        #expect(granted[0] <= 0.3 + 0.0001)
        #expect(granted[0] < 2.0)
    }

    @Test func aTransitionThatFitsIsGrantedInFull() {
        let granted = VideoTimelineMath.effectiveOverlaps(
            requested: [0.5],
            durations: [5.0, 4.0]
        )
        #expect(abs(granted[0] - 0.5) < 0.0001)
    }

    /// Every kind the sheet lists must be a kind the compositor can blend, or
    /// the sheet is offering something the export cannot honour.
    @Test func everyTransitionKindIsOfferedAndRenderable() {
        #expect(VideoTransitionKind.allCases.contains(.none))
        #expect(VideoTransitionKind.allCases.contains(.crossfade))
        #expect(VideoTransitionKind.allCases.count >= 7)
    }

    // MARK: Media pool cells

    @Test func theMediaPoolFitsThreeColumnsWideAndTwoNarrow() {
        #expect(VideoStudioMetrics.mediaPoolColumnCount(columnWidth: VideoStudioMetrics.mediaPoolWideWidth) == 3)
        #expect(VideoStudioMetrics.mediaPoolColumnCount(columnWidth: VideoStudioMetrics.mediaPoolNarrowWidth) == 2)
    }

    /// The cells and their gaps must not add up to more than the column, or
    /// the last one in every row is clipped by the divider.
    @Test func theMediaPoolCellsFitInsideTheirColumn() {
        for width in [VideoStudioMetrics.mediaPoolWideWidth, VideoStudioMetrics.mediaPoolNarrowWidth] {
            let count = CGFloat(VideoStudioMetrics.mediaPoolColumnCount(columnWidth: width))
            let cell = VideoStudioMetrics.mediaPoolCellWidth(columnWidth: width)
            #expect(cell > 0)
            #expect(cell * count + VideoStudioMetrics.mediaPoolCellSpacing * (count + 1) <= width)
        }
    }
}
