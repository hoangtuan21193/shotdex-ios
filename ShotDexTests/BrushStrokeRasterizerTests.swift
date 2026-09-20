import CoreGraphics
import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

@Suite struct BrushStrokeRasterizerTests {
    /// Coverage the passes add up to at the centre of the stamp, composited the way
    /// Core Graphics composites them: each pass over what the earlier ones left.
    private func coverage(_ rings: [BrushStrokeRasterizer.Ring]) -> Double {
        rings.reduce(0.0) { covered, ring in
            covered + (1 - covered) * Double(ring.alpha)
        }
    }

    @Test func theStampReachesFlowAtItsCoreAndFadesToNothingAtItsEdge() {
        let rings = BrushStrokeRasterizer.rings(
            size: 0.25,
            feather: 0.45,
            flow: 0.8,
            isEraser: false,
            shortEdge: 1_600
        )
        #expect(rings.count > 1)
        #expect(abs(coverage(rings) - 0.8) < 0.0001)

        // Outermost pass first, shrinking to the hard core, and every pass is a
        // legal alpha.
        let widths = rings.map(\.lineWidth)
        #expect(widths == widths.sorted(by: >))
        #expect(rings.allSatisfy { $0.alpha >= 0 && $0.alpha <= 1 })

        // The widest pass is the full stamp — the outer ring `EditorBrushCursor`
        // draws — and the last one is the core it draws inside it.
        let full = EditorLayoutMetrics.brushDiameter(
            size: 0.25,
            in: CGRect(x: 0, y: 0, width: 1_600, height: 1_600)
        )
        let core = full * EditorLayoutMetrics.brushCoreScale(feather: 0.45)
        #expect(abs(widths.first! - full) < full / Double(rings.count))
        #expect(abs(widths.last! - core) < 0.0001)
    }

    @Test func aStrokePaintedZoomedInIsExactlyAsStrongAsOneAtFit() {
        // The regression this guards: the renderer used to blur the whole mask with
        // one radius taken from the *largest* stroke, so a stroke recorded at 500%
        // (a fifth of the width, because the Size slider is a screen size) was
        // smeared to nothing next to a stroke painted at 100%.
        let atFit = BrushStrokeRasterizer.rings(
            size: 0.25,
            feather: 0.45,
            flow: 0.8,
            isEraser: false,
            shortEdge: 1_600
        )
        let zoomed = BrushStrokeRasterizer.rings(
            size: EditorLayoutMetrics.paintedSize(0.25, zoomScale: 5),
            feather: 0.45,
            flow: 0.8,
            isEraser: false,
            shortEdge: 1_600
        )

        // Same strength — that is the whole point.
        #expect(abs(coverage(atFit) - coverage(zoomed)) < 0.0001)

        // And the same shape, only narrower. A thinner stamp has a thinner soft edge
        // so it is cut into fewer passes, which is why the two cannot be compared
        // pass for pass: what has to match is the *profile* both sample, so each is
        // checked against the same law — coverage `0.8 · smoothstep(t)` at a width
        // running from the full stamp down to the core.
        let core = EditorLayoutMetrics.brushCoreScale(feather: 0.45)
        for rings in [atFit, zoomed] {
            let full = rings[0].lineWidth / (1 - (1 - core) / Double(rings.count))
            var covered = 0.0
            for (index, ring) in rings.enumerated() {
                covered += (1 - covered) * Double(ring.alpha)
                let position = Double(index + 1) / Double(rings.count)
                let expected = 0.8 * position * position * (3 - 2 * position)
                #expect(abs(covered - expected) < 0.0001)
                #expect(
                    abs(ring.lineWidth / full - (1 - (1 - core) * position)) < 0.0001
                )
            }
        }

        // The zoomed stamp really is a fifth as wide — same ink, finer detail.
        #expect(abs(atFit.last!.lineWidth / zoomed.last!.lineWidth - 5) < 0.0001)
    }

    @Test func anEraserTakesThePixelAwayCompletelyAtItsCentre() {
        let rings = BrushStrokeRasterizer.rings(
            size: 0.2,
            feather: 0.5,
            flow: 0.3,
            isEraser: true,
            shortEdge: 1_600
        )
        // Flow shapes a paint stroke, not a removal: the core erases fully, the way
        // the `.clear` blend it replaced did.
        #expect(abs(coverage(rings) - 1) < 0.0001)
        #expect(rings.count > 1)
    }

    @Test func aHardBrushIsASinglePass() {
        let hard = BrushStrokeRasterizer.rings(
            size: 0.25,
            feather: 0,
            flow: 0.8,
            isEraser: false,
            shortEdge: 1_600
        )
        #expect(hard.count == 1)
        #expect(abs(hard[0].alpha - 0.8) < 0.0001)
        #expect(abs(hard[0].lineWidth - 400) < 0.0001)

        // A stamp whose soft edge is thinner than a pixel is not worth ramping, and
        // must still land at full strength rather than being rounded away.
        let tiny = BrushStrokeRasterizer.rings(
            size: 0.002,
            feather: 0.45,
            flow: 0.8,
            isEraser: false,
            shortEdge: 1_000
        )
        #expect(tiny.count == 1)
        #expect(abs(coverage(tiny) - 0.8) < 0.0001)
    }

    @Test func theRampNeverCostsMoreThanItsCap() {
        // A whole-frame brush must not turn into hundreds of path fills per render.
        let huge = BrushStrokeRasterizer.rings(
            size: 0.5,
            feather: 1,
            flow: 1,
            isEraser: false,
            shortEdge: 4_800
        )
        #expect(huge.count == BrushStrokeRasterizer.maximumRings)
        #expect(abs(coverage(huge) - 1) < 0.0001)
    }
}

