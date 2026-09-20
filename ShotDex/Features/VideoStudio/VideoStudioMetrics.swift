import CoreGraphics
import Foundation

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
    /// The inspector, when it stands beside the stage instead of under the
    /// timeline. Final Cut puts it left, Resolve right, LumaFusion left; it
    /// goes right here because the tool rail already owns the leading edge
    /// and two columns of chrome on one side is the mistake the photo
    /// editor's sidebar was written to avoid.
    static let inspectorColumnWidth: CGFloat = 320

    /// A window wide enough for the rail **and** wider than it is tall gets
    /// the column: there the stage is short of height, not width, so the
    /// inspector should cost width. A portrait tablet is the opposite and
    /// docks the panel under the timeline instead.
    /// The floor is a stage no narrower than a phone's screen: below that the
    /// column has taken more than it gave back. The iPhone Duo's inner
    /// display leaves 455pt and clears it — and it is the device the drawer
    /// hurt most, squeezing the frame to 266×150.
    static let minimumStageWidth: CGFloat = 400

    static func usesInspectorColumn(size: CGSize) -> Bool {
        size.width >= EditorLayoutMetrics.sidebarMinCanvasWidth
            && size.width > size.height
            && size.width - railWidth - inspectorColumnWidth >= minimumStageWidth
    }

    /// Width of the tool rail that replaces the bottom row on a regular-width
    /// screen. Wide enough for a 24pt glyph over an 11pt label without the
    /// label wrapping ("Background" is the longest), which is what Final Cut
    /// and CapCut both settle on for an iPad rail.
    static let railWidth: CGFloat = 92
    /// One rail cell: the same shape as a toolbar cell, stacked instead of
    /// spread.
    static let railCellHeight: CGFloat = 62
    /// Back · export estimate · Export pill. On a phone this is a band of its
    /// own at the bottom; on a regular-width window those three move into the
    /// top band and this band is not drawn at all.
    static let bottomBarHeight: CGFloat = 50

    /// The top band. It carries the command row on a phone, and the command
    /// row *plus* Back, the read-out and Export on a regular-width window,
    /// which needs more room than the 48pt the phone's row sits in.
    ///
    /// Every editor surveyed — Final Cut for iPad, CapCut, iMovie — puts the
    /// project's primary action in the top bar. ShotDex had it at the bottom,
    /// which is why the contextual panel could cover it.
    static func topBandHeight(usesToolRail: Bool, safeAreaTop: CGFloat) -> CGFloat {
        guard usesToolRail else {
            return max(EditorLayoutMetrics.editorTopBandHeight, safeAreaTop)
        }
        // Derived, not picked: the row's own button plus its inset above and
        // an equal breath below. Written out so it follows the button if the
        // button ever changes, instead of drifting away from the row it is
        // sized for.
        let row = EditorLayoutMetrics.editorFloatingCommandButtonSize(isRegularWidth: true)
        let inset = EditorLayoutMetrics.editorFloatingCommandRowTopInset
        return max(row + inset * 2, safeAreaTop + inset)
    }
    /// Height of the contextual panel (selection + global tools), above the
    /// device's bottom safe inset. It slides over the bars, never displaces them.
    static let sheetHeight: CGFloat = 264
    /// How far the contextual panel reaches above the toolbar and bottom bar.
    /// The stack lifts by this much while the panel is up, so the whole timeline
    /// stays visible above it and the selected band never hides under the panel.
    static var sheetLift: CGFloat { sheetHeight - toolbarHeight - bottomBarHeight }

    /// How far the stack lifts so the panel covers nothing that matters: the
    /// panel's height, less whatever bands it lands on top of. With the tools
    /// in a rail and the project actions in the top band there are none, so
    /// it is the whole panel.
    static func sheetLift(usesToolRail: Bool, showsBottomBar: Bool = true) -> CGFloat {
        sheetHeight
            - (usesToolRail ? 0 : toolbarHeight)
            - (showsBottomBar ? bottomBarHeight : 0)
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
        /// On a window too short to hold the frame, the lanes and the panel
        /// at once, the timeline stands down while the panel is up rather
        /// than every band being squeezed under its own floor.
        var hidesTimeline = false
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
        panelMayDock: Bool = false,
        /// `false` where Back, the read-out and Export have moved into the top
        /// band, so the bottom band is not drawn and costs no height.
        showsBottomBar: Bool = true,
        /// Points the user has dragged the divider to give the timeline more
        /// than its lanes need. Clamped to `timelineExtraRange`.
        timelineExtraHeight: CGFloat = 0
    ) -> StackLayout {
        // The rail takes the tools out of the vertical stack entirely, so the
        // 62pt the row used to cost goes back to the preview and the timeline.
        let toolRow = usesToolRail ? 0 : toolbarHeight
        let natural = canvas.width > 0 ? screen.width * canvas.height / canvas.width : 0
        let extra = min(max(0, timelineExtraHeight), timelineExtraRange.upperBound)
        let wanted = max(timelineMinimumHeight, timelineContentHeight) + extra

        // What the timeline must keep when the preview is clamped. It is the
        // lanes' own height, not the phone's 248: at `Lanes.regular` one
        // overlay and one music lane want 255, so reserving 248 handed the
        // preview 7pt the lanes needed and left them scrolling on every
        // regular-width window. A caller that passes no content height is
        // asking for the old behaviour — the timeline takes the leftover —
        // and gets the floor.
        // (`.greatestFiniteMagnitude` *is* finite, so the sentinel has to be
        // compared for, not tested with `isFinite` — doing that clamped the
        // phone's preview to its 150pt floor.)
        let reserve = timelineContentHeight == .greatestFiniteMagnitude ? timelineMinimumHeight : wanted

        let bottomBand = showsBottomBar ? bottomBarHeight : 0

        func split(lift: CGFloat, dock: CGFloat) -> StackLayout {
            let fixed = bandHeight + previewTimelineGap + toolRow + bottomBand + bottomInset + lift + dock
            let usable = max(0, screen.height - fixed)
            let previewCap = max(previewMinimumHeight, usable - reserve)
            var preview = min(max(natural > 0 ? natural : usable, previewMinimumHeight), previewCap)
            var timeline = max(0, usable - preview)
            if timeline > wanted {
                preview += timeline - wanted
                timeline = wanted
            }
            return StackLayout(preview: preview, timeline: timeline, lift: lift, dockedPanel: dock)
        }

        guard presentsSheet else { return split(lift: 0, dock: 0) }

        // A window can be too short to hold the frame, the lanes and the
        // panel at once. Measured on the iPhone Duo's cover display
        // (382×644): opening the panel there put the preview on its 150pt
        // floor *and* the timeline 108pt under its own — three regions, all
        // broken, to edit one clip. The timeline stands down instead; it is
        // the one of the three the user can get back by deselecting, and a
        // frame they cannot see is worth less than lanes they cannot reach.
        let openable = split(lift: sheetLift(usesToolRail: usesToolRail, showsBottomBar: showsBottomBar), dock: 0)
        if !panelMayDock,
           screen.height <= shortWindowHeight,
           openable.preview <= previewMinimumHeight,
           openable.timeline < timelineMinimumHeight {
            var standDown = split(lift: sheetHeight - (showsBottomBar ? bottomBarHeight : 0) - (usesToolRail ? 0 : toolbarHeight), dock: 0)
            let idle = split(lift: 0, dock: 0)
            standDown.preview = idle.preview
            standDown.timeline = 0
            standDown.hidesTimeline = true
            return standDown
        }

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
        return split(
            lift: sheetLift(usesToolRail: usesToolRail, showsBottomBar: showsBottomBar),
            dock: 0
        )
    }

    /// Shorter than any shipping iPhone — the smallest is 667pt — so this is
    /// an outward-facing cover display, not a phone anyone edits on all day.
    /// An iPhone SE with a vertical project is cramped too, but it is a
    /// device people work on, and taking its timeline away on every
    /// selection is not a trade to make unasked.
    static let shortWindowHeight: CGFloat = 660

    /// How far the divider may be dragged. The ceiling is about five
    /// regular-width lanes' worth — past that the preview is the thing being
    /// starved, and the point of the handle is to let the user choose between
    /// them, not to let them lose one.
    static let timelineExtraRange: ClosedRange<CGFloat> = 0...400

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
        /// The fixed column at the leading edge of the lane stack. A phone
        /// has room for a glyph; a tablet has room for the lane's name, and
        /// a track nobody can name is a track you count rather than read.
        var gutter: CGFloat

        static let compact = Lanes(overlay: 34, video: 66, music: 40, ruler: 26, clipCell: 54, gutter: 30)
        static let regular = Lanes(overlay: 44, video: 104, music: 52, ruler: 30, clipCell: 88, gutter: 64)

        /// A window has to be wide **and tall** for tablet tracks. Width alone
        /// is not enough: the iPhone Duo's inner display is 867pt wide and
        /// 669pt tall, and 255pt of regular lanes on a 669pt window pushes the
        /// preview down to its floor. The editor's sidebar already keys on a
        /// height for the same reason.
        static let minimumHeightForRegularLanes: CGFloat = 750

        static func `for`(size: CGSize) -> Lanes {
            size.width >= EditorLayoutMetrics.sidebarMinCanvasWidth
                && size.height >= minimumHeightForRegularLanes
                ? .regular
                : .compact
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

    /// The export read-out — `9.0s · 1080p · 30fps` — in one place, because
    /// the top band and the bottom bar both draw it and a `String(format:)`
    /// copied into two files drifts.
    ///
    /// `String(format:)` also ignores the locale: its decimal point is always
    /// a dot, where half of Europe writes a comma. The number goes through
    /// `FormatStyle`; `s`, `fps` and the preset name are technical and stay.
    static func exportReadout(duration: Double, presetName: String, frameRate: Int = 30) -> String {
        let seconds = duration.formatted(.number.precision(.fractionLength(1)))
        return "\(seconds)s · \(presetName) · \(frameRate)fps"
    }

    /// The phone's gutter, for anything that has no lane tier to hand.
    static let gutterWidth: CGFloat = Lanes.compact.gutter
    static let gutterIconSize: CGFloat = 20

    /// x of the fixed playhead for a given screen width: centre of the row area.
    static func playheadX(screenWidth: CGFloat, gutter: CGFloat = gutterWidth) -> CGFloat {
        gutter + (screenWidth - gutter) / 2
    }

    /// Half the row area — the content padding at each end so 0s and the last
    /// mark can both sit under the centred playhead.
    static func rowAreaHalfWidth(screenWidth: CGFloat, gutter: CGFloat = gutterWidth) -> CGFloat {
        (screenWidth - gutter) / 2
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
    /// Inspector sheet rows: the typeface button (40) and the Bold/Italic
    /// toggles (36) keep their drawn height — DESIGN.md §308 says a tier-D
    /// control grows its target, not its box — and reach 44 through the hit
    /// shape.
    static let fontButtonHitInset: CGFloat = -2
    static let fontToggleHitInset: CGFloat = -4

    static let commandCellWidth: CGFloat = 52
    static let commandCellHeight: CGFloat = 54
    static let inspectorTitleButton: CGFloat = 30
    static let addMediaButtonWidth: CGFloat = 40
    static let transitionChipSize: CGFloat = 22
}
