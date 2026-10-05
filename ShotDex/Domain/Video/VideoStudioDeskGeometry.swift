import CoreGraphics

/// Where every band of the Video Studio sits on a window that is not a phone
/// (FS-12.03, FS-12.03b, FS-12.07b) — one pure function per window class,
/// each returning the rect of every band in window coordinates.
///
/// Each class has exactly one band that flexes; the rest are fixed. iPad
/// landscape: the stage (the timeline keeps its 354pt floor). That is why
/// each layout is a function with a numbered test instead of one general
/// stack that tries to suit every window.
///
/// The phone's stack is `VideoStudioMetrics.stackLayout`, owned by the phone
/// plan; nothing here draws a phone.
enum VideoStudioDeskGeometry {
    // MARK: iPad toolbar (FS-12.03 §2, the Mac-style canvas of 2026-10-04)

    /// The top 24pt are the system's status bar; the row of glass capsules
    /// runs y 24–68, 12 apart.
    static let toolbarTop: CGFloat = 24
    static let toolbarHeight: CGFloat = 44
    static let capsuleGap: CGFloat = 12
    /// The toolbar's leading and trailing margin, pool shut.
    static let toolbarInset: CGFloat = 16
    /// Export: a 124×44 pill, radius `r-export` 19.
    static let exportSize = CGSize(width: 124, height: 44)
    static let exportRadius: CGFloat = 19
    /// The capsules after the title, right to left from Export.
    static let viewToggleCapsuleWidth: CGFloat = 92
    static let settingsCapsuleWidth: CGFloat = 226
    static let historyCapsuleWidth: CGFloat = 140
    /// The buttons inside a capsule: 40, in a 44 capsule.
    static let capsuleButton: CGFloat = 40
    /// The title's leading edge from the last leading capsule.
    static let titleGap: CGFloat = 12

    // MARK: Pool and inspector

    /// The library: a floating glass panel 320×568 at (8, 8), radius 22 —
    /// it stands beside the toolbar, not under it. iPad only.
    static let poolFrame = CGRect(x: 8, y: 8, width: 320, height: 568)
    static let poolCornerRadius: CGFloat = 22
    /// What the stage leaves between the pool and itself.
    static let poolGap: CGFloat = 8
    /// The pool opens by itself only this wide, and only if the stage keeps
    /// `poolMinimumStageWidth` beside it (FS-12.03b §1).
    static let poolOpensByDefaultWidth: CGFloat = 1100
    static let poolMinimumStageWidth: CGFloat = 330
    /// The iPad inspector: 360, flush right, from the window's top edge —
    /// the toolbar's trailing capsules sit over its head and its content
    /// starts at 80. Look when nothing is selected.
    static let inspectorWidth: CGFloat = 360
    static let inspectorContentTop: CGFloat = 80
    /// The selected item's ✕ · name · ✓ at the inspector's foot: 64, with
    /// 44pt discs (FS-12.03 §2).
    static let inspectorFooterHeight: CGFloat = 64
    static let deskFooterButton: CGFloat = 44
    /// ✕ and ✓ 16 in from the foot's edges (17 from the column's, past its
    /// hairline).
    static let footerInset: CGFloat = 16
    /// The selected item's command row in the inspector: 13 in, at the
    /// content's top (y 80).
    static let inspectorCommandInset: CGFloat = 13

    // MARK: Stage and the rows under it

