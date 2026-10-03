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
}
