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
    /// The iPhone Duo's inner display, portrait: the device the desk bands
    /// were lowered below the tool rail's 700pt threshold for.
    private let duoInner = CGSize(width: 669, height: 951)
    private let iPadPortrait = CGSize(width: 1032, height: 1376)
    private let iPadLandscape = CGSize(width: 1376, height: 1032)

    // MARK: Which windows get the desk bands

    @Test func aPhoneGetsNoDeskChrome() {
        #expect(!VideoStudioMetrics.usesDeskChrome(size: phone))
        #expect(VideoStudioMetrics.deskChromeHeight(usesDeskChrome: false) == 0)
    }

    /// The point of the 600pt threshold: the Duo's inner display never
    /// reaches the tool rail's 700, and it is the window with the most to
    /// gain from a transport row and track headers.
    @Test func theDuoInnerDisplayGetsDeskChromeWithoutTheToolRail() {
        #expect(VideoStudioMetrics.usesDeskChrome(size: duoInner))
        #expect(!VideoStudioMetrics.usesToolRail(size: duoInner))
    }

    @Test func bothTabletOrientationsGetDeskChrome() {
        #expect(VideoStudioMetrics.usesDeskChrome(size: iPadPortrait))
        #expect(VideoStudioMetrics.usesDeskChrome(size: iPadLandscape))
    }

    // MARK: The media pool's width budget

    @Test func aPhoneCannotShowTheMediaPool() {
        #expect(!VideoStudioMetrics.canShowMediaPool(size: phone))
    }

    /// It fits on the Duo, but only just, and only at the narrow width — so
    /// it stays shut until the user asks for it.
    @Test func theDuoCanOpenTheMediaPoolButDoesNotByDefault() {
        #expect(VideoStudioMetrics.canShowMediaPool(size: duoInner))
        #expect(VideoStudioMetrics.mediaPoolWidth(size: duoInner) == VideoStudioMetrics.mediaPoolNarrowWidth)
        #expect(!VideoStudioMetrics.mediaPoolOpensByDefault(size: duoInner))
    }

    @Test func aLandscapeTabletOpensTheWideMediaPoolFromTheStart() {
        #expect(VideoStudioMetrics.mediaPoolOpensByDefault(size: iPadLandscape))
        #expect(VideoStudioMetrics.mediaPoolWidth(size: iPadLandscape) == VideoStudioMetrics.mediaPoolWideWidth)
    }

    /// Whatever the window, opening every column the window allows must leave
    /// the frame at least the floor the pool rule promises.
    @Test func theStageKeepsItsFloorWithEveryColumnOpen() {
        for size in [duoInner, iPadPortrait, iPadLandscape] {
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
