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

    /// How tall a scope is drawn in the colour panel.
    ///
    /// A waveform needs enough vertical room that the gap between the black
    /// point and the trace is readable; measured against the panel, 140
    /// leaves the four scopes legible without pushing the primaries wheels
    /// below the fold on a 13" iPad in landscape.
    static let scopeHeight: CGFloat = 140

    /// The same scope on the phone's 264pt band, where 140 would be most of
    /// the panel. Short enough that the controls under it stay on screen,
    /// tall enough that the gap between the black point and the trace is
    /// still readable — which is the whole reason to look at one.
    static let scopeCompactHeight: CGFloat = 96

    // MARK: Desk chrome

    /// A window this wide gets the bands a desktop-shaped editor has and a
    /// phone cannot afford: a labelled viewer header, a transport row between
    /// the frame and the lanes, a whole-project overview strip, and track
    /// headers with controls on them instead of a glyph column.
    ///
    /// The threshold is lower than the tool rail's 700 on purpose. The rail is
    /// a trade — 92pt of width for 62pt of height — and only pays on a
    /// landscape tablet. These bands are not: they cost height a tall window
    /// has going spare, and the window that needs them most is the iPhone
    /// Duo's inner display, which is 669pt wide and never reaches 700.
    static let deskChromeMinimumWidth: CGFloat = 600

    static func usesDeskChrome(size: CGSize) -> Bool {
        size.width >= deskChromeMinimumWidth
    }

    /// Names what is under the playhead and holds the two column toggles.
    static let viewerHeaderHeight: CGFloat = 32
    /// Cut tools, play controls, timecode.
    static let transportBarHeight: CGFloat = 44
    /// The quick-adjust strip under the frame: the one or two values a user
    /// changes constantly, editable without opening the 264pt panel. Resolve
    /// states the reason for its own viewer tool strip plainly — the common
    /// tweak should happen "without ever having to open the inspector".
    static let viewerToolStripHeight: CGFloat = 44
    /// The whole-project strip above the ruler, its own padding included.
    static let timelineOverviewHeight: CGFloat = 22
    static var timelineOverviewBandHeight: CGFloat { timelineOverviewHeight + 8 }

    /// The phone's own transport row: the same playhead commands as the desk
    /// bar, in one row that fits 320pt — the frame-accurate stepping inline,
    /// the rest behind an overflow menu. Shorter than the desk row because it
    /// carries no play pill: the frame has a 56pt play button on it already,
    /// and a tap on the stage pauses.
    static let compactTransportHeight: CGFloat = 40

    /// The look picker in the Filter panel: a 62pt tile, its name, and the
    /// gap between them.
    static let filterStripHeight: CGFloat = 82

    /// The lying-down level meter at the top of the Volume panel: a label
    /// row and two 7pt bars.
    static let levelMeterBarHeight: CGFloat = 46

    /// Total height the chrome above the timeline takes out of the stack.
    ///
    /// A phone is not "no chrome" — it is a narrower shape for the same
    /// commands. It pays for one transport row; a desk window pays for the
    /// header, the wider row and the project overview.
    static func deskChromeHeight(usesDeskChrome: Bool) -> CGFloat {
        usesDeskChrome
            ? viewerHeaderHeight + transportBarHeight + timelineOverviewBandHeight
            : compactTransportHeight
    }

    /// Extra trailing inset for a band that reaches the screen's own edge.
    ///
    /// These screens are **rounded**, and `simctl`'s default screenshot is a
    /// rectangle, so a control parked in a top corner looks right in every
    /// picture and is cut off on the device. Measured with the display mask
    /// on: the corner eats 17pt of width at 14pt down on the iPhone Duo's
    /// inner display (a ~66pt radius) and 4.5pt on a 13" iPad (~36pt). The
    /// Export pill sat 19pt from the Duo's edge at that height — 1.7pt of
    /// daylight, and 0.6pt at its tightest row. This is what buys it back.
    ///
    /// It is spent only when the band really is the trailing-most thing on
    /// screen; with the inspector column open the band's edge is nowhere
    /// near the glass.
    static let displayCornerClearance: CGFloat = 16

    /// Timecode is counted at 30fps: the studio renders at 30 and the frame
    /// step in the transport has to land on the same grid the read-out shows,
    /// or stepping forward one frame moves the last field by two.
    static let timecodeFrameRate: Double = 30

    /// `hh:mm:ss:ff`, the form every NLE's read-out takes. The command band's
    /// pill keeps its shorter `m:ss.t` — it is read while scrubbing with a
    /// thumb, not while matching a cut to a number.
    static func timecode(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let whole = Int(clamped)
        let frames = Int((clamped - Double(whole)) * timecodeFrameRate)
        return String(
            format: "%02d:%02d:%02d:%02d",
            whole / 3600,
            (whole % 3600) / 60,
            whole % 60,
            min(Int(timecodeFrameRate) - 1, frames)
        )
    }

    // MARK: Media pool

    /// The library column beside the stage. 300 holds three 92pt thumbnails
    /// with their dates under them; Resolve's iPad pool, Final Cut's browser
    /// and LumaFusion's library all sit within 20pt of it.
    static let mediaPoolWideWidth: CGFloat = 300
    /// Two columns instead of three, for a window that has the room for a
    /// pool but not for a wide one — the Duo's inner display.
    static let mediaPoolNarrowWidth: CGFloat = 236
    static let mediaPoolHeaderHeight: CGFloat = 34
    /// Media · Stickers · Music. Resolve's top tab row, moved onto the column
    /// it actually drives.
    static let mediaPoolTabStripHeight: CGFloat = 38
    static let mediaPoolToolRowHeight: CGFloat = 32
    static let mediaPoolCellSpacing: CGFloat = 6

    /// What the stage must keep once the pool and the meter have taken their
    /// width. Lower than `minimumStageWidth`, and deliberately: the inspector
    /// is a column the user did not ask for, while the pool is one they opened
    /// and can close again from the same button.
    static let mediaPoolMinimumStageWidth: CGFloat = 330

    static func mediaPoolWidth(size: CGSize) -> CGFloat {
        size.width >= 900 ? mediaPoolWideWidth : mediaPoolNarrowWidth
    }

    /// Whether the window can hold the pool at all. Below this the button is
    /// not drawn, rather than drawn as a control that shrinks the frame to
    /// nothing.
    static func canShowMediaPool(size: CGSize) -> Bool {
        guard usesDeskChrome(size: size) else { return false }
        let taken = mediaPoolWidth(size: size)
            + audioMeterWidth(size: size)
            + (usesToolRail(size: size) ? railWidth : 0)
        return size.width - taken >= mediaPoolMinimumStageWidth
    }

    /// Open from the start only where it costs the frame nothing that matters
    /// — a full-width landscape tablet. Everywhere else it opens on the tap
    /// that asks for it.
    static func mediaPoolOpensByDefault(size: CGSize) -> Bool {
        canShowMediaPool(size: size) && size.width >= 1100
    }

    static func mediaPoolColumnCount(columnWidth: CGFloat) -> Int {
        columnWidth >= mediaPoolWideWidth ? 3 : 2
    }

    static func mediaPoolCellWidth(columnWidth: CGFloat) -> CGFloat {
        let count = CGFloat(mediaPoolColumnCount(columnWidth: columnWidth))
        let gaps = mediaPoolCellSpacing * (count + 1)
        return ((columnWidth - gaps) / count).rounded(.down)
    }

    // MARK: Level meter

    /// The program meter beside the viewer: a dB scale and two channel bars.
    static let audioMeterWideWidth: CGFloat = 50
    /// Bars without the scale, for a window that has no 50pt to spare.
    static let audioMeterNarrowWidth: CGFloat = 32

    static func audioMeterWidth(size: CGSize) -> CGFloat {
        guard usesDeskChrome(size: size) else { return 0 }
        return size.width >= 820 ? audioMeterWideWidth : audioMeterNarrowWidth
    }

    /// A window wide enough for the rail **and** wider than it is tall gets
    /// the column: there the stage is short of height, not width, so the
    /// inspector should cost width. A portrait tablet is the opposite and
    /// docks the panel under the timeline instead.
    /// The floor is a stage no narrower than a phone's screen: below that the
    /// column has taken more than it gave back. The iPhone Duo's inner
    /// display leaves 455pt and clears it — and it is the device the drawer
    /// hurt most, squeezing the frame to 266×150.
    static let minimumStageWidth: CGFloat = 400

    /// Whether the tools stand in a rail down the leading edge instead of a
    /// row under the timeline.
    ///
    /// Same rule as the inspector, and for the same reason: chrome spends the
    /// dimension the stage has to spare. A landscape window is short of
    /// height, so a 92pt rail is the cheap place to put nine tools. A
    /// **portrait** tablet is the opposite — width is what the preview is
    /// starved of and height is what it is drowning in — and a rail there
    /// takes 92pt off the frame while leaving hundreds of points of black
    /// above and below it. Measured on a 1032×1376 iPad: the rail costs the
    /// preview 92pt of width and 61pt of height, and nothing fills the gap.
    /// So portrait puts the tools back in the row under the timeline, where
    /// they cost height the window is not using.
    static func usesToolRail(size: CGSize) -> Bool {
        size.width >= EditorLayoutMetrics.sidebarMinCanvasWidth
            && size.height >= EditorLayoutMetrics.sidebarMinCanvasHeight
            && size.width > size.height
    }

    /// Whether the divider between the frame and the lanes can be dragged.
    ///
    /// This is about the window being a tablet, not about which way it is
    /// turned. A portrait tablet is where the slack actually is — the frame
    /// is capped at its aspect-fit height, so everything past that is black —
    /// and that is exactly where the drag was unavailable while it keyed on
    /// the rail.
    static func usesResizableTimeline(size: CGSize) -> Bool {
        size.width >= EditorLayoutMetrics.sidebarMinCanvasWidth
            && size.height >= EditorLayoutMetrics.sidebarMinCanvasHeight
    }

    /// `otherColumns` is whatever else is standing beside the stage — the
    /// media pool and the level meter. The inspector is the column that gives
    /// way: the pool and the meter are there because the user asked for them,
    /// and an inspector that squeezes the frame to 200pt to show controls for
    /// a clip the user can no longer see is the trade this rule exists to
    /// refuse.
    static func usesInspectorColumn(size: CGSize, otherColumns: CGFloat = 0) -> Bool {
        size.width >= EditorLayoutMetrics.sidebarMinCanvasWidth
            && size.width > size.height
            && size.width - railWidth - inspectorColumnWidth - otherColumns >= minimumStageWidth
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
        timelineExtraHeight: CGFloat = 0,
        /// Viewer header + transport + overview, on a window wide enough for
        /// them. They are fixed bands like the toolbar, so they come out of
        /// the same pot the preview and the timeline divide.
        deskChromeHeight: CGFloat = 0
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
            let fixed = bandHeight + previewTimelineGap + toolRow + bottomBand
                + bottomInset + lift + dock + deskChromeHeight
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

        /// The gutter widened into a track header column, the way every
        /// desk-shaped editor draws one: the lane's number and name, and the
        /// two switches that belong to a track rather than to a clip — lock
        /// and mute. 104 is what a 3-glyph row plus a "A1" badge needs before
        /// the glyphs fall under Apple's 44pt target on a stacked layout.
        static let trackHeaderWidth: CGFloat = 104

        /// Whether the gutter is wide enough to carry controls instead of a
        /// glyph. Same test either way, so the ruler inset, the playhead and
        /// the header all agree on one number.
        var showsTrackControls: Bool { gutter >= Lanes.trackHeaderWidth }

        /// The same lane heights with a track header column in front of them.
        func withTrackHeaders(_ enabled: Bool) -> Lanes {
            guard enabled else { return self }
            var copy = self
            copy.gutter = Lanes.trackHeaderWidth
            return copy
        }

        /// The glyph box in the gutter, and the symbol drawn in it. A 13pt
        /// symbol on a phone held at reading distance is the same angular
        /// size as a 16pt one on a 13" tablet at arm's length — and the wide
        /// gutter has the room, so there is nothing to trade for it.
        var gutterIcon: CGFloat { gutter >= 56 ? 26 : 20 }
        var gutterGlyph: CGFloat { gutter >= 56 ? 16 : 13 }
        /// Whether the lane's name fits under its glyph. The phone's 30pt
        /// column does not hold a word without clipping it.
        var showsLaneNames: Bool { gutter >= 56 }
        var gutterNameFont: CGFloat { 11 }
        /// Height of the whole glyph-plus-name stack, so the gutter can centre
        /// it on the lane rather than centring the glyph and letting the name
        /// hang below the lane's middle.
        var gutterStackHeight: CGFloat {
            showsLaneNames ? gutterIcon + 2 + gutterNameFont + 3 : gutterIcon
        }

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
