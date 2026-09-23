import CoreGraphics
import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

struct EditorPanelLayoutTests {

    /// The Turn 31 panel is one fixed 246pt slab: a parameter zone, the group
    /// strip (a wheel flanked by Back and Save) and a bare home-indicator inset.
    /// There is no in-panel command row — it moved to the band — and the panel is
    /// the same height on every tab, the target strip eating into the parameter
    /// zone rather than adding to the panel.
    @Test func theTurn31PanelIsAFixed246SlabOfThreeTiers() {
        #expect(EditorLayoutMetrics.editorPanelHeight == 246)
        #expect(EditorLayoutMetrics.editorParamZoneHeight == 167)
        #expect(EditorLayoutMetrics.editorGroupStripHeight == 54)
        #expect(EditorLayoutMetrics.editorTargetStripHeight == 36)
        #expect(EditorLayoutMetrics.editorPanelSafeAreaInset == 25)

        // Light · Curve · Color · Mix · Point · Grade · Effects · Detail · Optics ·
        // Geo · Crop · Heal · Mask · Markup · Presets — all in the wheel, each with
        // an icon. Heal joined in FS-03.11; the phone gets it like the iPad.
        #expect(EditorGroup.allCases.count == 15)
        #expect(EditorGroup.allCases.allSatisfy { !$0.title.isEmpty })
        #expect(EditorGroup.allCases.allSatisfy { !$0.icon.isEmpty })

        // The three tiers total the slab.
        #expect(
            EditorLayoutMetrics.editorParamZoneHeight
                + EditorLayoutMetrics.editorGroupStripHeight
                + EditorLayoutMetrics.editorPanelSafeAreaInset
                == EditorLayoutMetrics.editorPanelHeight
        )

