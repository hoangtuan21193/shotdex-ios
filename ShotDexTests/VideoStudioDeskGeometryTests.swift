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

    /// FS-12.03 AC-1 (board IL1): pool 236; inspector 280 at x 1096; frame
    /// 810×456 at (236, 122); transport at 604; overview 104–1360 at 652;
    /// timeline from 678, 354 tall.
    @Test func iPadLandscapeIdle() throws {
        let frames = Geometry.iPadLandscape(.init(
            window: CGSize(width: 1376, height: 1032),
            canvas: sixteenNine,
            isPoolOpen: true,
            isInspectorOpen: true,
            laneNeed: VideoStudioMetrics.Lanes.desk.timelineContentHeight(overlayLanes: 1, musicLanes: 2)
        ))
        let pool = try #require(frames.pool)
        #expect(pool == CGRect(x: 0, y: 64, width: 236, height: 540))
        let inspector = try #require(frames.inspector)
        #expect(inspector == CGRect(x: 1096, y: 64, width: 280, height: 540))
        #expect(frames.header == CGRect(x: 236, y: 64, width: 860, height: 32))
        #expect(frames.meter == CGRect(x: 1046, y: 96, width: 50, height: 508))
        #expect(near(frames.frame.minX, 236) && near(frames.frame.minY, 122))
        #expect(near(frames.frame.width, 810) && near(frames.frame.height, 456))
        #expect(frames.transport == CGRect(x: 0, y: 604, width: 1376, height: 44))
        #expect(frames.overview == CGRect(x: 104, y: 652, width: 1256, height: 22))
        #expect(frames.timeline == CGRect(x: 0, y: 678, width: 1376, height: 354))
    }

    /// FS-12.03b AC-3 (position): the transport runs the window's whole
    /// width, so on a 13" iPad it never falls back to the narrow row — not
    /// with the pool and the inspector both open, not with either shut.
    @Test func theTransportAlwaysGetsTheFullRowOnA13InchIPad() {
        for pool in [true, false] {
            for inspector in [true, false] {
                let frames = Geometry.iPadLandscape(.init(
                    window: CGSize(width: 1376, height: 1032), canvas: sixteenNine,
                    isPoolOpen: pool, isInspectorOpen: inspector
                ))
                #expect(frames.transport.width == 1376)
                #expect(VideoStudioMetrics.usesFullTransportRow(stageWidth: frames.transport.width))
            }
        }
    }

    /// Shutting the inspector gives its 280pt to the stage; the frame grows,
    /// the timeline does not move.
    @Test func shuttingTheInspectorWidensTheStage() {
        func frames(inspector: Bool) -> Geometry.Frames {
            Geometry.iPadLandscape(.init(
                window: CGSize(width: 1376, height: 1032), canvas: sixteenNine,
                isPoolOpen: true, isInspectorOpen: inspector
            ))
        }
        let open = frames(inspector: true)
        let shut = frames(inspector: false)
        #expect(shut.inspector == nil)
        #expect(shut.stage.width == open.stage.width + 280)
        #expect(shut.timeline == open.timeline)
    }

    /// The divider gives the timeline more and takes it from the stage; the
    /// stage never goes under its floor.
    @Test func theDividerTradesStageForTimeline() {
        let base = Geometry.iPadLandscape(.init(
            window: CGSize(width: 1376, height: 1032), canvas: sixteenNine,
            isPoolOpen: true, isInspectorOpen: true, timelineExtra: 80
        ))
        #expect(base.timeline.height == CGFloat(354 + 80))
        #expect(base.stage.height == CGFloat(508 - 80))
        let most = Geometry.iPadLandscape(.init(
            window: CGSize(width: 1376, height: 1032), canvas: sixteenNine,
            isPoolOpen: true, isInspectorOpen: true, timelineExtra: 400
        ))
        #expect(most.stage.height >= Geometry.stageFloor)
    }

    /// The pool opens by itself only on a window at least 1100 wide, and
    /// opens at all only where the stage keeps 330 beside it.
    @Test func thePoolOpensWhereItCostsTheFrameNothing() {
        #expect(Geometry.poolOpensByDefault(windowWidth: 1376))
        #expect(!Geometry.poolOpensByDefault(windowWidth: 1032))
        #expect(Geometry.canOpenPool(windowWidth: 1376, isInspectorOpen: true))
        #expect(!Geometry.canOpenPool(windowWidth: 800, isInspectorOpen: true))
        #expect(Geometry.canOpenPool(windowWidth: 800, isInspectorOpen: false))
    }

    /// FS-12.03 AC-2: selecting clip 2 does not move the frame — the
    /// inspector is there either way — and its foot is 58 at y 546.
    @Test func iPadLandscapeSelectedKeepsTheFrame() throws {
        let input = Geometry.Input(
            window: CGSize(width: 1376, height: 1032), canvas: sixteenNine,
            isPoolOpen: true, isInspectorOpen: true
        )
        var columns = VideoDeskColumns()
        let idle = Geometry.iPadLandscape(input)
        columns.presentsSheetChanged(from: false, to: true)
        var selected = input
        selected.isInspectorOpen = columns.isInspectorOpen
        let chosen = Geometry.iPadLandscape(selected)
        #expect(chosen.frame == idle.frame)
        let footer = Geometry.inspectorFooter(in: try #require(chosen.inspector))
        #expect(footer == CGRect(x: 1096, y: 546, width: 280, height: 58))
    }

    // MARK: iPad portrait

    /// FS-12.03 AC-3 (board IP1): header the whole width at 64; frame
    /// 982×552 with the meter at x 982; transport 648; overview 696; the
    /// timeline 722–1052 (330); the dock 1052–1376 (324).
    @Test func iPadPortraitIdle() throws {
        let frames = Geometry.iPadPortrait(.init(
            window: CGSize(width: 1032, height: 1376), canvas: sixteenNine,
            isPoolOpen: false, isInspectorOpen: true,
            laneNeed: VideoStudioMetrics.Lanes.desk.timelineContentHeight(overlayLanes: 1, musicLanes: 2)
        ))
        #expect(frames.pool == nil)
        #expect(frames.header == CGRect(x: 0, y: 64, width: 1032, height: 32))
        #expect(near(frames.frame.width, 982) && near(frames.frame.height, 552))
        #expect(frames.frame.minX == 0 && frames.frame.minY == 96)
        #expect(frames.meter?.minX == 982)
        #expect(near(frames.transport.minY, 648))
        #expect(near(frames.overview?.minY ?? 0, 696))
        #expect(near(frames.timeline.minY, 722) && near(frames.timeline.maxY, 1052))
        #expect(frames.dock == CGRect(x: 0, y: 1052, width: 1032, height: 324))
    }

    /// FS-12.03 AC-4: selected in portrait, the foot is 60 at y 1316 and
    /// the timeline (722–1052) is above the dock, never under it.
    @Test func iPadPortraitSelectedFooterAt1316() throws {
        let frames = Geometry.iPadPortrait(.init(
            window: CGSize(width: 1032, height: 1376), canvas: sixteenNine,
            isPoolOpen: false, isInspectorOpen: true,
            laneNeed: VideoStudioMetrics.Lanes.desk.timelineContentHeight(overlayLanes: 1, musicLanes: 2)
        ))
        let dock = try #require(frames.dock)
        #expect(Geometry.dockFooter(in: dock) == CGRect(x: 0, y: 1316, width: 1032, height: 60))
        #expect(frames.timeline.maxY <= dock.minY)
        #expect(Geometry.dockParamTop + Geometry.dockParamHeight <= Geometry.dockFooterTop)
    }

    /// A 9:16 project would take the whole height by the width; the frame is
    /// capped so the timeline keeps its floor above the dock.
    @Test func aPortraitProjectLeavesTheTimelineItsFloor() {
        let frames = Geometry.iPadPortrait(.init(
            window: CGSize(width: 1032, height: 1376), canvas: CGSize(width: 1080, height: 1920),
            isPoolOpen: false, isInspectorOpen: true
        ))
        #expect(frames.timeline.height >= Geometry.portraitTimelineFloor)
        #expect(near(frames.frame.width / frames.frame.height, 9.0 / 16.0, 0.01))
    }

    /// Split View's 639pt portrait half: the dock's three columns split the
    /// width equally; under 600 there are two, and the dock scrolls.
    @Test func aNarrowPortraitDockSplitsItsWidthInThree() {
        #expect(Geometry.dockColumnCount(width: 1032) == 3)
        #expect(near(Geometry.dockColumnWidth(width: 1032), 344))
        #expect(Geometry.dockColumnCount(width: 639) == 3)
        #expect(near(Geometry.dockColumnWidth(width: 639), 213))
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
        #expect(frames.header == nil)
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
