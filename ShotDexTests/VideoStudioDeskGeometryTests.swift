import CoreGraphics
import Testing
@testable import ShotDex

/// The wide layouts' numbers, against the boards (FS-12.03, FS-12.07b).
/// Each window class has one band that flexes; these pin the rest.
struct VideoStudioDeskGeometryTests {
    private typealias Geometry = VideoStudioDeskGeometry
    private let sixteenNine = CGSize(width: 1920, height: 1080)

    /// Within half a point — a fitted frame lands on fractions.
    private func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.5) -> Bool {
        abs(a - b) <= tolerance
    }

    // MARK: iPad landscape

    /// The board's project: one text lane and two music lanes fit the
    /// landscape floor and exactly fill the portrait timeline (FS-12.03 §2–3).
    private let boardLaneNeed: CGFloat = 304

    private func landscape(pool: Bool = true, inspector: Bool = true, extra: CGFloat = 0) -> Geometry.Frames {
        Geometry.iPadLandscape(.init(
            window: CGSize(width: 1376, height: 1032), canvas: sixteenNine,
            isPoolOpen: pool, isInspectorOpen: inspector,
            laneNeed: boardLaneNeed, timelineExtra: extra
        ))
    }

    /// FS-12.03 AC-1 (board IL1_Main, Mac-style 2026-10-04): the toolbar at
    /// y 24, 44 tall; the pool floating 320×568 at (8, 8); the inspector
    /// 360 at x 1016 from y 0 to 584; the frame 604×340 at (352, 130) with
    /// the 44 meter 10 after it, as tall as the frame; the play row at 530;
    /// the tool row at 596; the overview from x 208 at 644; the timeline
    /// from 672, 360 tall.
    @Test func iPadLandscapeIdle() throws {
        let frames = landscape()
        #expect(frames.band == CGRect(x: 0, y: 24, width: 1376, height: 44))
        #expect(frames.pool == CGRect(x: 8, y: 8, width: 320, height: 568))
        #expect(frames.inspector == CGRect(x: 1016, y: 0, width: 360, height: 584))
        #expect(frames.stage == CGRect(x: 336, y: 80, width: 680, height: 440))
        #expect(near(frames.frame.minX, 352) && near(frames.frame.minY, 130))
        #expect(near(frames.frame.width, 604) && near(frames.frame.height, 340))
        let meter = try #require(frames.meter)
        #expect(near(meter.minX, 966) && meter.width == 44)
        #expect(meter.minY == frames.frame.minY && meter.height == frames.frame.height)
        let playRow = try #require(frames.playRow)
        #expect(playRow.minY == 530 && playRow.height == 48)
        // Before and After ends the row at the frame's trailing edge + 44;
        // the play group is centred on the stage, x 538–816 on the board.
        #expect(near(playRow.minX, 352) && near(playRow.maxX, 1000))
        let mid = try #require(frames.playGroupMidX)
        #expect(near(mid - Geometry.playGroupWidth / 2, 538, 1.5))
        #expect(frames.divider == CGRect(x: 670, y: 586, width: 36, height: 4))
        #expect(frames.transport == CGRect(x: 0, y: 596, width: 1376, height: 44))
        #expect(frames.overview == CGRect(x: 208, y: 644, width: 1152, height: 22))
        #expect(frames.timeline == CGRect(x: 0, y: 672, width: 1376, height: 360))
    }

    /// FS-12.03b AC-3 (position): the timeline's tool row runs the window's
    /// whole width with the pool and the inspector open or shut — the
    /// columns stand beside the stage only.
    @Test func theToolRowRunsTheFullWidth() {
        for pool in [true, false] {
            for inspector in [true, false] {
                let frames = landscape(pool: pool, inspector: inspector)
                #expect(frames.transport == CGRect(x: 0, y: 596, width: 1376, height: 44))
                #expect(frames.timeline.width == 1376)
            }
        }
    }

    /// Shutting the inspector gives its 360 to the stage; the timeline does
    /// not move. Hiding the pool gives the stage everything from x 0.
    @Test func shuttingAColumnWidensTheStage() {
        let open = landscape()
        let noInspector = landscape(inspector: false)
        #expect(noInspector.inspector == nil)
        #expect(noInspector.stage.width == open.stage.width + 360)
        #expect(noInspector.timeline == open.timeline)
        let noPool = landscape(pool: false)
        #expect(noPool.pool == nil)
        #expect(noPool.stage.minX == 0 && noPool.stage.maxX == 1016)
        #expect(noPool.frame.width > open.frame.width)
    }

    /// The toolbar's leading capsules start past the pool when it is open,
    /// at the margin when it is shut: Back at 344, or Media Pool at 16.
    @Test func theToolbarStartsPastAnOpenPool() {
        #expect(Geometry.toolbarLeading(isPoolOpen: true) == 344)
        #expect(Geometry.toolbarLeading(isPoolOpen: false) == 16)
    }

    /// The divider gives the timeline more and takes it from the stage; the
    /// stage never goes under its floor.
    @Test func theDividerTradesStageForTimeline() {
        let base = landscape(extra: 80)
        #expect(base.timeline.height == CGFloat(360 + 80))
        #expect(base.stage.height == CGFloat(440 - 80))
        #expect(base.inspector?.height == CGFloat(584 - 80))
        #expect(landscape(extra: 400).stage.height >= Geometry.stageFloor)
    }

    /// The pool opens by itself only on a window at least 1100 wide, and
    /// opens at all only where the frame keeps 330 beside it.
    @Test func thePoolOpensWhereItCostsTheFrameNothing() {
        #expect(Geometry.poolOpensByDefault(windowWidth: 1376))
        #expect(!Geometry.poolOpensByDefault(windowWidth: 1032))
        #expect(Geometry.canOpenPool(windowWidth: 1376, isInspectorOpen: true))
        #expect(!Geometry.canOpenPool(windowWidth: 1000, isInspectorOpen: true))
        #expect(Geometry.canOpenPool(windowWidth: 1000, isInspectorOpen: false))
    }

    /// FS-12.03 AC-2: selecting clip 2 does not move the frame — the
    /// inspector is there either way — and its foot is 64 at y 520.
    @Test func iPadLandscapeSelectedKeepsTheFrame() throws {
        let input = Geometry.Input(
            window: CGSize(width: 1376, height: 1032), canvas: sixteenNine,
            isPoolOpen: true, isInspectorOpen: true, laneNeed: boardLaneNeed
        )
        var columns = VideoDeskColumns()
        let idle = Geometry.iPadLandscape(input)
        columns.presentsSheetChanged(from: false, to: true)
        var selected = input
        selected.isInspectorOpen = columns.isInspectorOpen
        let chosen = Geometry.iPadLandscape(selected)
        #expect(chosen.frame == idle.frame)
        let footer = Geometry.inspectorFooter(in: try #require(chosen.inspector))
        #expect(footer == CGRect(x: 1016, y: 520, width: 360, height: 64))
        #expect(Geometry.deskFooterButton == 44)
    }

    // MARK: iPad portrait

    private func portrait(pool: Bool = false, inspector: Bool = true, canvas: CGSize? = nil) -> Geometry.Frames {
        Geometry.iPadPortrait(.init(
            window: CGSize(width: 1032, height: 1376), canvas: canvas ?? sixteenNine,
            isPoolOpen: pool, isInspectorOpen: inspector, laneNeed: boardLaneNeed
        ))
    }

    /// FS-12.03 AC-3 (board IP1_Main): the toolbar as in landscape; the
    /// frame 932×524 at (28, 80), the meter at x 970; the play row at 610;
    /// the divider at 662; the tool row at 672; the overview 208–1016 at
    /// 720; the timeline 748–1052 (304); the dock 1052–1376 (324).
    @Test func iPadPortraitIdle() throws {
        let frames = portrait()
        #expect(frames.pool == nil)
        #expect(frames.band == CGRect(x: 0, y: 24, width: 1032, height: 44))
        #expect(near(frames.frame.minX, 28) && frames.frame.minY == 80)
        #expect(near(frames.frame.width, 932) && near(frames.frame.height, 524))
        #expect(near(frames.meter?.minX ?? 0, 970) && frames.meter?.height == frames.frame.height)
        let playRow = try #require(frames.playRow)
        #expect(playRow.minY == 610)
        #expect(near(playRow.maxX, 1004))
        #expect(near((frames.playGroupMidX ?? 0) - Geometry.playGroupWidth / 2, 355, 1.5))
        #expect(frames.divider?.minY == 662)
        #expect(frames.transport == CGRect(x: 0, y: 672, width: 1032, height: 44))
        #expect(frames.overview == CGRect(x: 208, y: 720, width: 808, height: 22))
        #expect(frames.timeline == CGRect(x: 0, y: 748, width: 1032, height: 304))
        #expect(frames.dock == CGRect(x: 0, y: 1052, width: 1032, height: 324))
    }

    /// The pool floats over the frame in portrait: opening it moves nothing.
    @Test func aPortraitPoolFloatsOverTheFrame() {
        let shut = portrait()
        let open = portrait(pool: true)
        #expect(open.pool == Geometry.poolFrame)
        #expect(open.frame == shut.frame)
        #expect(open.timeline == shut.timeline)
    }

    /// FS-12.03 AC-4: selected in portrait, the foot is 64 at y 1312 and
    /// the timeline (748–1052) is above the dock, never under it.
    @Test func iPadPortraitSelectedFooterAt1312() throws {
        let dock = try #require(portrait().dock)
        #expect(Geometry.dockFooter(in: dock) == CGRect(x: 0, y: 1312, width: 1032, height: 64))
        #expect(portrait().timeline.maxY <= dock.minY)
        #expect(dock.minY + Geometry.dockCommandRowTop == 1061)
        // The columns start where boards IP2, IP3 and F5_IP draw them
        // (user decision 2026-10-08): 12 under the command row.
        #expect(dock.minY + Geometry.dockParamTop == 1129)
        #expect(dock.minY + Geometry.dockCommandRowTop + 56 + 12 == 1129)
        #expect(Geometry.dockParamTop + Geometry.dockParamHeight == Geometry.dockFooterTop)
        #expect(Geometry.dockParamTop + Geometry.dockParamHeight <= Geometry.dockFooterTop)
    }

    /// A 9:16 project would take the whole height by the width; the frame is
    /// capped so the timeline keeps what its lanes need above the dock.
    @Test func aPortraitProjectLeavesTheTimelineItsLanes() {
        let frames = portrait(canvas: CGSize(width: 1080, height: 1920))
        #expect(frames.timeline.height >= boardLaneNeed)
        #expect(near(frames.frame.width / frames.frame.height, 9.0 / 16.0, 0.01))
    }

    /// The dock's columns (FS-12.03 §3): three of 312, 32 apart, 16 in on a
    /// 1032 window; Split View's 639 still splits in three, equally; under
    /// 600 there are two, and the dock scrolls.
    @Test func aNarrowPortraitDockSplitsItsWidthInThree() {
        #expect(Geometry.dockColumnCount(width: 1032) == 3)
        #expect(near(Geometry.dockColumnWidth(width: 1032), 312, 0.7))
        #expect(Geometry.dockColumnCount(width: 639) == 3)
        #expect(near(Geometry.dockColumnWidth(width: 639), 181))
        #expect(Geometry.dockColumnCount(width: 507) == 2)
        #expect(Geometry.dockColumnWidth(width: 507) >= Geometry.dockColumnMinimum)
    }

    // MARK: Duo inner

    /// FS-12.03 AC-5 (board DI1): 385 + 40 + 188 + 56 = 669 — no slack, so
    /// the sum is pinned. Frame 684×385 at y 0, column 264 at x 687,
    /// transport at 385, timeline 188, bottom row at 613.
    @Test func duoInnerBandsSumToTheWindow() throws {
        let frames = Geometry.duoInner(.init(
            window: CGSize(width: 951, height: 669), canvas: sixteenNine,
            isPoolOpen: false, isInspectorOpen: true
        ))
        let column = try #require(frames.inspector)
        let row = try #require(frames.bottomRow)
        #expect(frames.stage.height + frames.transport.height + frames.timeline.height + row.height == 669)
        #expect(column == CGRect(x: 687, y: 0, width: 264, height: 385))
        #expect(near(frames.frame.width, 684) && near(frames.frame.height, 385))
        #expect(near(frames.frame.minY, 0) && near(frames.frame.minX, 1.5))
        #expect(frames.transport == CGRect(x: 0, y: 385, width: 951, height: 40))
        #expect(frames.timeline == CGRect(x: 0, y: 425, width: 951, height: 188))
        #expect(row == CGRect(x: 0, y: 613, width: 951, height: 56))
        // The five tools from x 40, 72×50 apart by 4; the right group ends
        // at x 907.
        let lastTool = Geometry.duoToolLeading + 4 * (Geometry.duoToolCell.width + Geometry.duoToolGap)
        #expect(lastTool == 344)
        #expect(951 - Geometry.duoRowTrailingInset == 907)
        #expect(Geometry.duoDiscFrames().first == CGRect(x: 16, y: 12, width: 36, height: 36))
        #expect(Geometry.duoDiscFrames().last?.minX == 148)
    }

    /// FS-12.03 AC-6: selected, the right group is ✕ · name · ✓ from x 620
    /// to 907 — ✕ at 620, ✓ ending at 907 — and the five tools go inert.
    @Test func duoInnerSelectedFooterSpans620To907() {
        let row = CGRect(x: 0, y: 613, width: 951, height: 56)
        let end = row.maxX - Geometry.duoRowTrailingInset
        #expect(end == 907)
        #expect(end - Geometry.duoSessionGroupWidth == 620)
        #expect(Geometry.footerButton == 40)
        // The tools end at 416, well short of the group.
        let toolsEnd = Geometry.duoToolLeading + 5 * Geometry.duoToolCell.width + 4 * Geometry.duoToolGap
        #expect(toolsEnd < end - Geometry.duoSessionGroupWidth)
        #expect(VideoAddTool.toolsAreInert(in: .duoInner, isSelecting: true))
        #expect(!VideoAddTool.toolsAreInert(in: .duoInner, isSelecting: false))
    }

    /// The Duo inner layout has no pool, no meter and no viewer header:
    /// each would cost height this window does not have.
    @Test func duoInnerHasNoPoolMeterOrHeader() {
        let frames = Geometry.duoInner(.init(
            window: CGSize(width: 951, height: 669), canvas: sixteenNine,
            isPoolOpen: true, isInspectorOpen: true
        ))
        #expect(frames.pool == nil)
        #expect(frames.meter == nil)
        #expect(frames.overview == nil)
    }

    /// A Stage Manager window 1000×700 is short, so it gets this layout;
    /// the frame takes what the fixed bands leave.
    @Test func aShortStageManagerWindowFlexesTheFrame() {
        let frames = Geometry.duoInner(.init(
            window: CGSize(width: 1000, height: 700), canvas: sixteenNine,
            isPoolOpen: false, isInspectorOpen: true
        ))
        #expect(frames.stage == CGRect(x: 0, y: 0, width: 736, height: 416))
        #expect(frames.timeline.height == 188)
    }

    // MARK: Duo cover

    private func cover(_ canvas: CGSize) -> Geometry.Frames {
        Geometry.duoCover(.init(
            window: CGSize(width: 466, height: 678), canvas: canvas,
            isPoolOpen: false, isInspectorOpen: false
        ))
    }

    /// FS-12.07b AC-1 (board DC1): frame 382×215 at y 45; transport at 260;
    /// timeline 300–644; five cells 64×56 at x 392 from y 80 to 360; Video
    /// Settings at 504 and Export at 556 — and AC-11: three discs in the top
    /// row, nothing else.
    @Test func duoCoverIdle() throws {
        let frames = cover(sixteenNine)
        #expect(frames.stage == CGRect(x: 0, y: 45, width: 382, height: 215))
        #expect(near(frames.frame.width, 382) && near(frames.frame.height, 215))
        #expect(frames.transport == CGRect(x: 0, y: 260, width: 382, height: 40))
        #expect(frames.timeline == CGRect(x: 0, y: 300, width: 382, height: 344))
        #expect(frames.rail == CGRect(x: 382, y: 0, width: 84, height: 678))
        #expect(frames.toolPanel == frames.timeline)
        let rail = Geometry.coverRail(windowWidth: 466)
        #expect(rail.tools.count == 5)
        #expect(rail.tools.first == CGRect(x: 392, y: 80, width: 64, height: 56))
        #expect(rail.tools.last?.maxY == 360)
        #expect(rail.tools[3].contains(CGPoint(x: 424, y: 276)), "the Music cell answers at (424, 276)")
        #expect(rail.upperAction == CGRect(x: 402, y: 504, width: 44, height: 44))
        #expect(rail.lowerAction == CGRect(x: 402, y: 556, width: 44, height: 44))
        #expect(rail.name == CGRect(x: 386, y: 440, width: 76, height: 56))
        let discs = Geometry.coverDiscFrames()
        #expect(discs.count == 3)
        #expect(discs.map(\.minX) == [10, 50, 90])
        #expect(discs.allSatisfy { $0.minY >= 6 && $0.maxY <= 42 })
    }

    /// FS-12.07b AC-3: nothing that takes a touch in the cap (x 382–466,
    /// y 0–72) or below y 600 — the camera, the corners, the home bar.
    @Test func nothingTappableInTheCapOrBelow600() {
        let rail = Geometry.coverRail(windowWidth: 466)
        let tappable = rail.tools + [rail.upperAction, rail.lowerAction]
        for rect in tappable {
            #expect(rect.minY >= Geometry.coverCapHeight, "\(rect)")
            #expect(rect.maxY <= Geometry.coverTouchFloor, "\(rect)")
        }
    }

    /// FS-12.07b AC-7: a 9:16 project fits the same box — 121×215, centred
    /// in x 0–382.
    @Test func aPortraitProjectFitsCentred() {
        let frames = cover(CGSize(width: 1080, height: 1920))
        #expect(near(frames.frame.width, 121) && frames.frame.height == 215)
        #expect(near(frames.frame.minX, 130.5) && frames.frame.minY == 45)
    }

    /// FS-12.07b AC-4, AC-6: selected, the overview is at 306 (x 12, 358
    /// wide) and the panel starts at 334; the frame is still 382×215 at 45;
    /// ✕ at 504 and ✓ at 556 are the rail's two discs, the name at 440.
    @Test func duoCoverSelected() {
        let frames = cover(sixteenNine)
        let selection = Geometry.coverSelection(frames, isCollapsed: false)
        #expect(selection.overview == CGRect(x: 12, y: 306, width: 358, height: 22))
        #expect(selection.panel == CGRect(x: 0, y: 334, width: 382, height: 310))
        #expect(selection.timeline == nil)
        #expect(frames.stage == CGRect(x: 0, y: 45, width: 382, height: 215))
        let rail = Geometry.coverRail(windowWidth: 466)
        #expect(rail.name.minY == 440)
        #expect(rail.upperAction.minY == 504 && rail.lowerAction.minY == 556)
        #expect(VideoAddTool.toolsAreInert(in: .duoCover, isSelecting: true))
    }

    /// FS-12.07b AC-12: pulled down, the panel is 78 at 566–644 and the
    /// timeline is back from 300 to 566; the frame does not move.
    @Test func duoCoverCollapsedPanelIs78At566() {
        let frames = cover(sixteenNine)
        let selection = Geometry.coverSelection(frames, isCollapsed: true)
        #expect(selection.panel == CGRect(x: 0, y: 566, width: 382, height: 78))
        #expect(selection.timeline == CGRect(x: 0, y: 300, width: 382, height: 266))
        #expect(selection.overview == nil)
        #expect(frames.stage.minY == 45)
    }
}