    /// The stage starts 12 under the toolbar.
    static let stageTop: CGFloat = 80
    /// The frame's box inside the stage: 16 in from the leading edge; on the
    /// trailing side the meter, 10 after the frame, and 6 more.
    static let stageInset: CGFloat = 16
    static let meterGap: CGFloat = 10
    static let meterTrailingGap: CGFloat = 6
    /// The level meter beside the frame: two bars and a dB scale, as tall as
    /// the frame (FS-12.03b §3).
    static let meterWidth: CGFloat = 44
    /// Portrait has no columns beside the frame: it starts 28 in and the
    /// meter ends 18 short of the window's edge.
    static let portraitFrameLeading: CGFloat = 28
    static let portraitMeterTrailing: CGFloat = 18
    /// The play row under the frame: the name under the playhead, the six
    /// play buttons (Play a 48 disc), Before and After at the frame's
    /// trailing edge (FS-12.03b §2).
    static let playRowHeight: CGFloat = 48
    static let playRowGap: CGFloat = 10
    static let portraitPlayRowGap: CGFloat = 6
    /// The six play buttons, as one group: 44 · 44 · 48 · 44 · 44, 10, 44.
    static let playGroupWidth: CGFloat = 278
    /// Before and After: 44, its leading edge on the frame's trailing one.
    static let beforeAfterButton: CGFloat = 44
    /// Under the play row: 6 to the bottom of the inspector, then 12 in
    /// which the divider's grabber sits, then the timeline's tool row.
    static let inspectorBelowPlayRow: CGFloat = 6
    static let toolRowGap: CGFloat = 12
    static let portraitToolRowGap: CGFloat = 14
    /// The timeline's tool row: the playhead edits, the markers, the
    /// timecode and Fit, 44 buttons, the window's whole width.
    static let toolRowHeight: CGFloat = 44
    static let toolRowInset: CGFloat = 16
    /// The divider's grabber: 36×4, 10 above the tool row.
    static let dividerSize = CGSize(width: 36, height: 4)
    static let dividerAboveToolRow: CGFloat = 10
    /// The whole-project strip: 4 under the tool row, 22 tall, 6 above the
    /// timeline; from where the lanes start to 16 short of the edge.
    static let overviewHeight: CGFloat = 22
    static let overviewGap: CGFloat = 4
    static let overviewBelowGap: CGFloat = 6
    static let overviewTrailingInset: CGFloat = 16
    /// The iPad's track header column: a 192 card 8 in (FS-12.03b §4).
    static let trackHeaderWidth: CGFloat = 200
    /// Where the lanes, and so the overview, start: 8 after the headers.
    static let overviewLeading: CGFloat = 208
    /// iPad landscape: the timeline never gets less than this.
    static let landscapeTimelineFloor: CGFloat = 360
    /// The least the stage keeps when the divider is dragged up.
    static let stageFloor: CGFloat = 200
    /// How far the divider may give the timeline more than it needs.
    static let timelineExtraRange: ClosedRange<CGFloat> = 0...400

    // MARK: iPad portrait dock (FS-12.03 §3)

    /// The controls under the timeline: fixed, 324 tall, the whole width.
    static let dockHeight: CGFloat = 324
    /// "Look · Whole video" and the four add buttons, 104×44, 8 apart.
    static let dockTitleHeight: CGFloat = 46
    static let dockButtonSize = CGSize(width: 104, height: 44)
    static let dockButtonGap: CGFloat = 8
    static let dockButtonRadius: CGFloat = 12
    static let dockInset: CGFloat = 16
    static let dockCornerRadius: CGFloat = 16
    /// The dock's three columns, at their board width on a 1032 window: 312,
    /// 32 apart, a rule in the middle of each gap.
    static let dockColumnWidth: CGFloat = 312
    static let dockColumnGap: CGFloat = 32
    /// Under three of these a column is too narrow to read: two, scrolling.
    static let dockColumnMinimum: CGFloat = 200
    /// A selected item in the dock: the command row 9 below its top, three
    /// columns of controls from 73, the ✕ · name · ✓ foot (64) at 260
    /// (FS-12.03 §3).
    static let dockCommandRowTop: CGFloat = 9
    static let dockParamTop: CGFloat = 73
    static let dockParamHeight: CGFloat = 187
    static let dockFooterTop: CGFloat = 260
    static let dockFooterHeight: CGFloat = 64
    /// ✕ and ✓ at the foot of the Duo inner display's row.
    static let footerButton: CGFloat = 40

    /// Where the selected item's foot sits in the landscape inspector: 64
    /// at its bottom.
    static func inspectorFooter(in inspector: CGRect) -> CGRect {
        CGRect(x: inspector.minX, y: inspector.maxY - inspectorFooterHeight, width: inspector.width, height: inspectorFooterHeight)
    }

    static func dockFooter(in dock: CGRect) -> CGRect {
        CGRect(x: dock.minX, y: dock.minY + dockFooterTop, width: dock.width, height: dockFooterHeight)
    }

    /// The least the portrait timeline keeps, whatever the frame wants.
    static let portraitTimelineFloor: CGFloat = 200