/// Apple Pencil force, from the touch through the model to the width the
/// rasterizer draws with.
@Suite struct BrushPressureTests {
    @Test func aStrokeWithNoPressuresIsDrawnAtItsNominalWidth() {
        let stroke = BrushStroke(
            points: [NormalizedPoint(x: 0.1, y: 0.1), NormalizedPoint(x: 0.9, y: 0.9)],
            size: 0.2, feather: 0.3, flow: 1, isEraser: false
        )
        #expect(stroke.pressures.isEmpty, "a finger stroke carries none")
    }

    @Test func pressureScalesTheWidthWithinItsRange() {
        let range = BrushStroke.pressureWidthRange
        #expect(BrushStroke.widthScale(forPressure: 0) == range.lowerBound)
        #expect(BrushStroke.widthScale(forPressure: 1) == range.upperBound)
        #expect(BrushStroke.widthScale(forPressure: 0.5) > range.lowerBound)
        #expect(BrushStroke.widthScale(forPressure: 0.5) < range.upperBound)
        // A Pencil at rest still marks: the floor is not zero.
        #expect(range.lowerBound > 0.2)
    }

    @Test func pressureIsClampedRatherThanTrusted() {
        #expect(BrushStroke.widthScale(forPressure: -1) == BrushStroke.pressureWidthRange.lowerBound)
        #expect(BrushStroke.widthScale(forPressure: 9) == BrushStroke.pressureWidthRange.upperBound)
    }

    /// Recipes written before pressure existed have to decode unchanged — a
    /// mask is the user's work, not a cache.
    @Test func aStrokeSavedBeforePressureExistedStillDecodes() throws {
        let json = """
        {"points":[{"x":0.1,"y":0.2}],"size":0.25,"feather":0.4,"flow":0.8,"isEraser":false}
        """
        let stroke = try JSONDecoder().decode(BrushStroke.self, from: Data(json.utf8))
        #expect(stroke.pressures.isEmpty)
        #expect(stroke.size == 0.25)
        #expect(stroke.points.count == 1)
    }

    @Test func pressuresSurviveARoundTrip() throws {
        let stroke = BrushStroke(
            points: [NormalizedPoint(x: 0, y: 0), NormalizedPoint(x: 1, y: 1)],
            size: 0.3, feather: 0.2, flow: 0.9, isEraser: true,
            pressures: [0.2, 0.85]
        )
        let data = try JSONEncoder().encode(stroke)
        let decoded = try JSONDecoder().decode(BrushStroke.self, from: data)
        #expect(decoded == stroke)
        #expect(decoded.pressures == [0.2, 0.85])
    }
}

/// What the photo-editing extension may take on. Its memory ceiling is a
/// fraction of the app's, and a mask, a drawing or an overlay each rasterize
/// a bitmap the size of the whole image.
@Suite struct ExtensionRecipeLimitTests {
    @Test func aPlainRecipeHasNoFullExtentLayers() {
        var recipe = PhotoEditRecipe.identity
        recipe.filter = .vivid
        recipe.adjustments.exposure = 0.4
        #expect(!recipe.needsFullExtentLayers)
    }

    @Test func aMaskADrawingOrAnOverlayEachCount() {
        var masked = PhotoEditRecipe.identity
        masked.masks = [PhotoMask(name: "Brush", component: PhotoMaskComponent(kind: .brush))]
        #expect(masked.needsFullExtentLayers)

        var drawn = PhotoEditRecipe.identity
        drawn.drawing = PhotoDrawing(data: Data("pk".utf8), canvasWidth: 100, canvasHeight: 100)
        #expect(drawn.needsFullExtentLayers)

        var captioned = PhotoEditRecipe.identity
        var caption = PhotoOverlay(kind: .text)
        // An overlay with no text in it draws nothing, so it does not count —
        // the rule is about layers the renderer would actually rasterize.
        caption.text = "Reykjavík, 2026"
        captioned.overlays = [caption]
        #expect(captioned.needsFullExtentLayers)

        var blankCaption = PhotoEditRecipe.identity
        blankCaption.overlays = [PhotoOverlay(kind: .text)]
        #expect(!blankCaption.needsFullExtentLayers, "an empty caption is not a layer")
    }