extension VideoStudioDeskGeometryTests {
    /// FS-12.17 §4 (board F6_IP_PencilTrim): the frame trim's four dock
    /// columns, 238 wide and 16 apart, fill the 1032 window between the
    /// dock's 16pt insets — x 16, 270, 524, 778.
    @Test func portraitTrimColumnsFillTheDock() {
        let width = Geometry.dockTrimColumnWidth
        let gap = Geometry.dockTrimColumnGap
        let xs = (0..<4).map { Geometry.dockInset + CGFloat($0) * (width + gap) }
        #expect(xs == [16, 270, 524, 778])
        #expect(xs[3] + width + Geometry.dockInset == 1032)
    }
}

extension VideoStudioDeskGeometryTests {
    /// FS-12.17 AC-16 (board F6_DC_PreciseTrim): on the cover, trimming
    /// hides the panel — "Trim · Clip 2" in a band at 300–334, the timeline
    /// 334–644, the pill 248×48 at (67, 582); ✕ and ✓ stay at 504 and 556
    /// in the rail, nothing touchable above 72 or below 600 there.
    @Test func duoCoverFrameTrim() {
        let frames = cover(CGSize(width: 1920, height: 1080))
        let trim = Geometry.coverFrameTrim(frames)
        #expect(trim.nameBand == CGRect(x: 0, y: 300, width: 382, height: 34))
        #expect(trim.timeline == CGRect(x: 0, y: 334, width: 382, height: 310))
        #expect(trim.pill == CGRect(x: 67, y: 582, width: 248, height: 48))
        let rail = Geometry.coverRail(windowWidth: 466)
        #expect(rail.upperAction.minY == 504)
        #expect(rail.lowerAction.minY == 556)
        #expect(rail.lowerAction.maxY <= Geometry.coverTouchFloor)
        #expect(rail.tools.allSatisfy { $0.minY >= Geometry.coverCapHeight })
    }
}