    /// How the dock's width splits into columns: three on any window at
    /// least three minimum columns wide (Split View's 639 included), two
    /// and a horizontal scroll under that.
    static func dockColumnCount(width: CGFloat) -> Int {
        width >= dockColumnMinimum * 3 ? 3 : 2
    }

    /// One column's width: the dock less its margins and the gaps, shared
    /// equally — 312 on a 1032 window.
    static func dockColumnWidth(width: CGFloat) -> CGFloat {
        let count = CGFloat(dockColumnCount(width: width))
        let shared = (width - dockInset * 2 - dockColumnGap * (count - 1)) / count
        return count == 3 ? shared : max(dockColumnMinimum, shared)
    }

    // MARK: Duo inner display (FS-12.03 §4)

    /// The column beside the frame: the frame is limited by the height, so
    /// these 264pt cost it nothing.
    static let duoColumnWidth: CGFloat = 264
    static let duoTransportHeight: CGFloat = 40
    static let duoTimelineHeight: CGFloat = 188
    static let duoBottomRowHeight: CGFloat = 56
    /// Export at the right end of the bottom row: a pill 40 tall.
    static let duoExportHeight: CGFloat = 40
    /// Back · Undo · Redo · Show original over the frame: 36pt discs on
    /// black 55 %, 8 apart, from (16, 12).
    static let duoDisc: CGFloat = 36
    static let duoDiscGap: CGFloat = 8
    static let duoDiscOrigin = CGPoint(x: 16, y: 12)
    /// The bottom row's five tools: 72×50, 4 apart, from x 40.
    static let duoToolCell = CGSize(width: 72, height: 50)
    static let duoToolGap: CGFloat = 4
    static let duoToolLeading: CGFloat = 40
    /// The row's right-hand group ends at x 907 on a 951pt window — 44 in,
    /// clear of the rounded corner.
    static let duoRowTrailingInset: CGFloat = 44
    /// While an item is selected the right group is ✕ · name · ✓, x 620–907.
    static let duoSessionGroupWidth: CGFloat = 287

    // MARK: Duo cover display (FS-12.07b)

    /// The trailing strip iOS keeps for its vertical status bar — the
    /// studio hides the status bar, so the strip is the tools'.
    static let coverRailWidth: CGFloat = 84
    /// The rail's top: the camera hole and the corner. Nothing to touch.
    static let coverCapHeight: CGFloat = 72
    /// Nothing that takes a touch below this: the bottom corner begins
    /// ~612 and the last 34pt are the home indicator.
    static let coverTouchFloor: CGFloat = 600
    /// The home indicator strip under the timeline.
    static let coverHomeIndicator: CGFloat = 34
    /// Back · Undo · Redo: 34pt discs on white 10 %, 6 apart, from (10, 7).
    static let coverDisc: CGFloat = 34
    static let coverDiscGap: CGFloat = 6
    static let coverDiscOrigin = CGPoint(x: 10, y: 7)
    /// The frame's box: the content width at 16:9 (382×215), from y 45.
    static let coverStageTop: CGFloat = 45
    static let coverTransportHeight: CGFloat = 40
    /// The five tools: 64×56, stacked from y 80, 10 in from the rail's edge.
    static let coverToolCell = CGSize(width: 64, height: 56)
    static let coverToolTop: CGFloat = 80
    static let coverToolInset: CGFloat = 10
    /// A selected item's name: 76×56 at y 440, 4 in.
    static let coverNameTop: CGFloat = 440
    static let coverNameSize = CGSize(width: 76, height: 56)
    static let coverNameInset: CGFloat = 4
    /// Video Settings / ✕ at y 504 and Export / ✓ at y 556: 44pt discs,
    /// 20 in — where the thumb of the hand holding the phone lands.
    static let coverActionDisc: CGFloat = 44
    static let coverActionInset: CGFloat = 20
    static let coverUpperActionTop: CGFloat = 504
    static let coverLowerActionTop: CGFloat = 556
    /// The panel's grabber: 36×5, 6 below its top.
    static let coverGrabber = CGSize(width: 36, height: 5)
    /// A selected item (FS-12.07b §4): the overview strip at 306 (12 in,
    /// 22 tall), the panel from 334; pulled down, the panel is 78 —
    /// grabber and command row — at the bottom, 566–644.
    static let coverOverviewTop: CGFloat = 306
    static let coverOverviewInset: CGFloat = 12
    static let coverItemPanelTop: CGFloat = 334
    static let coverCollapsedPanelHeight: CGFloat = 78