    /// A layer that would not be drawn costs the renderer nothing, so it must
    /// not cost the user a continuable edit either.
    @Test func hiddenLayersDoNotCount() {
        var hiddenMask = PhotoEditRecipe.identity
        var mask = PhotoMask(name: "Brush", component: PhotoMaskComponent(kind: .brush))
        mask.isVisible = false
        hiddenMask.masks = [mask]
        #expect(!hiddenMask.needsFullExtentLayers)

        var hiddenDrawing = PhotoEditRecipe.identity
        var drawing = PhotoDrawing(data: Data("pk".utf8), canvasWidth: 100, canvasHeight: 100)
        drawing.isVisible = false
        hiddenDrawing.drawing = drawing
        #expect(!hiddenDrawing.needsFullExtentLayers)
    }

    /// An empty drawing is not a drawing — reverting every stroke must not
    /// leave the photo locked out of the extension forever.
    @Test func anEmptyDrawingDoesNotCount() {
        var recipe = PhotoEditRecipe.identity
        recipe.drawing = PhotoDrawing(data: Data(), canvasWidth: 100, canvasHeight: 100)
        #expect(!recipe.needsFullExtentLayers)
    }
}

/// The segment-by-segment pressured path in `BrushStrokeRasterizer.draw`,
/// rendered into the exact context shape `PhotoRenderService.brushMask` uses
/// (8-bit DeviceGray, no alpha channel, background painted black) so a
/// pixel's value *is* the mask's coverage at that point.
@Suite struct BrushStrokeRasterizerDrawTests {
    private func renderedMask(_ strokes: [BrushStroke], width: Int, height: Int) -> [UInt8] {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            Issue.record("could not create test bitmap context")
            return []
        }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let shortEdge = CGFloat(min(width, height))
        BrushStrokeRasterizer.draw(strokes, in: context, shortEdge: shortEdge) { point in
            CGPoint(x: point.x * Double(width), y: point.y * Double(height))
        }
        guard let data = context.data else {
            Issue.record("bitmap context had no backing data")
            return []
        }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height)
        return Array(UnsafeBufferPointer(start: buffer, count: width * height))
    }

    /// How many rows in the column at `x` are painted above `threshold` — the
    /// stroke's on-screen thickness at that point.
    private func paintedHeight(
        _ pixels: [UInt8], width: Int, height: Int, x: Int, threshold: UInt8 = 40
    ) -> Int {
        (0 ..< height).filter { y in pixels[y * width + x] >= threshold }.count
    }

    @Test func aHardPressSegmentIsWiderThanALightPressSegment() {
        // Five points along one horizontal line: the first two segments are
        // pressed lightly, the last two hard.
        let stroke = BrushStroke(
            points: [
                NormalizedPoint(x: 0.1, y: 0.5),
                NormalizedPoint(x: 0.3, y: 0.5),
                NormalizedPoint(x: 0.5, y: 0.5),
                NormalizedPoint(x: 0.7, y: 0.5),
                NormalizedPoint(x: 0.9, y: 0.5),
            ],
            size: 0.3, feather: 0, flow: 1, isEraser: false,
            pressures: [0, 0, 0, 1, 1]
        )
        let width = 100, height = 40
        let pixels = renderedMask([stroke], width: width, height: height)
        #expect(!pixels.isEmpty)
        let light = paintedHeight(pixels, width: width, height: height, x: 20)
        let hard = paintedHeight(pixels, width: width, height: height, x: 80)
        #expect(hard > light, "a hard press must paint a visibly wider line than a light one")
    }

    @Test func aStrokeWithNoPressuresIsOneUniformWidthEndToEnd() {
        let stroke = BrushStroke(
            points: [
                NormalizedPoint(x: 0.1, y: 0.5),
                NormalizedPoint(x: 0.5, y: 0.5),
                NormalizedPoint(x: 0.9, y: 0.5),
            ],
            size: 0.3, feather: 0, flow: 1, isEraser: false
        )
        let width = 100, height = 40
        let pixels = renderedMask([stroke], width: width, height: height)
        let start = paintedHeight(pixels, width: width, height: height, x: 20)
        let end = paintedHeight(pixels, width: width, height: height, x: 80)
        #expect(start == end, "a finger stroke has no pressures and draws at its nominal width throughout")
    }

    /// The state a corrupted or hand-edited recipe could hand the renderer:
    /// a `pressures` array shorter than `points`. It must fall back to the
    /// unpressured path rather than indexing out of bounds.
    @Test func mismatchedPressureCountFallsBackToTheUnpressuredPath() {
        var mismatched = BrushStroke(
            points: [
                NormalizedPoint(x: 0.1, y: 0.5),
                NormalizedPoint(x: 0.5, y: 0.5),
                NormalizedPoint(x: 0.9, y: 0.5),
            ],
            size: 0.3, feather: 0, flow: 1, isEraser: false
        )
        mismatched.pressures = [0.9] // one pressure, three points
        let unpressured = BrushStroke(
            points: mismatched.points,
            size: 0.3, feather: 0, flow: 1, isEraser: false
        )

        let width = 100, height = 40
        let mismatchedPixels = renderedMask([mismatched], width: width, height: height)
        let unpressuredPixels = renderedMask([unpressured], width: width, height: height)
        #expect(
            mismatchedPixels == unpressuredPixels,
            "a mismatched pressures count must be ignored, not partially applied"
        )
    }
}
