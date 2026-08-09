import CoreGraphics
import Foundation

/// Corner the floating histogram card snaps to when the user lets go.
enum EditorHistogramCorner: String, CaseIterable, Codable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    var isTop: Bool { self == .topLeading || self == .topTrailing }
    var isLeading: Bool { self == .topLeading || self == .bottomLeading }
}

/// Fixed geometry of the editor. The panel never resizes — not while scrolling,
/// changing tab, entering a mask, or dragging a slider. Only full-bleed takes it
/// away, so its height is a pure function of the screen.
enum EditorLayoutMetrics {
    // MARK: Turn 31 panel

    /// The "Turn 31" editor: a floating command row rides the Dynamic Island band
    /// over the photo (undo / redo / hold-for-original on the leading edge, the
    /// histogram mini and the ⋯ menu on the trailing edge), and one opaque panel is
    /// glued to the bottom. The panel never resizes. Its tiers, top to bottom, are
    /// the scrolling parameter zone (an optional target strip is its first row, not
    /// a tier of its own, so the panel is the same height on every tab), the group
    /// strip — a snap wheel flanked by Back and Save — and a bare home-indicator
    /// inset. There is no in-panel command row: everything that used to sit there
    /// moved onto the band or into the ⋯ menu.
    static let editorPanelHeight: CGFloat = 246
    /// The parameter zone: the scrolling rows. Fixed, so the panel stays 246 on
    /// every tab. When a target strip shows it is the zone's first 36pt and the rows
    /// take the rest — the panel height itself does not change.
    /// 167 = 246 − 54 group strip − 25 safe-area inset.
    static let editorParamZoneHeight: CGFloat = 167
    /// The group-strip tier: `[Back 38] [wheel] [Save 42]`. Taller than the old chip
    /// row (54, not 40) because the wheel's chips are an icon over a label.
    static let editorGroupStripHeight: CGFloat = 54
    /// Target strip — "which area does this act on" — the first row *inside* the
    /// parameter zone (not a tier of its own). Only Grade shows it; Color Mix keeps
    /// its all-channels scroll and Mask keeps its own list / detail panels.
    static let editorTargetStripHeight: CGFloat = 36
    /// Bare home-indicator zone under the group strip. 25pt, not the full 34: the
    /// wheel above it takes only horizontal swipes, which the system's bottom-edge
    /// (vertical) gesture does not claim.
    static let editorPanelSafeAreaInset: CGFloat = 25
    /// The band over the Dynamic Island. It carries the floating command row; the
    /// photo starts at its bottom edge so it never touches the island. This 48 is a
    /// *floor*: the band is grown to the device's top safe-area inset (≈59 on Face-ID
    /// iPhones) when that is larger, so a tall aspect-fit photo begins below the
    /// island's bottom rather than being sliced by it.
    static let editorTopBandHeight: CGFloat = 48
    /// The floating command row inside the band: 34pt circular buttons, 37 tall,
    /// inset 11 from the band's top so the row sits level with the Dynamic Island.
    static let editorFloatingCommandRowHeight: CGFloat = 37
    static let editorFloatingCommandRowTopInset: CGFloat = 11
    static let editorFloatingCommandButtonSize: CGFloat = 34
    /// Horizontal inset for the command clusters from each screen edge. Must clear
    /// the device's rounded corner (≈55–62pt radius on Face-ID iPhones) at the row's
    /// vertical band so a 34pt disc is never sliced by the corner; the clusters can
    /// still sit right up against the Dynamic Island in the middle. Same value on
    /// both edges so undo (left-most) and ⋯ (right-most) are equally safe.
    static let editorFloatingCommandSideInset: CGFloat = 20
    /// On-screen width of the Dynamic Island, plus a hair of margin, used to keep
    /// the stretchable histogram pill out from under it. Face-ID iPhones are ~126pt;
    /// a touch wider so the pill's edge parks just clear of the cutout.
    static let editorDynamicIslandWidth: CGFloat = 132

    /// Where the stretchable histogram pill should start (its leading x), given the
    /// band's full width: just right of the Dynamic Island. The pill then runs from
    /// here out to the ⋯ button, filling the band's right half.
    static func editorHistogramPillLeading(bandWidth: CGFloat) -> CGFloat {
        bandWidth / 2 + editorDynamicIslandWidth / 2
    }

    // MARK: Group wheel