    /// The rect of every band. Nil where the window class has no such band.
    struct Frames: Equatable {
        /// The row across the top: the iPad's toolbar of capsules (y 24–68),
        /// the Duo cover's three discs.
        var band: CGRect
        var pool: CGRect?
        /// The area the frame is fitted into (black around the frame).
        var stage: CGRect
        /// The project's frame, aspect-fitted into the stage.
        var frame: CGRect
        /// The box the frame is fitted into, where it is not the whole stage:
        /// the iPad's, inset for the meter beside it.
        var frameBox: CGRect? = nil
        var meter: CGRect?
        var inspector: CGRect?
        /// The transport: the iPad's timeline tool row, the Duo's row of
        /// fifteen, the cover's compact one.
        var transport: CGRect
        /// The iPad's play row under the frame (FS-12.03b §2), and the x its
        /// six play buttons are centred on.
        var playRow: CGRect? = nil
        var playGroupMidX: CGFloat? = nil
        /// The iPad's grabber between the stage and the timeline.
        var divider: CGRect? = nil
        var overview: CGRect?
        var timeline: CGRect
        var dock: CGRect?
        var bottomRow: CGRect? = nil
        /// The Duo cover's trailing rail.
        var rail: CGRect? = nil
        /// A tool's panel (Music, Look, Media) where it covers the timeline.
        var toolPanel: CGRect? = nil
    }

    /// The rail's own rects, in window coordinates (FS-12.07b §3).
    struct CoverRail: Equatable {
        var cap: CGRect
        var tools: [CGRect]
        var name: CGRect
        var upperAction: CGRect
        var lowerAction: CGRect
    }

    /// What a layout needs to know beyond the window.
    struct Input: Equatable {
        var window: CGSize
        /// The project's canvas, in any unit — only its ratio is read.
        var canvas: CGSize
        var isPoolOpen: Bool
        var isInspectorOpen: Bool
        /// What the lanes in this project need to show without scrolling.
        var laneNeed: CGFloat = 0
        /// Points the divider has given the timeline beyond its need.
        var timelineExtra: CGFloat = 0
    }

    /// Whether the pool opens by itself on a window this wide: only where
    /// it costs the frame nothing that matters.
    static func poolOpensByDefault(windowWidth: CGFloat) -> Bool {
        windowWidth >= poolOpensByDefaultWidth
    }

    /// Whether the pool can open at all with the inspector as it is: in
    /// landscape the stage has to keep `poolMinimumStageWidth` for the frame
    /// beside it. In portrait the pool floats over the frame, so it always can.
    static func canOpenPool(windowWidth: CGFloat, isInspectorOpen: Bool) -> Bool {
        let stage = windowWidth - (poolFrame.maxX + poolGap) - (isInspectorOpen ? inspectorWidth : 0)
        return frameBoxWidth(stageWidth: stage) >= poolMinimumStageWidth
    }

    /// The frame's box in a landscape stage this wide: the inset before it,
    /// the meter and its gaps after.
    static func frameBoxWidth(stageWidth: CGFloat) -> CGFloat {
        stageWidth - stageInset - meterGap - meterWidth - meterTrailingGap
    }

    /// Where the toolbar's leading capsules start: past the pool when it is
    /// open (it stands beside the toolbar), at the margin when it is shut.
    static func toolbarLeading(isPoolOpen: Bool) -> CGFloat {
        isPoolOpen ? poolFrame.maxX + toolbarInset : toolbarInset
    }

    /// The timeline's tool row and everything under it, from the bottom up:
    /// the timeline (`height` tall), the overview 6 above it, the tool row
    /// 4 above that.
    private static func lowerBands(window: CGSize, timelineHeight: CGFloat) -> (toolRow: CGRect, overview: CGRect, timeline: CGRect) {
        let timeline = CGRect(x: 0, y: window.height - timelineHeight, width: window.width, height: timelineHeight)
        let overview = CGRect(
            x: overviewLeading,
            y: timeline.minY - overviewBelowGap - overviewHeight,
            width: window.width - overviewLeading - overviewTrailingInset,
            height: overviewHeight
        )
        let toolRow = CGRect(x: 0, y: overview.minY - overviewGap - toolRowHeight, width: window.width, height: toolRowHeight)
        return (toolRow, overview, timeline)
    }

