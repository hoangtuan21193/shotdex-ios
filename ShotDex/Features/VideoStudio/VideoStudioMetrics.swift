import CoreGraphics

/// Fixed geometry for the Video Studio, in points on the 393×852 reference
/// frame (Dynamic Island). The screen is a vertical stack of fixed bands; only
/// the preview flexes. Everything here is read by the screen, the timeline, and
/// the contextual sheets so no view invents its own measurement.
///
/// Vertical map: top band · preview · timeline · toolbar 62 · bottom bar 50.
/// The preview takes its aspect-fit height and the timeline gets everything
/// left over (never less than `timelineMinimumHeight`); a portrait canvas
/// flips that — the preview is capped so the timeline keeps its minimum. The
/// timeline is a viewport: its lane content is taller whenever the overlay /
/// music lanes stack up, and scrolls vertically inside it. `stackLayout`
/// is the one place these heights are decided.
enum VideoStudioMetrics {
    // MARK: Screen bands

    /// The least the timeline ever gets: ruler + one overlay lane + video lane +
    /// one music lane, all visible without vertical scrolling.
    static let timelineMinimumHeight: CGFloat = 248
    /// The least the preview ever gets, so a portrait canvas under the contextual
    /// panel still shows the frame being edited.
    static let previewMinimumHeight: CGFloat = 150
    /// Gap between the preview and the timeline.
    static let previewTimelineGap: CGFloat = 8
    static let toolbarHeight: CGFloat = 62
    /// Back · export estimate · Export pill. Always on screen.
    static let bottomBarHeight: CGFloat = 50
    /// Height of the contextual panel (selection + global tools), above the
    /// device's bottom safe inset. It slides over the bars, never displaces them.
    static let sheetHeight: CGFloat = 264
    /// How far the contextual panel reaches above the toolbar and bottom bar.
    /// The stack lifts by this much while the panel is up, so the whole timeline
    /// stays visible above it and the selected band never hides under the panel.
    static var sheetLift: CGFloat { sheetHeight - toolbarHeight - bottomBarHeight }

    /// The preview / timeline split for one screen. Pure, so it is unit-tested.
    struct StackLayout: Equatable {
        var preview: CGFloat
        var timeline: CGFloat
        /// Spacer under the timeline while the panel is up (`sheetLift`), zero
        /// otherwise.
        var lift: CGFloat
    }

    static func stackLayout(
        screen: CGSize,
        bandHeight: CGFloat,
        bottomInset: CGFloat,
        canvas: CGSize,
        presentsSheet: Bool
    ) -> StackLayout {
        let lift = presentsSheet ? sheetLift : 0
        let fixed = bandHeight + previewTimelineGap + toolbarHeight + bottomBarHeight + bottomInset + lift
        let usable = max(0, screen.height - fixed)
        let natural = canvas.width > 0 ? screen.width * canvas.height / canvas.width : usable
        let previewCap = max(previewMinimumHeight, usable - timelineMinimumHeight)
        let preview = min(max(natural, previewMinimumHeight), previewCap)
        return StackLayout(preview: preview, timeline: max(0, usable - preview), lift: lift)
    }

    // MARK: Sheet tiers

    static let sheetTitleHeight: CGFloat = 36
    static let sheetParamHeight: CGFloat = 112
    static let sheetCommandHeight: CGFloat = 62

    // MARK: Timeline verticals

    static let timelineTopPadding: CGFloat = 8
    static let rulerHeight: CGFloat = 26
    static let rulerToTracks: CGFloat = 3
    static let laneSpacing: CGFloat = 3
    static let scrollbarHeight: CGFloat = 3
    static let timelineBottomPadding: CGFloat = 5

    // MARK: Lanes

    /// Overlay lanes (text and stickers) stack above the video lane; music
    /// lanes stack below it. Both grow with the number of lanes in use.
    static let overlayLaneHeight: CGFloat = 34
    static let videoLaneHeight: CGFloat = 66
    static let musicLaneHeight: CGFloat = 40

    /// Where the lane stack starts, below the pinned ruler.
    static let laneAreaTop: CGFloat = 0

    static func overlayLaneTop(_ lane: Int) -> CGFloat {
        laneAreaTop + CGFloat(lane) * (overlayLaneHeight + laneSpacing)
    }

    static func videoLaneTop(overlayLanes: Int) -> CGFloat {
        overlayLaneTop(max(0, overlayLanes))
    }

    static func musicLaneTop(_ lane: Int, overlayLanes: Int) -> CGFloat {
        videoLaneTop(overlayLanes: overlayLanes)
            + videoLaneHeight + laneSpacing
            + CGFloat(lane) * (musicLaneHeight + laneSpacing)
    }

    /// Total scrollable height of the lane stack (excludes the pinned ruler).
    static func laneContentHeight(overlayLanes: Int, musicLanes: Int) -> CGFloat {
        musicLaneTop(max(0, musicLanes - 1), overlayLanes: overlayLanes)
            + musicLaneHeight
            + timelineBottomPadding
    }

    /// Height of the scrolling viewport under the pinned ruler.
    static func laneViewportHeight(timelineHeight: CGFloat) -> CGFloat {
        timelineHeight - timelineTopPadding - rulerHeight - rulerToTracks - scrollbarHeight - 2
    }

    // MARK: Timeline horizontals

    /// The fixed left icon column; the scrolling content starts after it.
    static let gutterWidth: CGFloat = 30
    static let gutterIconSize: CGFloat = 20

    /// x of the fixed playhead for a given screen width: centre of the row area.
    static func playheadX(screenWidth: CGFloat) -> CGFloat {
        gutterWidth + (screenWidth - gutterWidth) / 2
    }

    /// Half the row area — the content padding at each end so 0s and the last
    /// mark can both sit under the centred playhead.
    static func rowAreaHalfWidth(screenWidth: CGFloat) -> CGFloat {
        (screenWidth - gutterWidth) / 2
    }

    // MARK: Scale

    static let defaultPointsPerSecond: CGFloat = 55
    static let pointsPerSecondRange: ClosedRange<CGFloat> = 20...160

    // MARK: Bands & controls (timeline-only radius exception r-track = 6)

    static let trackRadius: CGFloat = 6
    static let commandCellRadius: CGFloat = 10

    static let clipCellHeight: CGFloat = 54
    static let chipBandHeight: CGFloat = 28
    static let musicBandHeight: CGFloat = 32
    /// Extended hit target for the 28pt chip bands (spec §8: ≥44).
    static let bandHitInset: CGFloat = -8

    static let commandCellWidth: CGFloat = 52
    static let commandCellHeight: CGFloat = 54
    static let inspectorTitleButton: CGFloat = 30
    static let addMediaButtonWidth: CGFloat = 40
    static let transitionChipSize: CGFloat = 22
}