    /// One wheel chip: an icon over a label. Fixed width so the snap picker has a
    /// regular stride and the chip nearest the centre is unambiguous.
    static let editorGroupChipWidth: CGFloat = 58
    static let editorGroupChipHeight: CGFloat = 42
    /// The fade over each end of the wheel, dissolving chips into the panel colour.
    static let editorGroupWheelEdgeFade: CGFloat = 26

    // MARK: Legacy panel constants (Collage / Video Studio, draw takeover)

    /// Still used by the Collage and Video Studio panels and the drawing top bar —
    /// left in place so this change stays inside the photo editor.
    static let editorPanelFixedHeight: CGFloat = 240
    static let editorActionBarHeight: CGFloat = 40
    static let editorGroupNavHeight: CGFloat = 48
    /// One parameter row. Every gesture surface (label, track, value) spans the
    /// full row width at this height, so a value can be dragged from anywhere on it.
    static let editorRowHeight: CGFloat = 34
    static let editorRowLabelWidth: CGFloat = 88
    static let editorRowValueWidth: CGFloat = 40
    /// Mini histogram, in the Dynamic Island band. Tapping it expands the floating
    /// card over the photo.
    static let editorMiniHistogramSize = CGSize(width: 56, height: 29)

    /// Height the parameter-row list gets: the whole parameter zone, less the target
    /// strip when one is shown. The panel height is unaffected either way.
    static func editorParamAreaHeight(hasTargetStrip: Bool) -> CGFloat {
        editorParamZoneHeight - (hasTargetStrip ? editorTargetStripHeight : 0)
    }

    // MARK: Floating histogram card

    /// The expanded histogram card that floats over the photo. Tapping the mini
    /// histogram opens it; it drags to any corner and taps closed.
    static let histogramCardWidth: CGFloat = 152
    static let histogramCardHeight: CGFloat = 86
    static let histogramCollapsedHeight: CGFloat = 30
    /// Margin the card keeps from the image edges when parked in a corner.
    static let histogramInset: CGFloat = 12

    static func histogramSize(collapsed: Bool) -> CGSize {
        collapsed
            ? CGSize(width: editorMiniHistogramSize.width, height: histogramCollapsedHeight)
            : CGSize(width: histogramCardWidth, height: histogramCardHeight)
    }

    /// Resting centre of the card for a given corner inside the image bounds.
    static func histogramCenter(
        for corner: EditorHistogramCorner,
        cardSize: CGSize,
        in bounds: CGRect
    ) -> CGPoint {
        let field = bounds.insetBy(dx: histogramInset, dy: histogramInset)
        let x = corner.isLeading
            ? field.minX + cardSize.width / 2
            : field.maxX - cardSize.width / 2
        let y = corner.isTop
            ? field.minY + cardSize.height / 2
            : field.maxY - cardSize.height / 2
        return CGPoint(x: x, y: y)
    }

    /// Corner nearest a dropped centre, so the card snaps to whichever quadrant
    /// the user let go in.
    static func nearestHistogramCorner(
        to center: CGPoint,
        in bounds: CGRect
    ) -> EditorHistogramCorner {
        let isLeading = center.x <= bounds.midX
        let isTop = center.y <= bounds.midY
        if isTop { return isLeading ? .topLeading : .topTrailing }
        return isLeading ? .bottomLeading : .bottomTrailing
    }
    /// Fine-adjust: press in place this long, then drag, and the value moves at
    /// `sliderFineGain` of the normal rate.
    static let sliderFineHoldSeconds: Double = 0.3
    static let sliderFineGain: Double = 0.25