    private static func divider(above toolRow: CGRect, windowWidth: CGFloat) -> CGRect {
        CGRect(
            x: ((windowWidth - dividerSize.width) / 2).rounded(),
            y: toolRow.minY - dividerAboveToolRow,
            width: dividerSize.width,
            height: dividerSize.height
        )
    }

    private static func toolbar(windowWidth: CGFloat) -> CGRect {
        CGRect(x: 0, y: toolbarTop, width: windowWidth, height: toolbarHeight)
    }

    // MARK: iPad landscape (FS-12.03 §2, board IL1)

    /// The toolbar's capsules across the top; the pool floating at (8, 8);
    /// the stage between it and the 360 inspector, which runs from the
    /// window's top edge; the play row under the frame; then the tool row,
    /// the overview and the timeline the whole width. The stage flexes; the
    /// timeline keeps 360.
    static func iPadLandscape(_ input: Input) -> Frames {
        let width = input.window.width
        let height = input.window.height
        let extra = min(max(0, input.timelineExtra), timelineExtraRange.upperBound)
        // Everything above the timeline that does not flex, with the stage
        // at its floor: what the timeline may grow into.
        let fixedAbove = stageTop + stageFloor + playRowGap + playRowHeight + inspectorBelowPlayRow
            + toolRowGap + toolRowHeight + overviewGap + overviewHeight + overviewBelowGap
        let timelineHeight = min(
            max(landscapeTimelineFloor, input.laneNeed) + extra,
            max(landscapeTimelineFloor, height - fixedAbove)
        )
        let (toolRow, overview, timeline) = lowerBands(window: input.window, timelineHeight: timelineHeight)
        let upperBottom = toolRow.minY - toolRowGap
        let inspector = input.isInspectorOpen
            ? CGRect(x: width - inspectorWidth, y: 0, width: inspectorWidth, height: upperBottom)
            : nil
        let pool = input.isPoolOpen ? poolFrame : nil
        let stageX = pool.map { $0.maxX + poolGap } ?? 0
        let playRowTop = upperBottom - inspectorBelowPlayRow - playRowHeight
        let stage = CGRect(
            x: stageX, y: stageTop,
            width: (inspector?.minX ?? width) - stageX,
            height: playRowTop - playRowGap - stageTop
        )
        let box = CGRect(x: stage.minX + stageInset, y: stage.minY, width: frameBoxWidth(stageWidth: stage.width), height: stage.height)
        let frame = fit(input.canvas, in: box)
        return Frames(
            band: toolbar(windowWidth: width),
            pool: pool,
            stage: stage,
            frame: frame,
            frameBox: box,
            meter: CGRect(x: frame.maxX + meterGap, y: frame.minY, width: meterWidth, height: frame.height),
            inspector: inspector,
            transport: toolRow,
            playRow: CGRect(x: box.minX, y: playRowTop, width: frame.maxX + beforeAfterButton - box.minX, height: playRowHeight),
            playGroupMidX: stage.midX,
            divider: divider(above: toolRow, windowWidth: width),
            overview: overview,
            timeline: timeline,
            dock: nil
        )
    }

    // MARK: iPad portrait (FS-12.03 §3, board IP1)

