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
    /// A selected item's command row (FS-12.04b §2): 64×56 cells, 4 apart,
    /// 10 in from the panel's edges, a 32pt fade at the trailing edge; the
    /// row sits 10 below the panel's top, a 1pt rule 6 under it.
    static let itemCommandCell = CGSize(width: 64, height: 56)
    static let itemCommandGap: CGFloat = 4
    static let itemCommandRowInset: CGFloat = 10
    static let itemCommandFade: CGFloat = 32
    static let itemCommandRowTop: CGFloat = 10
    /// Trim's Start/End to Playhead chips (FS-12.04b §4).
    static let trimChipHeight: CGFloat = 30
    static let trimChipRadius: CGFloat = 8
    /// The speaker at the head of a Volume row (FS-12.04b §5).
    static let muteDisc: CGFloat = 26
    /// A selected clip's edge handles (FS-12.05 §3): 12pt tabs outside the
    /// edges, answering a 44pt-wide drag of which 16 lies outside the clip;
    /// the top 20pt belong to the fade grips.
    static let edgeHandleWidth: CGFloat = 12
    static let edgeHandleTouchWidth: CGFloat = 44
    static let edgeHandleTouchOutside: CGFloat = 16
    static let fadeGripBand: CGFloat = 20
    /// ✕ and ✓ of the session footer (board P2).
    static let sessionButton: CGFloat = 44
    /// The Music panel's title row (board P4).
    static let musicPanelTitleHeight: CGFloat = 46
    /// A cell of the phone's tool row (FS-12.04 §3): five of them, 72×52,
    /// spread over the width from a 6pt inset — on 402pt at x 9, 87, 165…
    static let toolCellSize = CGSize(width: 72, height: 52)
    static let toolRowInset: CGFloat = 6

    /// Leading x of each cell of the phone's tool row on a window `width`
    /// wide: equal columns over the width less the insets, each cell centred.
    static func toolCellXs(width: CGFloat, count: Int = VideoAddTool.bottomRow.count) -> [CGFloat] {
        let column = (width - toolRowInset * 2) / CGFloat(count)
        return (0..<count).map { index in
            toolRowInset + column * CGFloat(index) + (column - toolCellSize.width) / 2
        }
    }

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

    /// The quick-adjust strip under the frame: the one or two values a user
    /// changes constantly, editable without opening the 264pt panel. Resolve
    /// states the reason for its own viewer tool strip plainly — the common
    /// tweak should happen "without ever having to open the inspector".
    static let viewerToolStripHeight: CGFloat = 44
    /// The whole-project strip above the ruler.
    static let timelineOverviewHeight: CGFloat = 22

    /// The phone's own transport row: the same playhead commands as the desk
    /// bar, in one row that fits 320pt — the frame-accurate stepping inline,
    /// the rest behind an overflow menu. Shorter than the desk row because it
    /// carries no play pill: the frame has a 56pt play button on it already,
    /// and a tap on the stage pauses.
    static let compactTransportHeight: CGFloat = 40

    /// The look picker in the Filter panel: a 62pt tile, its name, and the
    /// gap between them.
    static let filterStripHeight: CGFloat = 82
    /// The look-name pill on a clip with a look of its own (FS-12.06c §3).
    static let lookPillHeight: CGFloat = 19

    /// The lying-down level meter at the top of the Volume panel: a label
    /// row and two 7pt bars.
    static let levelMeterBarHeight: CGFloat = 46

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

    /// Timecode is counted at the project's frame rate (30 unless Video
    /// Settings says otherwise): the frame step in the transport lands on
    /// the same grid the read-out shows, or stepping forward one frame
    /// would move the last field by two (FS-12.17b §3).
    static let timecodeFrameRate: Double = 30

    /// `hh:mm:ss:ff`, the form every NLE's read-out takes. The command band's
    /// pill keeps its shorter `m:ss.t` — it is read while scrubbing with a
    /// thumb, not while matching a cut to a number.
    static func timecode(_ seconds: Double, fps: Int = Int(timecodeFrameRate)) -> String {
        let rate = max(1, fps)
        let totalFrames = Int((max(0, seconds) * Double(rate) + 1e-6).rounded(.down))
        let whole = totalFrames / rate
        return String(
            format: "%02d:%02d:%02d:%02d",
            whole / 3600,
            (whole % 3600) / 60,
            whole % 60,
            totalFrames % rate
        )
    }

    /// `m:ss.t` — the short read-out a thumb reads while scrubbing: the
    /// phone's transport and the command band's pill.
    static func compactTimecode(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let whole = Int(clamped)
        let tenths = min(9, Int((clamped - Double(whole)) * 10))
        return String(format: "%d:%02d.%d", whole / 60, whole % 60, tenths)
    }

    /// `m:ss`, rounded to the second — a length read at a glance, as the
    /// iPad's band prints the project's ("0:24").
    static func shortDuration(_ seconds: Double) -> String {
        let whole = Int(max(0, seconds).rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// "0:24 · ~30 MB": the project's length and what it will weigh.
    static func lengthAndSize(duration: Double, bytes: Int64) -> String {
        "\(shortDuration(duration)) · \(VideoExportEstimate.label(bytes))"
    }

    /// The phone transport's read-out (FS-12.07 §2): `0:08.4 / 0:24.0`, the
    /// playhead and the project's length.
    static func compactTransportReadout(playhead: Double, length: Double) -> (playhead: String, length: String) {
        (compactTimecode(playhead), " / " + compactTimecode(length))
    }

    /// The phone transport's buttons: 40pt squares, as the board draws them.
    static let compactTransportButton: CGFloat = 40
    /// Inset of the first and last button from the row's edges.
    static let compactTransportInset: CGFloat = 6

    /// Leading x of each button of the phone transport, in order: Go to
    /// Start, Back a Frame, Forward a Frame, Go to End, More (FS-12.07 §2 —
    /// on 402pt: 6, 46, 276, 316, 356). The read-out takes what is between.
    static func compactTransportButtonXs(width: CGFloat) -> [CGFloat] {
        let button = compactTransportButton
        let inset = compactTransportInset
        return [inset, inset + button,
                width - inset - button * 3, width - inset - button * 2, width - inset - button]
    }

    // MARK: Phone top band (FS-12.07 §2)

    /// The phone's top band: 36pt discs level with the Dynamic Island —
    /// Back, Undo, Redo from the leading edge, Video Settings and Export at
    /// the trailing one, and nothing over the island between them.
    enum PhoneBandItem: CaseIterable {
        case back, undo, redo, videoSettings, export
    }

    static let phoneBandButton: CGFloat = 36
    static let phoneBandTop: CGFloat = 11.5
    /// 16, not the board's 10: at the island's height a disc 10pt in is cut
    /// by the screen's own rounded corner — measured on a masked sim-shot of
    /// iPhone 17, where Back and Export each lost their outer top quarter.
    /// The same clearance the desk band takes (`displayCornerClearance`).
    static let phoneBandInset: CGFloat = displayCornerClearance
    /// Gap between Back, Undo and Redo, and between Video Settings and Export.
    static let phoneBandLeadingGap: CGFloat = 4
    static let phoneBandTrailingGap: CGFloat = 8
    /// The island the row keeps clear: 126pt centred, at the band's height.
    static let dynamicIslandWidth: CGFloat = 126

    /// Where each disc sits on a window `width` wide (402pt: x 16, 56, 96 ·
    /// 306, 350).
    static func phoneBandFrame(_ item: PhoneBandItem, width: CGFloat) -> CGRect {
        let size = phoneBandButton
        let x: CGFloat = switch item {
        case .back: phoneBandInset
        case .undo: phoneBandInset + size + phoneBandLeadingGap
        case .redo: phoneBandInset + (size + phoneBandLeadingGap) * 2
        case .videoSettings: width - phoneBandInset - size * 2 - phoneBandTrailingGap
        case .export: width - phoneBandInset - size
        }
        return CGRect(x: x, y: phoneBandTop, width: size, height: size)
    }

    /// The island's span on a window `width` wide (402pt: 138–264).
    static func dynamicIslandSpan(width: CGFloat) -> ClosedRange<CGFloat> {
        let start = (width - dynamicIslandWidth) / 2
        return start...(start + dynamicIslandWidth)
    }

    /// A pop-up button on the iPad (Motion, Font, Animate In / Out, Ratio).
    static let popUpHeight: CGFloat = 44
    /// The iPad's section titles in the inspector and the dock: Title Case,
    /// 17 semibold in a 28 row (FS-12.03b §1).
    static let deskSectionTitleHeight: CGFloat = 28

    // MARK: Media pool

    /// The iPad pool's insides, in the 320pt panel's own coordinates (board
    /// IL1_Main, FS-12.03b §1): "Library" 20 at (17, 17) in a 44 row with
    /// Select 68 · Search 44 · Hide Media 44 ending 11 short of the edge; the
    /// tabs' segmented 294×36 at y 69, 13 in; the tab's content from 113.
    enum Pool {
        static let inset: CGFloat = 13
        static let headerTop: CGFloat = 17
        static let headerHeight: CGFloat = 44
        static let titleLeading: CGFloat = 17
        static let headerTrailing: CGFloat = 11
        static let selectWidth: CGFloat = 68
        static let segmentedTop: CGFloat = 8
        static let segmentedHeight: CGFloat = 36
        static let contentGap: CGFloat = 8
        /// Add Text, Add Music from Files…: 294×44, radius 12.
        static let buttonHeight: CGFloat = 44
        /// "Fonts You Used", "My Music": Title Case, 15 semibold, 28 tall,
        /// 14 under what is above.
        static let sectionTitleHeight: CGFloat = 28
        static let sectionGap: CGFloat = 14
        /// Rows 302 wide (9 in): fonts 50, songs and In Video 56.
        static let rowInset: CGFloat = 9
        static let fontRowHeight: CGFloat = 50
        static let songRowHeight: CGFloat = 56
        static let stickerGap: CGFloat = 8
    }

    // MARK: Phone bands

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
    /// The Look panel on the phone (FS-12.06c §3, board F5_P_Looks): 340
    /// tall at y 450, standing over the tool row rather than covering it,
    /// so Look stays lit under it.
    static let lookSheetHeight: CGFloat = 340

    // MARK: Beats (FS-12.12 §3)

    /// The beat card's disc.
    static let beatCardDisc: CGFloat = 34
    static let beatCardHeight: CGFloat = 54
    /// Ducking's graph of the whole film (FS-12.13 §3): 370×78 on the
    /// phone, 354×78 on the cover — label 14, the bed's box 50, the clip
    /// strip 8 under a 6pt gap.
    static let duckingGraphHeight: CGFloat = 78
    /// The "−12 dB" pill on the music lane.
    static let duckingPill = CGSize(width: 60, height: 16)
    /// How near a beat a finger must bring an edge or a slider for it to
    /// stick: 8pt, at any zoom (§5).
    static let beatSnapTolerance: CGFloat = 8
    /// "Beat 14 · 0:08.75 · −0.45s" over the ruler while an edge sticks.
    static let beatSnapPill = CGSize(width: 206, height: 26)
    /// Cut to Beat's move over each target: "+0.8s".
    static let cutToBeatPill = CGSize(width: 40, height: 16)
    /// Ticks on a music band: a bar is a 2×12 line under a 6×6 square, a
    /// beat a 1×7 line; on the overview strip 1×8 and 1×5.
    static let barTick = CGSize(width: 2, height: 12)
    static let barTickSquare: CGFloat = 6
    static let beatTick = CGSize(width: 1, height: 7)
    static let overviewBarTick = CGSize(width: 1, height: 8)
    static let overviewBeatTick = CGSize(width: 1, height: 5)

    // MARK: Multi-select (FS-12.11 §3)

    /// The phone's group panel: 260 over the lower lanes, the timeline
    /// left whole underneath so more clips can be tapped above it.
    static let groupSheetHeight: CGFloat = 260
    /// The ring of a clip in the group, and its ✓ badge 5 in from the top
    /// and trailing edges.
    static let groupRing: CGFloat = 2
    static let groupBadge: CGFloat = 19
    static let groupBadgeInset: CGFloat = 5
    /// A dragged group (FS-12.11 §6): the stack under the finger, its count
    /// badge, the drop line and the pill over it.
    static let groupStack = CGSize(width: 131, height: 54)
    static let groupCountBadge: CGFloat = 22
    static let groupDropLine = CGSize(width: 3, height: 82)
    static let groupDropPill = CGSize(width: 100, height: 18)
    /// How near a lane's edge the finger must come for the timeline to
    /// scroll under a dragged group.
    static let groupAutoScrollEdge: CGFloat = 44

    /// How far the phone's stack lifts under the group panel: just enough
    /// for the video lane to clear the panel's top by 8 — zero whenever it
    /// already does, which keeps the 16:9 board's frame at its 226.
    static func groupPanelLift(timelineTop: CGFloat, videoLaneBottom: CGFloat, panelTop: CGFloat) -> CGFloat {
        max(0, timelineTop + videoLaneBottom + 8 - panelTop)
    }
    /// The pill at the head of the lanes: 190×22, 6 past the gutter and 5
    /// under the timeline's top (phone, Duo); 154×26 at the ruler's head on
    /// the iPad (x 212).
    static func groupPill(desk: Bool) -> (size: CGSize, inset: CGFloat, top: CGFloat) {
        desk ? (CGSize(width: 154, height: 26), 4, 1) : (CGSize(width: 190, height: 22), 6, 5)
    }
    /// The iPad's Video Settings popover (FS-12.10 §3, Mac-style board
    /// ES_IL_ExportSettings: 400×548).
    static let videoSettingsPopoverSize = CGSize(width: 400, height: 548)

    /// The iPad's Export Video sheet (FS-12.10b §2, boards IL5_Export,
    /// F8_IL_ExportPresets): 700 wide, 620 tall ready and 572 exporting,
    /// radius 22, 24 in; Close 44 16 from the top and the edge; a foot 44
    /// tall 14 from the bottom with Export 270×44 — or Cancel Export 180×44
    /// and a 360×6 bar. A preset card is 320×72.
    enum ExportSheet {
        static let width: CGFloat = 700
        static let readyHeight: CGFloat = 620
        static let exportingHeight: CGFloat = 572
        static let cornerRadius: CGFloat = 22
        static let inset: CGFloat = 24
        static let titleTop: CGFloat = 20
        static let closeSize: CGFloat = 44
        static let closeTop: CGFloat = 16
        static let closeTrailing: CGFloat = 16
        static let cardSize = CGSize(width: 320, height: 72)
        static let footHeight: CGFloat = 44
        static let footBottom: CGFloat = 14
        static let exportSize = CGSize(width: 270, height: 44)
        static let cancelSize = CGSize(width: 180, height: 44)
        static let progressWidth: CGFloat = 360
    }

    /// The iPad's Video Settings form (FS-12.10 §3, board
    /// ES_IL_ExportSettings): 16 in, labels in 96, 8 to the controls in
    /// 264; Ratio a 150 pop-up; Done 72×44.
    enum SettingsForm {
        static let inset: CGFloat = 16
        static let labelWidth: CGFloat = 96
        static let labelGap: CGFloat = 8
        static let controlWidth: CGFloat = 264
        static let ratioWidth: CGFloat = 150
        static let doneSize = CGSize(width: 72, height: 44)
        static let rowGap: CGFloat = 6
    }
    /// How far the contextual panel reaches above the toolbar and bottom bar.
    /// The stack lifts by this much while the panel is up, so the whole timeline
    /// stays visible above it and the selected band never hides under the panel.
    static var sheetLift: CGFloat { sheetHeight - toolbarHeight - bottomBarHeight }

    /// How far the stack lifts so the panel covers nothing that matters: the
    /// panel's height, less whatever bands it lands on top of. With the tools
    /// in a rail and the project actions in the top band there are none, so
    /// it is the whole panel.
    static func sheetLift(usesToolRail: Bool, showsBottomBar: Bool = true, sheetHeight: CGFloat = sheetHeight) -> CGFloat {
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
        deskChromeHeight: CGFloat = 0,
        /// The panel carries the ✕ · name · ✓ footer in the tool row's place,
        /// so it reaches the row's height higher and the stack lifts that
        /// much more.
        presentsSessionFooter: Bool = false,
        /// How tall the open panel is. The Look panel stands 340 over the
        /// tool row (FS-12.06c §3), others 264 over it.
        sheetHeight: CGFloat = VideoStudioMetrics.sheetHeight
    ) -> StackLayout {
        let footerLift = presentsSessionFooter && !usesToolRail ? toolbarHeight : 0
        // The rail takes the tools out of the vertical stack entirely, so the
        // 62pt the row used to cost goes back to the preview and the timeline.
        let toolRow = usesToolRail ? 0 : toolbarHeight
        let natural = canvas.width > 0 ? screen.width * canvas.height / canvas.width : 0
        let extra = min(max(0, timelineExtraHeight), timelineExtraRange.upperBound)
        let wanted = max(timelineMinimumHeight, timelineContentHeight) + extra

        // What the timeline must keep when the preview is clamped. It is the
        // lanes' own height, not the phone's 248: at `Lanes.desk` one
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
        let openable = split(lift: sheetLift(usesToolRail: usesToolRail, showsBottomBar: showsBottomBar, sheetHeight: sheetHeight) + footerLift, dock: 0)
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
            lift: sheetLift(usesToolRail: usesToolRail, showsBottomBar: showsBottomBar, sheetHeight: sheetHeight) + footerLift,
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

    /// VoiceOver's step on the divider (FS-12.03b §4): 40pt a swipe, kept
    /// inside `timelineExtraRange`.
    static let timelineExtraStep: CGFloat = 40

    static func steppedTimelineExtra(_ current: CGFloat, increment: Bool) -> CGFloat {
        let next = current + (increment ? timelineExtraStep : -timelineExtraStep)
        return min(max(timelineExtraRange.lowerBound, next), timelineExtraRange.upperBound)
    }

    /// The phone's lane geometry, kept as a free function for the layout
    /// tests and for callers that have no width to hand.
    static func timelineContentHeight(overlayLanes: Int, musicLanes: Int) -> CGFloat {
        Lanes.duo.timelineContentHeight(overlayLanes: overlayLanes, musicLanes: musicLanes)
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

    /// Lane geometry for one window class (FS-12.03b §4, FS-12.07 §4).
    ///
    /// Overlay lanes (text and stickers) stack above the video lane; music
    /// lanes stack below it. Three tiers, one per kind of window: the
    /// phone's, the Duo's (both of its displays — the inner one is wide but
    /// 669pt short, and lanes are paid for in height), and the desk's.
    struct Lanes: Equatable, Sendable {
        var overlay: CGFloat
        var video: CGFloat
        var music: CGFloat
        var ruler: CGFloat
        var clipCell: CGFloat
        /// The fixed column at the leading edge of the lane stack.
        var gutter: CGFloat
        /// What that column holds.
        var gutterStyle: GutterStyle
        /// The zoom a timeline opens at on this window (FS-12.03 §2–4).
        var pointsPerSecond: CGFloat
        /// Above the ruler, between the ruler and the first lane, and between
        /// lanes: 8 · 3 · 3 on the phone and the Duo; 0 · 4 · 4 on the iPad,
        /// whose lanes start 32 under the timeline's top (FS-12.03b §4).
        var topPadding: CGFloat = VideoStudioMetrics.timelineTopPadding
        var rulerGap: CGFloat = VideoStudioMetrics.rulerToTracks
        var laneGap: CGFloat = VideoStudioMetrics.laneSpacing
        /// C1, the caption lane above the text lanes (FS-12.14, FS-12.03b
        /// §4): 44 on the iPad, 34 on the Duo; 0 when the project has no
        /// lane or the window has no room for one (the phone: Voice chips).
        var caption: CGFloat = 0

        /// The leading column of the lane stack.
        enum GutterStyle: Equatable, Sendable {
            /// A glyph per lane and nothing to touch: the phone and the
            /// Duo's cover (30pt).
            case glyphs
            /// The Duo's inner display: `T1`/`V1`/`A1` with Lock and Mute
            /// beside them, no names (100pt — FS-12.03b §4).
            case badges
            /// The iPad: a track header card per lane — badge, name, Lock,
            /// Mute (a 192 card in a 208 column).
            case headers
        }

        /// FS-12.07 §4 — taken up by the phone layout when its stack is
        /// rebuilt (tools plan, task 43); until then the phone draws `duo`.
        static let phone = Lanes(
            overlay: 40, video: 80, music: 46, ruler: 33, clipCell: 60,
            gutter: 30, gutterStyle: .glyphs, pointsPerSecond: 55
        )
        static let duo = Lanes(
            overlay: 34, video: 66, music: 40, ruler: 33, clipCell: 54,
            gutter: 30, gutterStyle: .glyphs, pointsPerSecond: 55
        )
        static let desk = Lanes(
            overlay: 44, video: 104, music: 52, ruler: 28, clipCell: 88,
            gutter: VideoStudioDeskGeometry.overviewLeading, gutterStyle: .headers, pointsPerSecond: 70,
            topPadding: 0, rulerGap: 4, laneGap: 4
        )

        /// The iPad's track header (FS-12.03b §4, board IL1_Main): a card
        /// 192 wide, 8 in, radius 8 — badge 30×22 8 in, the name 15 in 62,
        /// Lock and Mute 40×44 ending 4 short of the card's edge. The lanes
        /// start 8 after it, at 208.
        static let trackHeaderWidth: CGFloat = VideoStudioDeskGeometry.trackHeaderWidth
        static let trackHeaderCardInset: CGFloat = 8
        static let trackHeaderCardWidth: CGFloat = 192
        static let trackHeaderBadge = CGSize(width: 30, height: 22)
        static let trackHeaderNameWidth: CGFloat = 62
        static let trackHeaderSwitch = CGSize(width: 40, height: 44)

        /// The Duo inner display's badge column: margin 6 · badge 26 · gap 4
        /// · Lock 28 · gap 4 · Mute 28 · margin 4 (FS-12.03b §4).
        static let badgeColumnWidth: CGFloat = 100
        static let badgeColumnMargin: CGFloat = 6
        static let badgeWidth: CGFloat = 26
        static let badgeGap: CGFloat = 4
        static let badgeDisc: CGFloat = 28
        static let badgeGlyph: CGFloat = 13
        /// Each switch answers 32pt wide by the lane's height.
        static let badgeTouchWidth: CGFloat = 32

        /// Leading x of the Lock and Mute discs in the badge column.
        static var badgeLockX: CGFloat { badgeColumnMargin + badgeWidth + badgeGap }
        static var badgeMuteX: CGFloat { badgeLockX + badgeDisc + badgeGap }

        /// The tier a window of `windowClass` draws its lanes at.
        static func `for`(_ windowClass: VideoStudioWindowClass) -> Lanes {
            switch windowClass {
            case .phone, .duoCover:
                return .duo
            case .duoInner:
                // The ruler from the timeline's top, lanes 4 under it
                // (board DI1_Main: T1 at 425 + 37).
                var lanes = Lanes.duo
                lanes.gutter = badgeColumnWidth
                lanes.gutterStyle = .badges
                lanes.topPadding = 0
                lanes.rulerGap = 4
                return lanes
            case .iPadLandscape:
                return .desk
            case .iPadPortrait:
                var lanes = Lanes.desk
                lanes.pointsPerSecond = 60
                return lanes
            }
        }

        /// Whether the leading column carries switches instead of a glyph.
        var showsTrackControls: Bool { gutterStyle != .glyphs }

        /// The glyph box in the gutter, and the symbol drawn in it.
        var gutterIcon: CGFloat { 20 }
        var gutterGlyph: CGFloat { 13 }

        /// The caption lane's height on this tier when the project has one.
        var captionLaneHeight: CGFloat { gutterStyle == .headers ? 44 : 34 }

        /// This tier with the caption lane shown, or not.
        func showingCaptions(_ shows: Bool) -> Lanes {
            var lanes = self
            lanes.caption = shows ? captionLaneHeight : 0
            return lanes
        }

        var captionLaneTop: CGFloat { laneAreaTop }

        /// What the caption lane takes above the first text lane.
        private var captionBlock: CGFloat { caption > 0 ? caption + laneGap : 0 }

        func overlayLaneTop(_ lane: Int) -> CGFloat {
            laneAreaTop + captionBlock + CGFloat(lane) * (overlay + laneGap)
        }

        func videoLaneTop(overlayLanes: Int) -> CGFloat {
            overlayLaneTop(max(0, overlayLanes))
        }

        func musicLaneTop(_ lane: Int, overlayLanes: Int) -> CGFloat {
            videoLaneTop(overlayLanes: overlayLanes)
                + video + laneGap
                + CGFloat(lane) * (music + laneGap)
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
            topPadding + ruler + rulerGap
                + laneContentHeight(overlayLanes: overlayLanes, musicLanes: musicLanes)
                + scrollbarHeight
        }

        /// Height of the scrolling viewport under the pinned ruler.
        func laneViewportHeight(timelineHeight: CGFloat) -> CGFloat {
            timelineHeight - topPadding - ruler - rulerGap - scrollbarHeight - 2
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
    static let gutterWidth: CGFloat = Lanes.duo.gutter

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

    /// From 18 — the Duo cover's multi-select zoom (FS-12.11 AC-14, D-6) —
    /// to 160; the bounds are `TimelineZoomMath`'s (Frame zoom raises the
    /// ceiling, FS-12.17 §6).
    static let pointsPerSecondRange: ClosedRange<CGFloat> = TimelineZoomMath.floor...TimelineZoomMath.standardCeiling

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

    static let inspectorTitleButton: CGFloat = 30
    static let addMediaButtonWidth: CGFloat = 40
    static let transitionChipSize: CGFloat = 22
}

extension VideoStudioMetrics {
    /// "Frame zoom · 1 frame = 12 pt" (FS-12.17 §6, board F6_P_FineScrub):
    /// 270×26, radius 13, 276 under the timeline's top.
    static let frameZoomPill = CGSize(width: 270, height: 26)
    static let frameZoomPillTop: CGFloat = 276

    /// The frame trim's geometry (FS-12.17 §4–5, boards F6_P_PreciseTrim,
    /// F6_DI_TouchTrim, F6_IP_PencilTrim, F6_DC_PreciseTrim).
    enum FrameTrim {
        /// ‹ −1 Frame · time · +1 Frame ›, radius 24.
        static let pill = CGSize(width: 248, height: 48)
        /// Its two buttons, radius 12.
        static let pillButton = CGSize(width: 76, height: 40)
        /// The pill floats this far above the floor of the area it is in:
        /// the phone's footer (y 790 → pill at 728), the Duo cover's
        /// timeline foot (644 → 582).
        static let pillGap: CGFloat = 14
        /// The loupe: Ø124 on the phone, 140 on the Duo's inner display, 152
        /// on the iPad (Mac-style canvas).
        static let loupeDiameterPhone: CGFloat = 124
        static let loupeDiameterDuoInner: CGFloat = 140
        static let loupeDiameterIPad: CGFloat = 152
        /// From the loupe's foot to the clip's top: 2 on the phone, 25 on
        /// the Duo's inner display, 20 on the iPad.
        static let loupeGapPhone: CGFloat = 2
        static let loupeGapDuoInner: CGFloat = 25
        static let loupeGapIPad: CGFloat = 20
        /// Ten frames inside it: 13pt slices, 14 apart.
        static let loupeSlice: CGFloat = 13
        static let loupeStep: CGFloat = 14
        /// At a screen edge the loupe slides in and stops this far from it.
        static let loupeEdgeInset: CGFloat = 8
        /// "Last frame · 0:09.07" over the viewer: 22 on the phone, 24 on
        /// the Duo's inner display, 10 in from the viewer's corner.
        static let viewerLabelHeightPhone: CGFloat = 22
        static let viewerLabelHeightDuoInner: CGFloat = 24
        static let viewerLabelInset: CGFloat = 10

        /// The pill's origin, centred across `width`, its foot `pillGap`
        /// above `floor`.
        static func pillOrigin(width: CGFloat, floor: CGFloat) -> CGPoint {
            CGPoint(x: ((width - pill.width) / 2).rounded(), y: floor - pillGap - pill.height)
        }

        /// The loupe's frame: centred on the edge's x, its foot `gap` above
        /// the clip's top — slid in to stay `loupeEdgeInset` inside
        /// `bounds` at either side and at the top.
        static func loupeFrame(edgeX: CGFloat, clipTop: CGFloat, diameter: CGFloat, gap: CGFloat, bounds: CGRect) -> CGRect {
            var x = edgeX - diameter / 2
            x = min(max(x, bounds.minX + loupeEdgeInset), bounds.maxX - loupeEdgeInset - diameter)
            let y = max(bounds.minY + loupeEdgeInset, clipTop - gap - diameter)
            return CGRect(x: x, y: y, width: diameter, height: diameter)
        }
    }
}