    /// Top padding for the editor's first row so `Cancel` / `Done` sit level with
    /// the Dynamic Island instead of below it, giving the photo the safe-area
    /// height back. The status bar is hidden in the editor, so nothing collides.
    static let dynamicIslandRowTopInset: CGFloat = 10
    /// Gap left under the tab bar. The editor takes the bottom safe area for
    /// itself so the photo is taller; this keeps the tab labels clear of the home
    /// indicator without giving the full 34pt back.
    static let panelBottomInset: CGFloat = 16
    /// Breathing room around the photo while the Crop tool is up, so the frame's
    /// handles sit inside the screen rather than on its edge.
    static let cropStageInset: CGFloat = 30
    static let maskNavigationRowHeight: CGFloat = 44
    static let sliderRowHeight: CGFloat = 32
    /// Total height of one slider/toggle row in the edit panel. 36pt on purpose —
    /// under the 44pt HIG tap minimum — so the panel fits more sliders per
    /// screenful. The track's pan area still spans the full row.
    static let sliderRowTotalHeight: CGFloat = 36
    static let sliderLabelWidth: CGFloat = 78
    static let sliderValueWidth: CGFloat = 44
    /// The pan has to travel this far before either the scroll view or a slider
    /// is declared the owner of the gesture. Deliberately below
    /// `UIPanGestureRecognizer`'s own ~10pt threshold: the slider must reject a
    /// vertical pan *before* the recognizer would otherwise begin and lock the
    /// scroll view out.
    static let gestureArbitrationDistance: CGFloat = 8
    /// And this far before a claimed slider actually writes a value, so a tap or
    /// a flick across the panel never nudges an adjustment.
    static let sliderActivationDistance: CGFloat = 6
    /// How far off the horizontal a pan may be and still belong to a slider.
    /// Comparing |dy| against |dx| was far too generous — a 40° diagonal flick
    /// counted as horizontal — so a list of sliders was hard to scroll.
    static let sliderAngleTolerance: CGFloat = 25
    /// Distance in points either side of a slider's identity value where the knob
    /// snaps onto it, so returning a slider to 0 does not need pixel precision.
    /// Small on purpose: a wide detent makes small values near 0 unreachable.
    static let sliderDetentDistance: CGFloat = 6

    /// True when a pan is within `sliderAngleTolerance` of the horizontal axis.
    static func isHorizontalPan(dx: CGFloat, dy: CGFloat) -> Bool {
        guard dx != 0 || dy != 0 else { return false }
        guard dx != 0 else { return false }
        return abs(dy) <= abs(dx) * tan(sliderAngleTolerance * .pi / 180)
    }