    /// The toolbar as in landscape; the frame takes the width less the meter
    /// and its aspect-fit height; the play row, the tool row, the overview,
    /// the timeline — the band that flexes — and the 324pt dock. The pool,
    /// when open, floats over the frame.
    static func iPadPortrait(_ input: Input) -> Frames {
        let width = input.window.width
        let height = input.window.height
        let dockHeight = input.isInspectorOpen ? Self.dockHeight : 0
        let boxWidth = width - portraitFrameLeading - meterGap - meterWidth - portraitMeterTrailing
        // The frame is limited by the width; whatever the timeline needs
        // below it caps the height, and the divider takes from the frame.
        let below = portraitPlayRowGap + playRowHeight + portraitToolRowGap + toolRowHeight
            + overviewGap + overviewHeight + overviewBelowGap
        let timelineMinimum = max(portraitTimelineFloor, input.laneNeed)
        let stageCap = height - stageTop - below - timelineMinimum - dockHeight
        let natural = input.canvas.width > 0 ? (boxWidth * input.canvas.height / input.canvas.width).rounded() : stageCap
        let extra = min(max(0, input.timelineExtra), timelineExtraRange.upperBound)
        let stageHeight = max(stageFloor, min(natural, stageCap) - extra)
        let box = CGRect(x: portraitFrameLeading, y: stageTop, width: boxWidth, height: stageHeight)
        let frame = fit(input.canvas, in: box)
        let playRow = CGRect(
            x: box.minX, y: box.maxY + portraitPlayRowGap,
            width: frame.maxX + beforeAfterButton - box.minX, height: playRowHeight
        )
        let toolRow = CGRect(x: 0, y: playRow.maxY + portraitToolRowGap, width: width, height: toolRowHeight)
        let overview = CGRect(
            x: overviewLeading, y: toolRow.maxY + overviewGap,
            width: width - overviewLeading - overviewTrailingInset, height: overviewHeight
        )
        let timelineTop = overview.maxY + overviewBelowGap
        let dockTop = height - dockHeight
        let timeline = CGRect(x: 0, y: timelineTop, width: width, height: max(0, dockTop - timelineTop))
        return Frames(
            band: toolbar(windowWidth: width),
            pool: input.isPoolOpen ? poolFrame : nil,
            stage: CGRect(x: 0, y: stageTop, width: width, height: stageHeight),
            frame: frame,
            frameBox: box,
            meter: CGRect(x: frame.maxX + meterGap, y: frame.minY, width: meterWidth, height: frame.height),
            inspector: nil,
            transport: toolRow,
            playRow: playRow,
            playGroupMidX: frame.midX,
            divider: divider(above: toolRow, windowWidth: width),
            overview: overview,
            timeline: timeline,
            dock: input.isInspectorOpen ? CGRect(x: 0, y: dockTop, width: width, height: dockHeight) : nil
        )
    }

    // MARK: Duo inner (FS-12.03 §4, board DI1)

    /// Frame and the 264 column side by side from the top; then transport
    /// 40, timeline 188 and the bottom row 56 across the width. Height is
    /// what this window lacks, so the frame is the band that flexes:
    /// 385 + 40 + 188 + 56 = 669.
    static func duoInner(_ input: Input) -> Frames {
        let width = input.window.width
        let height = input.window.height
        let bottomRow = CGRect(x: 0, y: height - duoBottomRowHeight, width: width, height: duoBottomRowHeight)
        let timeline = CGRect(x: 0, y: bottomRow.minY - duoTimelineHeight, width: width, height: duoTimelineHeight)
        let transport = CGRect(x: 0, y: timeline.minY - duoTransportHeight, width: width, height: duoTransportHeight)
        let column = CGRect(x: width - duoColumnWidth, y: 0, width: duoColumnWidth, height: transport.minY)
        let stage = CGRect(x: 0, y: 0, width: column.minX, height: transport.minY)
        return Frames(
            band: .zero,
            pool: nil,
            stage: stage,
            frame: fit(input.canvas, in: stage),
            meter: nil,
            inspector: column,
            transport: transport,
            overview: nil,
            timeline: timeline,
            dock: nil,
            bottomRow: bottomRow
        )
    }

    /// Where the four discs over the Duo's frame sit: Back, Undo, Redo,
    /// Show original.
    static func duoDiscFrames() -> [CGRect] {
        (0..<4).map { index in
            CGRect(
                x: duoDiscOrigin.x + CGFloat(index) * (duoDisc + duoDiscGap),
                y: duoDiscOrigin.y,
                width: duoDisc,
                height: duoDisc
            )
        }
    }

    // MARK: Duo cover (FS-12.07b, board DC1)