        // The parameter *rows* get the zone, less the target strip when one shows —
        // but the panel height is unchanged either way.
        let plain = EditorLayoutMetrics.editorParamAreaHeight(hasTargetStrip: false)
        let withTarget = EditorLayoutMetrics.editorParamAreaHeight(hasTargetStrip: true)
        #expect(plain == 167)
        #expect(withTarget == 131)
        #expect(plain == EditorLayoutMetrics.editorParamZoneHeight)
        #expect(
            withTarget + EditorLayoutMetrics.editorTargetStripHeight
                == EditorLayoutMetrics.editorParamZoneHeight
        )
    }

    /// The floating histogram card snaps to whichever corner it is dropped in and
    /// parks there inset from the image edges.
    @Test func histogramCardSnapsToTheNearestCorner() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 600)
        #expect(EditorLayoutMetrics.nearestHistogramCorner(to: CGPoint(x: 10, y: 10), in: bounds) == .topLeading)
        #expect(EditorLayoutMetrics.nearestHistogramCorner(to: CGPoint(x: 390, y: 10), in: bounds) == .topTrailing)
        #expect(EditorLayoutMetrics.nearestHistogramCorner(to: CGPoint(x: 10, y: 590), in: bounds) == .bottomLeading)
        #expect(EditorLayoutMetrics.nearestHistogramCorner(to: CGPoint(x: 390, y: 590), in: bounds) == .bottomTrailing)

        // The expanded card is larger than the parked mini, and its resting centre
        // sits a card-half plus the inset in from the chosen corner.
        let size = EditorLayoutMetrics.histogramSize(collapsed: false)
        #expect(size == CGSize(width: 152, height: 86))
        let center = EditorLayoutMetrics.histogramCenter(for: .topTrailing, cardSize: size, in: bounds)
        #expect(center.x == bounds.maxX - EditorLayoutMetrics.histogramInset - size.width / 2)
        #expect(center.y == bounds.minY + EditorLayoutMetrics.histogramInset + size.height / 2)
    }

    @Test func onlyNearHorizontalPansBelongToASlider() {
        // Along the axis, and a shallow diagonal: the slider takes it.
        #expect(EditorLayoutMetrics.isHorizontalPan(dx: 40, dy: 0))
        #expect(EditorLayoutMetrics.isHorizontalPan(dx: -40, dy: 6))
        #expect(EditorLayoutMetrics.isHorizontalPan(dx: 40, dy: -18)) // 24°

        // 40° used to count as horizontal under the |dy| > |dx| rule, which is
        // what made a panel of sliders hard to scroll.
        #expect(!EditorLayoutMetrics.isHorizontalPan(dx: 40, dy: 34))
        #expect(!EditorLayoutMetrics.isHorizontalPan(dx: 20, dy: 30))
        #expect(!EditorLayoutMetrics.isHorizontalPan(dx: 0, dy: 30))
        #expect(!EditorLayoutMetrics.isHorizontalPan(dx: 0, dy: 0))
    }

    @Test func valuesSnapOntoTheirDetentWithinAFixedPointDistance() {
        let range = -1.0...1.0
        // 220pt track, 6pt pull → ~0.055 of the −1…1 range either side of zero.
        #expect(
            EditorLayoutMetrics.snapped(0.04, detent: 0, range: range, trackWidth: 220) == 0
        )
        #expect(
            EditorLayoutMetrics.snapped(-0.05, detent: 0, range: range, trackWidth: 220) == 0
        )
        // The detent stays narrow so values just off zero are still reachable.
        #expect(
            EditorLayoutMetrics.snapped(0.09, detent: 0, range: range, trackWidth: 220) == 0.09
        )
        #expect(
            EditorLayoutMetrics.snapped(0.4, detent: 0, range: range, trackWidth: 220) == 0.4
        )
        // A non-zero detent works the same way, and a zero-width track is a no-op.
        #expect(
            EditorLayoutMetrics.snapped(0.98, detent: 1, range: 0...1, trackWidth: 220) == 1
        )
        #expect(
            EditorLayoutMetrics.snapped(0.5, detent: 0, range: range, trackWidth: 0) == 0.5
        )
    }

    @Test func fittedRectCentresTheImageWithoutOverflowing() {
        let rect = EditorLayoutMetrics.fittedRect(
            imageSize: CGSize(width: 3_000, height: 2_000),
            in: CGSize(width: 393, height: 460)
        )
        #expect(rect.width == 393)
        #expect(abs(rect.height - 262) < 1)
        #expect(abs(rect.midY - 230) < 0.01)
        // Same layout from the ratio alone, which is what the stage uses so a
        // re-render at another resolution cannot move the photo.
        let fromRatio = EditorLayoutMetrics.fittedRect(
            aspectRatio: 1.5,
            in: CGSize(width: 393, height: 460)
        )
        #expect(abs(fromRatio.width - rect.width) < 0.0001)
        #expect(abs(fromRatio.height - rect.height) < 0.0001)
        // Height-limited case: a tall photo in a wide box.
        let tall = EditorLayoutMetrics.fittedRect(
            aspectRatio: 0.5,
            in: CGSize(width: 400, height: 400)
        )
        #expect(abs(tall.height - 400) < 0.0001)
        #expect(abs(tall.width - 200) < 0.0001)
        #expect(abs(tall.midX - 200) < 0.0001)
    }

    @Test func panningCannotPushMoreThanHalfTheStageOffScreen() {
        let stage = CGSize(width: 400, height: 600)
        // Zoomed content twice the stage: the edge may pass the stage edge by half
        // a stage, and no further — so half the picture is always on screen.
        #expect(EditorLayoutMetrics.panLimit(content: 800, viewport: 400) == 400)
        // Exactly the stage size: half a stage of travel.
        #expect(EditorLayoutMetrics.panLimit(content: 400, viewport: 400) == 200)
        // Smaller than the stage but still over half of it.
        #expect(abs(EditorLayoutMetrics.panLimit(content: 320, viewport: 400) - 160) < 0.0001)
        // A letterboxed axis under half the stage can only slide to the edge, which
        // never takes the picture away.
        #expect(abs(EditorLayoutMetrics.panLimit(content: 120, viewport: 400) - 140) < 0.0001)

        // A fling that would leave a sliver comes back to the limit.
        let clamped = EditorLayoutMetrics.clampedZoomOffset(
            CGSize(width: 5_000, height: -5_000),
            imageSize: CGSize(width: 400, height: 300),
            zoomScale: 4,
            stage: stage
        )
        #expect(clamped.width == 800)
        #expect(clamped.height == -600)

        // Unzoomed, a photo that fits has nowhere to go.
        let atRest = EditorLayoutMetrics.clampedZoomOffset(
            CGSize(width: 300, height: 300),
            imageSize: CGSize(width: 400, height: 600),
            zoomScale: 1,
            stage: stage
        )
        #expect(atRest.width == 200)
        #expect(atRest.height == 300)
    }

    @Test func pinchingKeepsThePointUnderTheFingersStill() {
        let stage = CGSize(width: 400, height: 600)
        let center = CGPoint(x: 200, y: 300)

        /// Where a stage point ends up on screen for a given zoom and offset —
        /// the transform `EditorImageStage` applies, so the assertions below read
        /// as "the anchor did not move".
        func screenPoint(
            _ point: CGPoint,
            scale: CGFloat,
            offset: CGSize
        ) -> CGPoint {
            CGPoint(
                x: center.x + (point.x - center.x) * scale + offset.width,
                y: center.y + (point.y - center.y) * scale + offset.height
            )
        }

        // Pinching open on a corner: from 1× to 3× about (60, 90).
        let anchor = CGPoint(x: 60, y: 90)
        let openOffset = EditorLayoutMetrics.anchoredZoomOffset(
            anchor: anchor,
            stage: stage,
            startScale: 1,
            startOffset: .zero,
            scale: 3
        )
        // The content that was under the fingers at 1× is the anchor itself.
        let stillOpen = screenPoint(anchor, scale: 3, offset: openOffset)
        #expect(abs(stillOpen.x - anchor.x) < 0.0001)
        #expect(abs(stillOpen.y - anchor.y) < 0.0001)

        // And pinching closed again from an offset state pins the same way: start
        // at 3× with the offset above, squeeze back to 1.5× about (330, 500).
        let secondAnchor = CGPoint(x: 330, y: 500)
        let closedOffset = EditorLayoutMetrics.anchoredZoomOffset(
            anchor: secondAnchor,
            stage: stage,
            startScale: 3,
            startOffset: openOffset,
            scale: 1.5
        )
        // Whatever content sat under the second anchor at 3× has to still be there
        // at 1.5×, so both transforms must map it to the same screen point.
        let contentUnderAnchor = CGPoint(
            x: center.x + (secondAnchor.x - center.x - openOffset.width) / 3,
            y: center.y + (secondAnchor.y - center.y - openOffset.height) / 3
        )
        let stillClosed = screenPoint(
            contentUnderAnchor,
            scale: 1.5,
            offset: closedOffset
        )
        #expect(abs(stillClosed.x - secondAnchor.x) < 0.0001)
        #expect(abs(stillClosed.y - secondAnchor.y) < 0.0001)

        // A pinch centred on the stage's own middle is the old behaviour: no offset.
        let centred = EditorLayoutMetrics.anchoredZoomOffset(
            anchor: center,
            stage: stage,
            startScale: 1,
            startOffset: .zero,
            scale: 4
        )
        #expect(abs(centred.width) < 0.0001)
        #expect(abs(centred.height) < 0.0001)
    }

    @Test func maskPointsRoundTripBetweenNormalizedAndViewSpace() {
        let rect = CGRect(x: 30, y: 100, width: 300, height: 200)
        let point = NormalizedPoint(x: 0.25, y: 0.75)
        let view = EditorLayoutMetrics.maskViewPoint(point, in: rect)
        #expect(view == CGPoint(x: 105, y: 250))
        let back = EditorLayoutMetrics.maskNormalizedPoint(view, in: rect)
        #expect(abs(back.x - 0.25) < 0.0001)
        #expect(abs(back.y - 0.75) < 0.0001)
        // Off-photo drags pin to the edge instead of going out of range.
        let outside = EditorLayoutMetrics.maskNormalizedPoint(
            CGPoint(x: -50, y: 500),
            in: rect
        )
        #expect(outside.x == 0)
        #expect(outside.y == 1)
    }

    @Test func radialGuideScalesEachAxisByItsOwnImageDimension() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 200)
        let outer = EditorLayoutMetrics.radialGuideRect(
            center: NormalizedPoint(x: 0.5, y: 0.5),
            radiusX: 0.25,
            radiusY: 0.25,
            in: rect
        )
        // Same normalized radius, different dimensions: the ellipse is not a circle.
        #expect(outer.width == 200)
        #expect(outer.height == 100)
        #expect(outer.midX == 200)
        #expect(outer.midY == 100)
        // Feather shrinks the box to the solid core the renderer keeps.
        let inner = EditorLayoutMetrics.radialGuideRect(
            center: NormalizedPoint(x: 0.5, y: 0.5),
            radiusX: 0.25,
            radiusY: 0.25,
            feather: 0.5,
            in: rect
        )
        #expect(inner.width == 100)
        #expect(inner.height == 50)
        #expect(inner.midX == outer.midX)
    }

    @Test func maskRadiusClampsToTheSameFloorAsPlacement() {
        #expect(EditorLayoutMetrics.clampedMaskRadius(0) == 0.02)
        #expect(EditorLayoutMetrics.clampedMaskRadius(0.4) == 0.4)
        #expect(EditorLayoutMetrics.clampedMaskRadius(3) == 1)
    }

    @Test func featherReadsZeroOnTheRimAndOneAtTheCentre() {
        let center = CGPoint(x: 100, y: 100)
        let radii = CGSize(width: 80, height: 40)
        #expect(
            EditorLayoutMetrics.maskFeather(
                at: CGPoint(x: 180, y: 100),
                center: center,
                radii: radii
            ) == 0
        )
        #expect(
            EditorLayoutMetrics.maskFeather(at: center, center: center, radii: radii) == 1
        )
        // Halfway out along the short axis is the same reading as halfway out
        // along the long one: the gauge follows the ellipse, not a circle.
        let vertical = EditorLayoutMetrics.maskFeather(
            at: CGPoint(x: 100, y: 120),
            center: center,
            radii: radii
        )
        let horizontal = EditorLayoutMetrics.maskFeather(
            at: CGPoint(x: 140, y: 100),
            center: center,
            radii: radii
        )
        #expect(abs(vertical - 0.5) < 0.0001)
        #expect(abs(vertical - horizontal) < 0.0001)
    }

    @Test func brushCursorGeometryMatchesTheRenderer() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 300)
        // Size is a fraction of the short edge, so 0.2 is a 60pt footprint.
        #expect(EditorLayoutMetrics.brushDiameter(size: 0.2, in: rect) == 60)
        // The core ring is the renderer's hard centre before the feather ramp;
        // no feather means the whole stamp is core, full feather keeps a nub.
        #expect(EditorLayoutMetrics.brushCoreScale(feather: 0) == 1)
        #expect(abs(EditorLayoutMetrics.brushCoreScale(feather: 0.5) - 0.6) < 0.0001)
        #expect(abs(EditorLayoutMetrics.brushCoreScale(feather: 1) - 0.2) < 0.0001)
    }

    @Test func zoomingInShrinksWhatAStrokeRecordsSoDetailIsReachable() {
        // The Size slider is a screen size: at 4× the same ring under the finger
        // covers a quarter of the image it did at 1×, which is the whole point of
        // zooming in to paint an eyelash.
        #expect(EditorLayoutMetrics.paintedSize(0.2, zoomScale: 1) == 0.2)
        #expect(abs(EditorLayoutMetrics.paintedSize(0.2, zoomScale: 4) - 0.05) < 0.000001)
        // And at the 10× ceiling a half-of-the-short-edge brush is down to 2% of it.
        #expect(
            abs(
                EditorLayoutMetrics.paintedSize(
                    0.2,
                    zoomScale: EditorLayoutMetrics.maximumZoomScale
                ) - 0.02
            ) < 0.000001
        )
        // Zooming out past 1× is not a thing, so it never *grows* a stroke.
        #expect(EditorLayoutMetrics.paintedSize(0.2, zoomScale: 0.5) == 0.2)
    }

    @Test func theBrushKeepsItsScreenSizeAtEveryZoom() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 300)
        let size = 0.2
        // The invariant the whole screen-sized-brush design rests on: the cursor is
        // drawn inside a stack scaled by the zoom, so `diameter × zoom` — what the
        // eye actually sees — must not move.
        let onScreen = EditorLayoutMetrics.brushDiameter(size: size, in: rect)
        for zoom in [CGFloat(1), 2, 4, EditorLayoutMetrics.maximumZoomScale] {
            let drawn = EditorLayoutMetrics.brushCursorDiameter(
                size: size,
                in: rect,
                zoomScale: zoom
            )
            #expect(abs(drawn * zoom - onScreen) < 0.0001)
        }

        // And the ring keeps promising what the stroke records: the footprint of
        // `paintedSize` at that zoom is the same 60pt on screen.
        for zoom in [CGFloat(1), 4, EditorLayoutMetrics.maximumZoomScale] {
            let painted = EditorLayoutMetrics.brushDiameter(
                size: EditorLayoutMetrics.paintedSize(size, zoomScale: zoom),
                in: rect
            )
            #expect(abs(painted * zoom - onScreen) < 0.0001)
        }

        // The 8pt floor is a *screen* floor — it survives the multiply back out,
        // so the smallest brush is still visible at 800% instead of vanishing.
        let tiny = EditorLayoutMetrics.brushCursorDiameter(
            size: 0.001,
            in: rect,
            zoomScale: EditorLayoutMetrics.maximumZoomScale
        )
        #expect(abs(tiny * EditorLayoutMetrics.maximumZoomScale - 8) < 0.0001)

        // Zoom below 1× cannot inflate the ring, matching `paintedSize`.
        #expect(
            EditorLayoutMetrics.brushCursorDiameter(size: size, in: rect, zoomScale: 0.5)
                == onScreen
        )
    }

    @Test func brushControlsReadOutAsBareNumbersOutOfAHundred() {
        // Lightroom's brush numbers, and for the same reason: what each control is a
        // fraction *of* differs, so a `%` sign would be read as "of the photo".
        #expect(
            EditorLayoutMetrics.brushAmountText(0.25, in: EditorLayoutMetrics.brushSizeRange)
                == "50"
        )
        // The top of every brush slider is 100, whatever its underlying range —
        // that is what lets Size, Feather and Flow be compared at a glance.
        #expect(
            EditorLayoutMetrics.brushAmountText(
                EditorLayoutMetrics.brushSizeRange.upperBound,
                in: EditorLayoutMetrics.brushSizeRange
            ) == "100"
        )
        #expect(EditorLayoutMetrics.brushAmountText(0.45, in: 0...1) == "45")
        #expect(EditorLayoutMetrics.brushAmountText(0, in: 0...1) == "0")
        // Nothing overflows the value column: out-of-range input clamps.
        #expect(EditorLayoutMetrics.brushAmountText(3, in: 0...1) == "100")
        #expect(EditorLayoutMetrics.brushAmountText(-1, in: 0...1) == "0")
        #expect(EditorLayoutMetrics.brushAmountText(0.5, in: 0...0) == "0")
    }

    @Test func theZoomReadoutIsRoundedPercent() {
        #expect(EditorLayoutMetrics.zoomPercent(1) == 100)
        #expect(EditorLayoutMetrics.zoomPercent(3.456) == 346)
        #expect(
            EditorLayoutMetrics.zoomPercent(EditorLayoutMetrics.maximumZoomScale) == 1_000
        )
    }

    @Test func gradientRailsRunPerpendicularToTheAxis() {
        // Vertical axis (the default top-to-bottom gradient): rails are horizontal.
        let (a, b) = EditorLayoutMetrics.perpendicularSegment(
            through: CGPoint(x: 100, y: 50),
            axis: CGVector(dx: 0, dy: 1),
            length: 200
        )
        #expect(abs(a.y - 50) < 0.0001)
        #expect(abs(b.y - 50) < 0.0001)
        #expect(abs(abs(a.x - b.x) - 200) < 0.0001)
        // A diagonal axis: the rail's dot product with the axis is zero.
        let axis = CGVector(dx: 3, dy: 4)
        let (c, d) = EditorLayoutMetrics.perpendicularSegment(
            through: CGPoint(x: 10, y: 10),
            axis: axis,
            length: 100
        )
        let rail = CGVector(dx: d.x - c.x, dy: d.y - c.y)
        #expect(abs(rail.dx * axis.dx + rail.dy * axis.dy) < 0.0001)
        #expect(abs(hypot(rail.dx, rail.dy) - 100) < 0.0001)
        // Degenerate axis still produces a horizontal rail rather than nothing.
        let (e, f) = EditorLayoutMetrics.perpendicularSegment(
            through: .zero,
            axis: CGVector(dx: 0, dy: 0),
            length: 10
        )
        #expect(abs(e.y - f.y) < 0.0001)
        #expect(abs(abs(e.x - f.x) - 10) < 0.0001)
    }

    /// The curve plot is sized to the stage and centred on the photo: a landscape
    /// photo gets a screen-wide square spilling onto the letterbox, a portrait one
    /// the same square inside the photo, and the square never leaves the stage.
    @Test func curvePlotIsStageSizedAndImageCentred() {
        let stage = CGRect(x: 0, y: 0, width: 402, height: 600)
        let landscape = CGRect(x: 0, y: 166, width: 402, height: 268)
        let plot = EditorLayoutMetrics.curvePlotRect(in: landscape, stage: stage)
        #expect(plot.width == 402 - 2 * EditorLayoutMetrics.curvePlotInset)
        #expect(plot.width == plot.height)
        #expect(plot.midX == landscape.midX)
        #expect(plot.midY == landscape.midY)

        let tall = CGRect(x: 100, y: 0, width: 202, height: 600)
        let tallPlot = EditorLayoutMetrics.curvePlotRect(in: tall, stage: stage)
        #expect(tallPlot.width == plot.width)
        #expect(tallPlot.midX == tall.midX)

        // Image hugging the top edge: the plot is nudged down to stay on the stage.
        let top = CGRect(x: 0, y: 0, width: 402, height: 120)
        let topPlot = EditorLayoutMetrics.curvePlotRect(in: top, stage: stage)
        #expect(topPlot.minY == EditorLayoutMetrics.curvePlotInset)
    }

    // MARK: Which windows get the sidebar

    /// Asserted on the real windows ShotDex ships to, not on round numbers —
    /// the whole point of the rule is which devices fall on which side of it.
    /// The 11" iPad in landscape, the window the 2026-09-22 panel rebuild was
    /// measured on.
    private static let iPad11Landscape = CGSize(width: 1210, height: 834)
    private static let phone = CGSize(width: 402, height: 874)
    private static let iPadLandscape = CGSize(width: 1376, height: 1032)
    private static let iPadPortrait = CGSize(width: 1032, height: 1376)
    /// The Duo's inner display, measured: 951×669 landscape.
    private static let duoInner = CGSize(width: 951, height: 669)
    private static let duoCover = CGSize(width: 466, height: 678)

    /// Every window with room for a panel gets one, portrait included: rotating
    /// an iPad must not swap five collapsible sections for a fourteen-chip
    /// wheel. What still fails the gate fails on a number — a phone is too
    /// narrow in both directions, the Duo's cover too narrow, a squat window too
    /// short.
    @Test func everyWindowWithRoomGetsTheSidebar() {
        #expect(EditorLayoutMetrics.usesSidebar(width: Self.iPadLandscape.width, height: Self.iPadLandscape.height))
        #expect(EditorLayoutMetrics.usesSidebar(width: Self.iPad11Landscape.width, height: Self.iPad11Landscape.height))
        #expect(EditorLayoutMetrics.usesSidebar(width: Self.duoInner.width, height: Self.duoInner.height))
        // The change of 2026-09-22: portrait is in.
        #expect(EditorLayoutMetrics.usesSidebar(width: Self.iPadPortrait.width, height: Self.iPadPortrait.height))
        #expect(EditorLayoutMetrics.usesSidebar(width: 834, height: 1194))

        #expect(!EditorLayoutMetrics.usesSidebar(width: Self.phone.width, height: Self.phone.height))
        #expect(!EditorLayoutMetrics.usesSidebar(width: Self.duoCover.width, height: Self.duoCover.height))
        // A phone in landscape is nowhere near wide enough; a squat window
        // clears the width and fails on height.
        #expect(!EditorLayoutMetrics.usesSidebar(width: 874, height: 402))
        #expect(!EditorLayoutMetrics.usesSidebar(width: 900, height: 560))
    }

    /// Five sections, and the panel says so in one place: the catalog. A screen
    /// that hand-listed them is how Color went missing from one device once.
    @Test func thePanelListsFiveSections() {
        #expect(EditorAdjustmentCatalog.sidebarSections == [.light, .color, .effects, .detail, .optics])
    }

    /// A dependent row is dead until the slider it belongs to has a value.
    @Test func dependentRowsWaitForTheirParent() {
        var adjustments = PhotoAdjustments.zero
        for kind in [PhotoAdjustmentKind.vignetteMidpoint, .vignetteFeather, .vignetteRoundness, .vignetteHighlights] {
            #expect(EditorAdjustmentCatalog.parentKind(of: kind) == .vignette)
            #expect(!EditorAdjustmentCatalog.isEnabled(kind, in: adjustments))
        }
        for kind in [PhotoAdjustmentKind.grainSize, .grainRoughness] {
            #expect(EditorAdjustmentCatalog.parentKind(of: kind) == .grain)
            #expect(!EditorAdjustmentCatalog.isEnabled(kind, in: adjustments))
        }
        // Exposure answers to nobody.
        #expect(EditorAdjustmentCatalog.parentKind(of: .exposure) == nil)
        #expect(EditorAdjustmentCatalog.isEnabled(.exposure, in: adjustments))

        adjustments.vignette = -0.2
        #expect(EditorAdjustmentCatalog.isEnabled(.vignetteMidpoint, in: adjustments))
        #expect(!EditorAdjustmentCatalog.isEnabled(.grainSize, in: adjustments))
    }

    /// The short column keeps the histogram and pays for it by shrinking it, and
    /// buys another 20pt back across five cards by tightening their spacing.
    @Test func theShortColumnShrinksChromeInsteadOfDroppingIt() {
        let duo = Self.duoInner.height
        let iPad = Self.iPad11Landscape.height

        #expect(EditorLayoutMetrics.isShortColumn(duo))
        #expect(!EditorLayoutMetrics.isShortColumn(iPad))

        #expect(EditorLayoutMetrics.sidebarHistogramHeight(forColumnHeight: duo) == 56)
        #expect(EditorLayoutMetrics.sidebarHistogramHeight(forColumnHeight: iPad) == 92)
        #expect(EditorLayoutMetrics.sidebarCardSpacing(forColumnHeight: duo) == 6)
        #expect(EditorLayoutMetrics.sidebarCardSpacing(forColumnHeight: iPad) == 8)

        // Five collapsed cards still fit the Duo's scroll area with room over:
        // 5 × (44 header + 6 gap) against the column left after the fixed parts.
        let fixed = EditorLayoutMetrics.sidebarHistogramHeight(forColumnHeight: duo)
            + EditorLayoutMetrics.sidebarModeHeaderHeight
        let cards = 5 * (EditorLayoutMetrics.sidebarSectionHeaderHeight
            + EditorLayoutMetrics.sidebarCardSpacing(forColumnHeight: duo))
        #expect(fixed <= 180)
        #expect(cards <= duo - EditorLayoutMetrics.editorTopBandHeight - fixed)
    }

    /// A slider row is the target, and a precise instrument does not have to
    /// shove it as far as a fingertip does.
    @Test func aSliderRowIsBigEnoughToHitAndQuickEnoughToNudge() {
        // The whole row answers a drag, so the row height is the hit height.
        #expect(EditorLayoutMetrics.sidebarSliderRowHeight >= EditorLayoutMetrics.sidebarSliderHitHeight
            || max(EditorLayoutMetrics.sidebarSliderRowHeight, EditorLayoutMetrics.sidebarSliderHitHeight) == 46)
        #expect(EditorLayoutMetrics.sidebarSliderHitHeight == 44)

        // A finger must move 6pt before a value changes — it drifts while it
        // rests. A pencil or a pointer does not, and gets 2.
        #expect(EditorLayoutMetrics.sliderActivationDistance(isPrecise: false) == 6)
        #expect(EditorLayoutMetrics.sliderActivationDistance(isPrecise: true) == 2)
        #expect(
            EditorLayoutMetrics.sliderActivationDistance(isPrecise: true)
                < EditorLayoutMetrics.sliderActivationDistance(isPrecise: false)
        )
    }

    /// Primary actions are told apart by colour, not by size.
    @Test func primaryActionsAreSmall() {
        #expect(EditorLayoutMetrics.editorPrimaryButtonHeight == 32)
        #expect(EditorLayoutMetrics.editorPrimaryButtonMaxWidth <= 96)
        #expect(EditorLayoutMetrics.sidebarCommitBarHeight == 48)
        // And a slider's target is a full 44 even though its cursor is a 2pt bar.
        #expect(EditorLayoutMetrics.sidebarSliderHitHeight == 44)
    }

    // MARK: Panel rebuild 2026-09-22 — what already works and must keep working

    /// Which sections are open is a property of the editing *session*, not of
    /// the photo: it never reaches the recipe, so it cannot reach History or a
    /// saved edit either. Locked here because the rebuild makes the open/closed
    /// state visible enough to be mistaken for an edit.
    @Test func openSectionsNeverReachTheRecipe() throws {
        var recipe = PhotoEditRecipe()
        recipe.adjustments.exposure = 0.4
        let json = try JSONEncoder().encode(recipe)
        let text = try #require(String(data: json, encoding: .utf8))

        for key in ["expanded", "sidebar", "section", "collapsed", "panel", "rail"] {
            #expect(!text.lowercased().contains(key), "recipe carries panel state: \(key)")
        }
    }

    /// The canvas the photo gets on an 11" iPad in landscape, measured on
    /// 2026-09-22: 842 wide (window minus panel minus rail) by 786 tall (window
    /// minus the command band). A 3:2 frame fills 553 of those 786pt — 71%, so
    /// the rebuild's job is not to grow that number but to **not shrink it**.
    /// Cards, the footer move and the Save pill must all come out of chrome the
    /// panel already had.
    @Test func theCanvasDoesNotShrinkBelowTheMeasuredBaseline() {
        let canvasWidth = Self.iPad11Landscape.width
            - EditorLayoutMetrics.sidebarDefaultWidth
            - EditorLayoutMetrics.sidebarRailWidth
        let canvasHeight = Self.iPad11Landscape.height - EditorLayoutMetrics.editorTopBandHeight

        #expect(canvasWidth >= 842)
        #expect(canvasHeight >= 782)

        // And the panel is still paid for in width, never in canvas height: the
        // sidebar range has not crept upwards.
        #expect(EditorLayoutMetrics.sidebarWidthRange.upperBound <= 420)
    }

    /// The Duo's inner display is the reason the short-column rule exists: it
    /// passes the sidebar gate and then leaves the panel less than 600pt, of
    /// which the histogram and the Look row would be 165.
    @Test func duoInnerIsAShortColumnAndTheIPadIsNot() {
        #expect(Self.duoInner.height < EditorLayoutMetrics.sidebarShortColumnHeight)
        #expect(Self.iPadLandscape.height > EditorLayoutMetrics.sidebarShortColumnHeight)

        // What the fold buys, in points: the fixed furniture without those two
        // rows has to leave room for Light — a 44pt header and eight 46pt rows.
        let barAndInsets: CGFloat = 52 + 24 + 24
        let column = Self.duoInner.height - barAndInsets
        let modeHeader = EditorLayoutMetrics.sidebarModeHeaderHeight
        let footer = AppTheme.Size.primaryActionHeight + AppTheme.Spacing.md + 24
        let foldedFurniture = modeHeader + footer + 2
        let lightGroup = EditorLayoutMetrics.sidebarSectionHeaderHeight
            + 8 * EditorLayoutMetrics.sidebarSliderRowHeight
        #expect(column - foldedFurniture > lightGroup)

        // And that it was not, before: histogram block plus Look row is what
        // pushed the same column under the group it opens on.
        let histogramBlock = EditorLayoutMetrics.sidebarHistogramHeight
            + AppTheme.Spacing.md + AppTheme.Spacing.sm
        let unfolded = foldedFurniture + histogramBlock
            + EditorLayoutMetrics.sidebarLookRowHeight + 1
        #expect(column - unfolded < lightGroup)
    }
}