    /// Snaps `value` onto `detent` while the finger is within
    /// `sliderDetentDistance` of it. `width` is the track's on-screen width, so
    /// the pull is a constant distance in points at any range.
    static func snapped(
        _ value: Double,
        detent: Double,
        range: ClosedRange<Double>,
        trackWidth: CGFloat
    ) -> Double {
        guard trackWidth > 0 else { return value }
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return value }
        let tolerance = span * Double(sliderDetentDistance / trackWidth)
        return abs(value - detent) <= tolerance ? detent : value
    }


    // MARK: Mask guides

    /// Same knob as the crop frame: the two tools should feel like one hand.
    static let maskGuideKnobSize: CGFloat = 18
    static let maskGuideHitTarget: CGFloat = 44
    /// Smallest radius a radial gradient can be squeezed to — matches
    /// `PhotoEditorController.setGradient`.
    static let minimumMaskRadius = 0.02

    /// Normalized mask coordinate to a point inside the fitted image rect.
    static func maskViewPoint(_ point: NormalizedPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + rect.width * CGFloat(point.x),
            y: rect.minY + rect.height * CGFloat(point.y)
        )
    }

    /// View point back to a normalized mask coordinate, clamped to the image.
    /// Unlike the paint layer's mapping this never returns nil: a knob drag that
    /// wanders off the photo should pin to the edge, not stop responding.
    static func maskNormalizedPoint(_ point: CGPoint, in rect: CGRect) -> NormalizedPoint {
        guard rect.width > 0, rect.height > 0 else { return .center }
        return NormalizedPoint(
            x: min(1, max(0, (point.x - rect.minX) / rect.width)),
            y: min(1, max(0, (point.y - rect.minY) / rect.height))
        )
    }

    static func clampedMaskRadius(_ value: Double) -> Double {
        min(1, max(minimumMaskRadius, value))
    }

    /// Bounding box of a radial gradient's ellipse in view coordinates.
    /// `radiusX` is a fraction of the image width and `radiusY` of its height —
    /// the renderer scales each axis independently, so the guide must too.
    /// `feather` > 0 shrinks the box to the solid core the renderer keeps:
    /// the ramp runs from `(1 − feather) · radius` out to the full radius.
    static func radialGuideRect(
        center: NormalizedPoint,
        radiusX: Double,
        radiusY: Double,
        feather: Double = 0,
        in rect: CGRect
    ) -> CGRect {
        let scale = CGFloat(max(0, 1 - feather))
        let rx = rect.width * CGFloat(radiusX) * scale
        let ry = rect.height * CGFloat(radiusY) * scale
        let mid = maskViewPoint(center, in: rect)
        return CGRect(x: mid.x - rx, y: mid.y - ry, width: rx * 2, height: ry * 2)
    }

    /// Feather implied by a finger sitting at `location`: 0 on the ellipse's own
    /// edge, 1 at its centre. `radii` are the ellipse's half-extents in view
    /// points, so the reading follows the ellipse's shape rather than a circle.
    static func maskFeather(
        at location: CGPoint,
        center: CGPoint,
        radii: CGSize
    ) -> Double {
        guard radii.width > 0, radii.height > 0 else { return 0 }
        let ratio = hypot(
            (location.x - center.x) / radii.width,
            (location.y - center.y) / radii.height
        )
        return min(1, max(0, 1 - Double(ratio)))
    }

    /// Brush footprint the renderer will stamp: a fraction of the image's short
    /// edge, mirroring `PhotoRenderService.brushMask`.
    static func brushDiameter(size: Double, in rect: CGRect) -> CGFloat {
        CGFloat(size) * min(rect.width, rect.height)
    }

    /// How much of that footprint stays fully opaque before the feather ramp.
    static func brushCoreScale(feather: Double) -> CGFloat {
        CGFloat(max(0.08, 1 - feather * 0.8))
    }

    /// Diameter to draw the brush cursor at *inside the zoomed stack*, so that on
    /// screen it always comes back out as `brushDiameter` — the footprint the
    /// stroke will record, whatever the photo is pinched to. This is the whole
    /// point of a screen-sized brush: zooming in is how small detail is reached.
    ///
    /// The 8pt floor is a *screen* floor for the same reason — it is applied
    /// before the divide, so the multiply back out leaves exactly 8pt.
    static func brushCursorDiameter(
        size: Double,
        in rect: CGRect,
        zoomScale: CGFloat
    ) -> CGFloat {
        max(8, brushDiameter(size: size, in: rect)) / max(1, zoomScale)
    }

    /// Matches the Size slider in the mask popup.
    static let brushSizeRange = 0.02...0.5

    /// How a brush control reads out: a bare 0–100 number, the way Lightroom writes
    /// Size, Feather and Flow.
    ///
    /// Not a percentage, because the thing it is a percentage *of* differs per
    /// control and none of them is the photo: Size is a fraction of the short edge,
    /// Feather a fraction of the stamp, Flow a fraction of full opacity. A `%` sign
    /// invites the reading "50% of the picture", which Size at 0.25 is not. The
    /// number is simply where the knob sits on its own slider — so the top of every
    /// brush control is 100 and they can be compared at a glance.
    static func brushAmountText(_ value: Double, in range: ClosedRange<Double>) -> String {
        guard range.upperBound > 0 else { return "0" }
        let position = min(1, max(0, value / range.upperBound))
        return "\(Int((position * 100).rounded()))"
    }

    // MARK: Zoom

    /// How far the photo can be pinched open in the editor. 10×, one stop past
    /// Lightroom's own 8× ceiling: painting a mask into small detail — an eyelash,
    /// a power line — is what the zoom is for, and the brush is a screen size, so
    /// every extra stop is a finer brush rather than just a bigger picture.
    ///
    /// The picture itself stops sharpening before here: the settle render caps at
    /// `zoomedSettleEdge` (4800px), which on a phone is roughly 400%. Past that the
    /// photo is being magnified rather than resolved — still the right trade, since
    /// what is being aimed at is the *mask*, not the grain.
    static let maximumZoomScale: CGFloat = 10

    /// What a stroke records when it is painted at `zoomScale`.
    ///
    /// The Size slider is a *screen* size: the ring under the finger stays the
    /// same size however far the photo is zoomed, so zooming in is how the user
    /// paints finer detail. The recipe stores image-relative sizes, so the number
    /// that gets written has to shrink by exactly the zoom.
    static func paintedSize(_ size: Double, zoomScale: CGFloat) -> Double {
        size / Double(max(1, zoomScale))
    }

    /// Offset that keeps the pixel under the pinch's own anchor point still while
    /// the scale changes from `startScale` to `scale`.
    ///
    /// Without it the photo scales about the middle of the stage, so pinching open
    /// on a corner walks that corner off screen and finding the detail again costs
    /// a two-finger pan — which is most of the work when the reason for zooming was
    /// to paint one small thing.
    ///
    /// `anchor` and `startOffset` are in stage points; the maths is the inverse of
    /// the stage's own `scaleEffect(scale).offset(offset)`, which scales about the
    /// stage's centre.
    static func anchoredZoomOffset(
        anchor: CGPoint,
        stage: CGSize,
        startScale: CGFloat,
        startOffset: CGSize,
        scale: CGFloat
    ) -> CGSize {
        guard startScale > 0 else { return startOffset }
        let ratio = scale / startScale
        let dx = anchor.x - stage.width / 2
        let dy = anchor.y - stage.height / 2
        return CGSize(
            width: dx - (dx - startOffset.width) * ratio,
            height: dy - (dy - startOffset.height) * ratio
        )
    }

    /// Zoom readout, rounded the way a percentage is read: 100, 250, 800.
    static func zoomPercent(_ scale: CGFloat) -> Int {
        Int((scale * 100).rounded())
    }

    /// How much of the stage may be left empty on one side by panning. Half:
    /// dragging a zoomed photo until only a sliver of it is left on screen is a
    /// dead end — there is nothing under the finger to drag it back with.
    static let maximumPannedAwayFraction: CGFloat = 0.5

    /// Furthest the zoomed photo may be pushed along one axis before at least
    /// `1 − maximumPannedAwayFraction` of the stage would stop being covered.
    ///
    /// `content` is the photo's on-screen length once zoomed, `viewport` the
    /// stage's. A photo shorter than the viewport (a panorama's height, or any
    /// photo at 1×) can still slide until its edge reaches the stage edge and no
    /// further — it never leaves, so nothing is gained by pinning it.
    static func panLimit(content: CGFloat, viewport: CGFloat) -> CGFloat {
        guard viewport > 0 else { return 0 }
        let slack = abs(viewport - content) / 2
        let coverage = min(content, viewport)
        return slack + max(0, coverage - viewport * maximumPannedAwayFraction)
    }

    /// Pulls a pan offset back inside `panLimit` on both axes. Applied to every
    /// pan *and* to every zoom change, because pinching back out shrinks the
    /// content and can leave a previously legal offset out of bounds.
    static func clampedZoomOffset(
        _ offset: CGSize,
        imageSize: CGSize,
        zoomScale: CGFloat,
        stage: CGSize
    ) -> CGSize {
        let limitX = panLimit(content: imageSize.width * zoomScale, viewport: stage.width)
        let limitY = panLimit(content: imageSize.height * zoomScale, viewport: stage.height)
        return CGSize(
            width: min(limitX, max(-limitX, offset.width)),
            height: min(limitY, max(-limitY, offset.height))
        )
    }

    /// Endpoints of a line through `point`, perpendicular to `axis`, `length`
    /// long. This is the Lightroom-style guide for a linear gradient: the two
    /// rails through its start and end points. A degenerate axis (both points on
    /// top of each other) falls back to a vertical axis so the rails stay
    /// horizontal rather than vanishing.
    static func perpendicularSegment(
        through point: CGPoint,
        axis: CGVector,
        length: CGFloat
    ) -> (CGPoint, CGPoint) {
        let magnitude = hypot(axis.dx, axis.dy)
        let unit: CGVector = magnitude > 0
            ? CGVector(dx: axis.dx / magnitude, dy: axis.dy / magnitude)
            : CGVector(dx: 0, dy: 1)
        let half = length / 2
        // Perpendicular of (dx, dy) is (−dy, dx).
        return (
            CGPoint(x: point.x - unit.dy * half, y: point.y + unit.dx * half),
            CGPoint(x: point.x + unit.dy * half, y: point.y - unit.dx * half)
        )
    }

    /// Aspect-fit rect of an image inside a container, used by the stage for
    /// overlay placement and for mapping taps back to normalized coordinates.
    static func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        fittedRect(aspectRatio: imageSize.width / imageSize.height, in: container)
    }

    /// The same fit expressed as a ratio, which is what the editor stage uses.
    ///
    /// Laying out from the preview bitmap's pixel size meant the photo — and every
    /// guide over it — shifted a fraction of a point whenever the same recipe was
    /// re-rendered at a different resolution. Invisible at 1×; at 800% the same
    /// fraction is eight times as wide and reads as the picture jumping.
    static func fittedRect(aspectRatio: CGFloat, in container: CGSize) -> CGRect {
        guard aspectRatio > 0, aspectRatio.isFinite,
              container.width > 0, container.height > 0
        else { return CGRect(origin: .zero, size: container) }
        let scale = min(1, container.height * aspectRatio / container.width)
        let size = CGSize(
            width: container.width * scale,
            height: container.width * scale / aspectRatio
        )
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}
