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
    /// Width of the tool rail that replaces the bottom row on a regular-width
    /// screen. Wide enough for a 24pt glyph over an 11pt label without the
    /// label wrapping ("Background" is the longest), which is what Final Cut
    /// and CapCut both settle on for an iPad rail.
    static let railWidth: CGFloat = 92
    /// One rail cell: the same shape as a toolbar cell, stacked instead of
    /// spread.
    static let railCellHeight: CGFloat = 62
    /// Back · export estimate · Export pill. Always on screen.
    static let bottomBarHeight: CGFloat = 50
    /// Height of the contextual panel (selection + global tools), above the
    /// device's bottom safe inset. It slides over the bars, never displaces them.
    static let sheetHeight: CGFloat = 264
    /// How far the contextual panel reaches above the toolbar and bottom bar.
    /// The stack lifts by this much while the panel is up, so the whole timeline
    /// stays visible above it and the selected band never hides under the panel.
    static var sheetLift: CGFloat { sheetHeight - toolbarHeight - bottomBarHeight }

    /// With the tools in a rail there is no bottom tool row for the panel to
    /// cover, so it overlaps that much more of the stack.
    static func sheetLift(usesToolRail: Bool) -> CGFloat {
        usesToolRail ? sheetHeight - bottomBarHeight : sheetLift
    }

    /// The preview / timeline split for one screen. Pure, so it is unit-tested.
    struct StackLayout: Equatable {
        var preview: CGFloat
        var timeline: CGFloat
        /// Spacer under the timeline while the panel is up (`sheetLift`), zero
        /// otherwise — and zero when the panel is docked, because a docked
        /// panel covers nothing and so nothing has to move out of its way.
        var lift: CGFloat
        /// Height reserved *in the stack* for the contextual panel, when the
        /// window has room to spare for it. Zero means the panel slides over
        /// the bars as it does on a phone.
        var dockedPanel: CGFloat = 0
    }

    /// `timelineContentHeight` is what the lanes in this project actually
    /// occupy. On a phone the timeline is always the smaller half and the
    /// parameter changes nothing; on an iPad the leftover is 600pt, and giving
    /// all of it to the timeline drew three lanes at the top of an empty black
    /// field with the playhead ruled down the middle of the nothing. The
    /// timeline takes what it needs and the preview keeps the rest.
    static func stackLayout(
        screen: CGSize,
        bandHeight: CGFloat,
        bottomInset: CGFloat,
        canvas: CGSize,
        presentsSheet: Bool,
        timelineContentHeight: CGFloat = .greatestFiniteMagnitude,
        usesToolRail: Bool = false,
        /// `true` lets the contextual panel take a place in the stack instead
        /// of sliding over the bars, but only where the window has that much
        /// height going spare. Callers pass the regular-width flag.
        panelMayDock: Bool = false
    ) -> StackLayout {
        // The rail takes the tools out of the vertical stack entirely, so the
        // 62pt the row used to cost goes back to the preview and the timeline.
        let toolRow = usesToolRail ? 0 : toolbarHeight
        let natural = canvas.width > 0 ? screen.width * canvas.height / canvas.width : 0
        let wanted = max(timelineMinimumHeight, timelineContentHeight)

        func split(lift: CGFloat, dock: CGFloat) -> StackLayout {
            let fixed = bandHeight + previewTimelineGap + toolRow + bottomBarHeight + bottomInset + lift + dock
            let usable = max(0, screen.height - fixed)
            let previewCap = max(previewMinimumHeight, usable - timelineMinimumHeight)
            var preview = min(max(natural > 0 ? natural : usable, previewMinimumHeight), previewCap)
            var timeline = max(0, usable - preview)
            if timeline > wanted {
                preview += timeline - wanted
                timeline = wanted
            }
            return StackLayout(preview: preview, timeline: timeline, lift: lift, dockedPanel: dock)
        }

        guard presentsSheet else { return split(lift: 0, dock: 0) }

        // Docking is worth it only when the slack the preview is padding with
        // would still leave the frame its natural size afterwards. A portrait
        // iPad showing a 16:9 project has ~470pt of black around the frame;
        // spending 264 of it on the panel covers nothing, moves nothing, and
        // leaves the timeline exactly where the user scrolled it. A phone has
        // no such slack, so the panel keeps sliding over the bars.
        if panelMayDock {
            let undocked = split(lift: 0, dock: 0)
            if undocked.preview - natural >= sheetHeight + bottomInset {
                return split(lift: 0, dock: sheetHeight + bottomInset)
            }
        }
        return split(lift: sheetLift(usesToolRail: usesToolRail), dock: 0)
    }

    /// The phone's lane geometry, kept as a free function for the layout
    /// tests and for callers that have no width to hand.
    static func timelineContentHeight(overlayLanes: Int, musicLanes: Int) -> CGFloat {
        Lanes.compact.timelineContentHeight(overlayLanes: overlayLanes, musicLanes: musicLanes)
    }

    // MARK: Sheet tiers

    static let sheetTitleHeight: CGFloat = 36
    static let sheetParamHeight: CGFloat = 112
    static let sheetCommandHeight: CGFloat = 62

    // MARK: Timeline verticals

    static let timelineTopPadding: CGFloat = 8
    static let rulerToTracks: CGFloat = 3
    static let laneSpacing: CGFloat = 3
    static let scrollbarHeight: CGFloat = 3
    static let timelineBottomPadding: CGFloat = 5

    // MARK: Lanes

    /// Where the lane stack starts, below the pinned ruler.
    static let laneAreaTop: CGFloat = 0

    /// Lane geometry for one screen width.
    ///
    /// Overlay lanes (text and stickers) stack above the video lane; music
    /// lanes stack below it. Both grow with the number of lanes in use — and
    /// with the screen. A 66pt video lane is right on a 393pt phone and is a
    /// phone track sitting on a tablet at 1032pt: the thumbnail is what a cut
    /// is judged from, and the height a tall window has spare is what
    /// LumaFusion and Final Cut spend on taller tracks rather than on more
    /// black around the preview.
    struct Lanes: Equatable, Sendable {
        var overlay: CGFloat
        var video: CGFloat
        var music: CGFloat
        var ruler: CGFloat
        var clipCell: CGFloat

        static let compact = Lanes(overlay: 34, video: 66, music: 40, ruler: 26, clipCell: 54)
        static let regular = Lanes(overlay: 44, video: 104, music: 52, ruler: 30, clipCell: 88)

        /// Measured on the window, like every other regular-width decision in
        /// this screen: an iPad Split View half reports `.regular` at ~500pt,
        /// where tablet-sized tracks would leave no timeline.
        static func forWidth(_ width: CGFloat) -> Lanes {
            width >= EditorLayoutMetrics.sidebarMinCanvasWidth ? .regular : .compact
        }

        func overlayLaneTop(_ lane: Int) -> CGFloat {
            laneAreaTop + CGFloat(lane) * (overlay + laneSpacing)
        }

        func videoLaneTop(overlayLanes: Int) -> CGFloat {
            overlayLaneTop(max(0, overlayLanes))
        }

        func musicLaneTop(_ lane: Int, overlayLanes: Int) -> CGFloat {
            videoLaneTop(overlayLanes: overlayLanes)
                + video + laneSpacing
                + CGFloat(lane) * (music + laneSpacing)
        }

        /// Total scrollable height of the lane stack (excludes the pinned ruler).
        func laneContentHeight(overlayLanes: Int, musicLanes: Int) -> CGFloat {
            musicLaneTop(max(0, musicLanes - 1), overlayLanes: overlayLanes)
                + music
                + timelineBottomPadding
        }

        /// What the timeline needs to show every lane of this project without
        /// scrolling: the ruler, the lanes, and the paddings around them.
        func timelineContentHeight(overlayLanes: Int, musicLanes: Int) -> CGFloat {
            timelineTopPadding + ruler + rulerToTracks
                + laneContentHeight(overlayLanes: overlayLanes, musicLanes: musicLanes)
                + scrollbarHeight
        }

        /// Height of the scrolling viewport under the pinned ruler.
        func laneViewportHeight(timelineHeight: CGFloat) -> CGFloat {
            timelineHeight - timelineTopPadding - ruler - rulerToTracks - scrollbarHeight - 2
        }
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
