import CoreGraphics

/// Fixed geometry for the Video Studio, in points on the 393×852 reference
/// frame (Dynamic Island). The screen is a vertical stack of fixed bands; only
/// the preview flexes. Everything here is read by the screen, the timeline, and
/// the contextual sheets so no view invents its own measurement.
///
/// Vertical map: top band · preview (flex) · timeline 248 · toolbar 62.
/// The timeline is a viewport: its lane content is taller than 248 whenever the
/// overlay/music lanes stack up, and scrolls vertically inside it.
enum VideoStudioMetrics {
    // MARK: Screen bands

    static let timelineHeight: CGFloat = 248
    static let toolbarHeight: CGFloat = 62
    /// Back · export estimate · Export pill. Always on screen.
    static let bottomBarHeight: CGFloat = 50
    /// Height of the contextual panel (selection + global tools), above the
    /// device's bottom safe inset. It slides over the bars, never displaces them.
    static let sheetHeight: CGFloat = 264

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
    static var laneViewportHeight: CGFloat {
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
