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
    // MARK: iPad top band (FS-12.03 §2)

    /// The band runs 0–64; its row of discs sits at y 12–52.
    static let bandHeight: CGFloat = 64
    static let bandRowTop: CGFloat = 12
    static let bandDisc: CGFloat = 40
    static let bandDiscGap: CGFloat = 10
    static let bandInset: CGFloat = 20
    /// "16:9 · 1080p · 30 fps": 32 tall, radius 8, on one line in landscape.
    static let settingsButtonHeight: CGFloat = 32
    static let settingsButtonRadius: CGFloat = 8
    static let exportHeight: CGFloat = 40

    // MARK: Columns and bands

    /// The library column — iPad only.
    static let poolWidth: CGFloat = 236
    /// The pool opens by itself only this wide, and only if the stage keeps
    /// `poolMinimumStageWidth` beside it (FS-12.03b §1).
    static let poolOpensByDefaultWidth: CGFloat = 1100
    static let poolMinimumStageWidth: CGFloat = 330
    /// The iPad inspector: always there in landscape, Look when nothing is
    /// selected.
    static let inspectorWidth: CGFloat = 280
    static let inspectorCornerRadius: CGFloat = 16
    static let viewerHeaderHeight: CGFloat = 32
    /// The level meter beside the frame: a dB scale and two bars, or the
    /// bars alone when the stage is under `meterWideStage` (FS-12.03b §3).
    static let meterWidth: CGFloat = 50
    static let meterNarrowWidth: CGFloat = 32
    static let meterWideStage: CGFloat = 820
    /// The desk transport — fifteen buttons and the timecode.
    static let transportHeight: CGFloat = 44
    /// The whole-project strip, with 4pt above and below it.
    static let overviewHeight: CGFloat = 22
    static let overviewGap: CGFloat = 4
    /// It starts where the lanes start, after the track headers, and stops
    /// 16 short of the window's edge.
    static let overviewTrailingInset: CGFloat = 16
    /// The iPad's track header column — where the lanes, and so the
    /// overview, start.
    static let trackHeaderWidth: CGFloat = 104
    /// iPad landscape: the timeline never gets less than this.
    static let landscapeTimelineFloor: CGFloat = 354
    /// The least the stage keeps when the divider is dragged up.
    static let stageFloor: CGFloat = 200
    /// How far the divider may give the timeline more than it needs.
    static let timelineExtraRange: ClosedRange<CGFloat> = 0...400

    /// The rect of every band. Nil where the window class has no such band.
    struct Frames: Equatable {
        var band: CGRect
        var pool: CGRect?
        var header: CGRect?
        /// The area the frame is fitted into (black around the frame).
        var stage: CGRect
        /// The project's frame, aspect-fitted into `stage`.
        var frame: CGRect
        var meter: CGRect?
        var inspector: CGRect?
        var transport: CGRect
        var overview: CGRect?
        var timeline: CGRect
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

    /// Whether the pool can open at all with the inspector as it is: the
    /// stage has to keep `poolMinimumStageWidth` beside the meter.
    static func canOpenPool(windowWidth: CGFloat, isInspectorOpen: Bool) -> Bool {
        let centre = windowWidth - poolWidth - (isInspectorOpen ? inspectorWidth : 0)
        return centre - meterWidth(centreWidth: centre) >= poolMinimumStageWidth
    }

    static func meterWidth(centreWidth: CGFloat) -> CGFloat {
        centreWidth >= meterWideStage ? meterWidth : meterNarrowWidth
    }

    // MARK: iPad landscape (FS-12.03 §2, board IL1)

    /// Pool 236 | header + stage + meter | inspector 280 from y 64 to the
    /// transport; the transport, the overview and the timeline run the
    /// whole width under them. The stage flexes; the timeline keeps 354.
    static func iPadLandscape(_ input: Input) -> Frames {
        let width = input.window.width
        let height = input.window.height
        let extra = min(max(0, input.timelineExtra), timelineExtraRange.upperBound)
        // The timeline's height, then everything above it from the bottom up.
        let fixedAbove = bandHeight + viewerHeaderHeight + transportHeight
            + overviewGap * 2 + overviewHeight
        let timelineHeight = min(
            max(landscapeTimelineFloor, input.laneNeed) + extra,
            max(landscapeTimelineFloor, height - fixedAbove - stageFloor)
        )
        let timeline = CGRect(x: 0, y: height - timelineHeight, width: width, height: timelineHeight)
        let overview = CGRect(
            x: trackHeaderWidth,
            y: timeline.minY - overviewGap - overviewHeight,
            width: width - trackHeaderWidth - overviewTrailingInset,
            height: overviewHeight
        )
        let transport = CGRect(
            x: 0, y: overview.minY - overviewGap - transportHeight,
            width: width, height: transportHeight
        )
        let rowTop = bandHeight
        let rowHeight = transport.minY - rowTop
        let pool = input.isPoolOpen ? CGRect(x: 0, y: rowTop, width: poolWidth, height: rowHeight) : nil
        let inspector = input.isInspectorOpen
            ? CGRect(x: width - inspectorWidth, y: rowTop, width: inspectorWidth, height: rowHeight)
            : nil
        let centreX = pool?.maxX ?? 0
        let centreWidth = (inspector?.minX ?? width) - centreX
        let header = CGRect(x: centreX, y: rowTop, width: centreWidth, height: viewerHeaderHeight)
        let meterW = meterWidth(centreWidth: centreWidth)
        let stage = CGRect(
            x: centreX, y: header.maxY,
            width: centreWidth - meterW, height: transport.minY - header.maxY
        )
        let meter = CGRect(x: stage.maxX, y: stage.minY, width: meterW, height: stage.height)
        return Frames(
            band: CGRect(x: 0, y: 0, width: width, height: bandHeight),
            pool: pool,
            header: header,
            stage: stage,
            frame: fit(input.canvas, in: stage),
            meter: meter,
            inspector: inspector,
            transport: transport,
            overview: overview,
            timeline: timeline
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