    /// Content in the safe 382pt: three discs at the top, the frame's
    /// 382×215 box from y 45, the compact transport, and the timeline down
    /// to the home indicator — the band that flexes. The rail is the 84pt
    /// beside it. A tool's panel covers the timeline, frame and transport
    /// untouched.
    static func duoCover(_ input: Input) -> Frames {
        let width = input.window.width
        let height = input.window.height
        let contentWidth = width - coverRailWidth
        let stage = CGRect(x: 0, y: coverStageTop, width: contentWidth, height: (contentWidth * 9 / 16).rounded())
        let transport = CGRect(x: 0, y: stage.maxY, width: contentWidth, height: coverTransportHeight)
        let timeline = CGRect(
            x: 0, y: transport.maxY,
            width: contentWidth, height: height - coverHomeIndicator - transport.maxY
        )
        return Frames(
            band: CGRect(x: 0, y: 0, width: contentWidth, height: coverStageTop),
            pool: nil,
            stage: stage,
            frame: fit(input.canvas, in: stage),
            meter: nil,
            inspector: nil,
            transport: transport,
            overview: nil,
            timeline: timeline,
            dock: nil,
            bottomRow: nil,
            rail: CGRect(x: contentWidth, y: 0, width: coverRailWidth, height: height),
            toolPanel: timeline
        )
    }

    /// The cover with an item selected: the overview, and the panel full or
    /// pulled down to 78. The frame and the transport do not move.
    struct CoverSelection: Equatable {
        /// Nil while the panel is pulled down: the timeline shows instead.
        var overview: CGRect?
        var panel: CGRect
        /// What is left of the timeline above a pulled-down panel.
        var timeline: CGRect?
    }

    static func coverSelection(_ frames: Frames, isCollapsed: Bool) -> CoverSelection {
        let width = frames.timeline.width
        let bottom = frames.timeline.maxY
        if isCollapsed {
            let panel = CGRect(x: 0, y: bottom - coverCollapsedPanelHeight, width: width, height: coverCollapsedPanelHeight)
            let timeline = CGRect(x: 0, y: frames.timeline.minY, width: width, height: panel.minY - frames.timeline.minY)
            return CoverSelection(overview: nil, panel: panel, timeline: timeline)
        }
        return CoverSelection(
            overview: CGRect(x: coverOverviewInset, y: coverOverviewTop, width: width - coverOverviewInset * 2, height: overviewHeight),
            panel: CGRect(x: 0, y: coverItemPanelTop, width: width, height: bottom - coverItemPanelTop),
            timeline: nil
        )
    }

    /// Back, Undo, Redo over the cover's content.
    static func coverDiscFrames() -> [CGRect] {
        (0..<3).map { index in
            CGRect(
                x: coverDiscOrigin.x + CGFloat(index) * (coverDisc + coverDiscGap),
                y: coverDiscOrigin.y,
                width: coverDisc,
                height: coverDisc
            )
        }
    }

    /// The rail's parts for a window `width` wide.
    static func coverRail(windowWidth width: CGFloat, toolCount: Int = 5) -> CoverRail {
        let railX = width - coverRailWidth
        return CoverRail(
            cap: CGRect(x: railX, y: 0, width: coverRailWidth, height: coverCapHeight),
            tools: (0..<toolCount).map { index in
                CGRect(
                    x: railX + coverToolInset,
                    y: coverToolTop + CGFloat(index) * coverToolCell.height,
                    width: coverToolCell.width,
                    height: coverToolCell.height
                )
            },
            name: CGRect(origin: CGPoint(x: railX + coverNameInset, y: coverNameTop), size: coverNameSize),
            upperAction: CGRect(x: railX + coverActionInset, y: coverUpperActionTop, width: coverActionDisc, height: coverActionDisc),
            lowerAction: CGRect(x: railX + coverActionInset, y: coverLowerActionTop, width: coverActionDisc, height: coverActionDisc)
        )
    }

    // MARK: Shared

    /// The canvas aspect-fitted and centred in `rect`.
    static func fit(_ canvas: CGSize, in rect: CGRect) -> CGRect {
        guard canvas.width > 0, canvas.height > 0, rect.width > 0, rect.height > 0 else {
            return CGRect(origin: rect.origin, size: .zero)
        }
        let scale = min(rect.width / canvas.width, rect.height / canvas.height)
        let size = CGSize(width: canvas.width * scale, height: canvas.height * scale)
        return CGRect(
            x: rect.minX + (rect.width - size.width) / 2,
            y: rect.minY + (rect.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}
