import CoreGraphics
import Foundation
import PencilKit
import Testing
@testable import ShotDexKit

@testable import ShotDex

/// Drawing layers (FS-05.01 §4–5): each drawing is a layer in the overlay stack.
struct PhotoDrawingModelsTests {

    /// Top-level keys a recipe writes, order-independent.
    private func keys(of recipe: PhotoEditRecipe) throws -> Set<String> {
        let data = try JSONEncoder().encode(recipe)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return Set(object?.keys ?? [:].keys)
    }

    private func drawing(_ bytes: [UInt8] = [1, 2, 3]) -> PhotoDrawing {
        PhotoDrawing(data: Data(bytes), canvasWidth: 300, canvasHeight: 200)
    }

    /// A real PencilKit drawing: one red stroke across `rect` of a 300×200 canvas.
    private func stroke(across rect: CGRect, color: UIColor = .red, width: CGFloat = 12) -> PhotoDrawing {
        let ink = PKInk(.pen, color: color)
        let points = [
            PKStrokePoint(location: CGPoint(x: rect.minX, y: rect.midY), timeOffset: 0,
                          size: CGSize(width: width, height: width), opacity: 1, force: 1,
                          azimuth: 0, altitude: .pi / 2),
            PKStrokePoint(location: CGPoint(x: rect.maxX, y: rect.midY), timeOffset: 0.1,
                          size: CGSize(width: width, height: width), opacity: 1, force: 1,
                          azimuth: 0, altitude: .pi / 2),
        ]
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        let pk = PKDrawing(strokes: [PKStroke(ink: ink, path: path)])
        return PhotoDrawing(data: pk.dataRepresentation(), canvasWidth: 300, canvasHeight: 200)
    }

    @Test func emptyDrawingReadsAsIdentity() {
        #expect(PhotoDrawing(data: Data(), canvasWidth: 300, canvasHeight: 200).isEmpty)
        #expect(PhotoDrawing(data: Data([1]), canvasWidth: 0, canvasHeight: 200).isEmpty)
        #expect(!drawing().isEmpty)
    }

    /// A drawing layer round-trips inside `overlays`; there is no top-level
    /// `drawing` key any more.
    @Test func aDrawingLayerRoundTripsInTheStack() throws {
        var recipe = PhotoEditRecipe.identity
        recipe.overlays = [.text(), .drawing(drawing())]
        #expect(!recipe.isIdentity)
        #expect(!(try keys(of: recipe)).contains("drawing"))

        let decoded = try JSONDecoder().decode(
            PhotoEditRecipe.self,
            from: JSONEncoder().encode(recipe)
        )
        #expect(decoded.overlays.map(\.kind) == [.text, .drawing])
        #expect(decoded.overlays.last?.drawing == drawing())
    }

    /// A recipe written with the old single `drawing` key reads it back as one
    /// drawing layer at the bottom of the stack (a wrap, not a migration).
    @Test func theOldSingleDrawingReadsAsTheBottomLayer() throws {
        var object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(PhotoEditRecipe.identity)
        ) as? [String: Any] ?? [:]
        object["drawing"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(drawing()))
        object["overlays"] = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode([PhotoOverlay.text()])
        )
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(PhotoEditRecipe.self, from: data)
        #expect(decoded.overlays.map(\.kind) == [.drawing, .text])
    }

    @Test func anEmptyDrawingLayerDrawsNothing() {
        let layer = PhotoOverlay.drawing(PhotoDrawing(data: Data(), canvasWidth: 300, canvasHeight: 200))
        #expect(!layer.hasVisibleEffect)
        var hidden = PhotoOverlay.drawing(drawing())
        hidden.isVisible = false
        #expect(!hidden.hasVisibleEffect)
    }

    /// AC-31. A drawing layer is composited in stack order: moved above a filled
    /// shape it covers the shape where they overlap; below, the shape covers it.
    @Test func aDrawingLayerComposesInStackOrder() throws {
        var box = PhotoOverlay.shape(.rectangle)
        box.isFilled = true
        box.fill = OverlayColor(red: 0, green: 0, blue: 1)
        box.size = 0.8
        box.heightRatio = 0.5
        // The stroke runs across the middle of the frame, through the box.
        let scribble = PhotoOverlay.drawing(stroke(across: CGRect(x: 30, y: 90, width: 240, height: 20)))
        let extent = CGRect(x: 0, y: 0, width: 300, height: 200)

        func centrePixel(_ overlays: [PhotoOverlay]) throws -> (r: UInt8, b: UInt8) {
            let image = try #require(PhotoRenderService.rasterizedOverlayImage(overlays, extent: extent))
            let data = try #require(image.dataProvider?.data as Data?)
            let row = image.bytesPerRow
            let offset = (image.height / 2) * row + (image.width / 2) * 4
            return (data[offset], data[offset + 2])
        }

        let drawingOnTop = try centrePixel([box, scribble])
        #expect(drawingOnTop.r > 200 && drawingOnTop.b < 60)
        let shapeOnTop = try centrePixel([scribble, box])
        #expect(shapeOnTop.b > 200 && shapeOnTop.r < 60)
    }

    /// AC-38 (memory). A drawing is rasterized to its strokes' bounding box, not
    /// the whole frame: a stroke across a tenth of the canvas at 48MP export size
    /// costs a fraction of the ~195MB a full-frame raster would.
    @Test func aDrawingRastersOnlyItsBoundingBox() throws {
        let small = stroke(across: CGRect(x: 10, y: 10, width: 30, height: 10), width: 4)
        let stamp = try #require(PhotoRenderService.drawingStamp(small, pixelWidth: 8064, pixelHeight: 6048))
        let bytes = stamp.image.bytesPerRow * stamp.image.height
        #expect(bytes < 8 * 1024 * 1024)
        #expect(stamp.rect.minX >= 0 && stamp.rect.maxX <= 8064)
        // Near the top of the canvas, so near the top (high y) of the bottom-up bitmap.
        #expect(stamp.rect.midY > 6048 * 0.8)
    }

    /// AC-38 (memory). A drawing whose strokes span the whole frame is not built
    /// as one ~195MB bitmap at 48MP: it is planned as bands of at most 24MB that
    /// tile its bounding box top to bottom with no gap and no overlap.
    @Test func aFullFrameDrawingIsPlannedInBoundedBands() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        let scale: CGFloat = 8064 / 300
        let bands = PhotoRenderService.drawingBands(bounds: bounds, scale: scale)
        #expect(bands.count > 1)
        for band in bands {
            let bytes = Int((band.width * scale).rounded(.up)) * 4 * Int((band.height * scale).rounded(.up))
            #expect(bytes <= PhotoRenderService.largestDrawingStampBytes + Int(band.width * scale) * 4)
        }
        #expect(bands.first?.minY == bounds.minY)
        #expect(abs((bands.last?.maxY ?? 0) - bounds.maxY) < 0.001)
        for (upper, lower) in zip(bands, bands.dropFirst()) {
            #expect(abs(upper.maxY - lower.minY) < 0.001)
        }
        // A signature-sized drawing stays one band — the cached stamp path.
        #expect(PhotoRenderService.drawingBands(bounds: CGRect(x: 10, y: 10, width: 30, height: 10), scale: scale).count == 1)
    }

    /// The banded path draws the same marks: a vertical stroke crossing every
    /// band seam is unbroken in the composite.
    @Test func bandedDrawingHasNoSeams() throws {
        func point(_ x: CGFloat, _ y: CGFloat) -> PKStrokePoint {
            PKStrokePoint(location: CGPoint(x: x, y: y), timeOffset: 0, size: CGSize(width: 12, height: 12),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let ink = PKInk(.pen, color: .red)
        let across = PKStroke(ink: ink, path: PKStrokePath(controlPoints: [point(30, 12), point(270, 12)], creationDate: Date()))
        let down = PKStroke(ink: ink, path: PKStrokePath(controlPoints: [point(150, 12), point(150, 190)], creationDate: Date()))
        let drawing = PhotoDrawing(
            data: PKDrawing(strokes: [across, down]).dataRepresentation(),
            canvasWidth: 300, canvasHeight: 200
        )
        let extent = CGRect(x: 0, y: 0, width: 3600, height: 2400)
        let scale = extent.width / 300
        let pk = try PKDrawing(data: drawing.data)
        let bands = PhotoRenderService.drawingBands(bounds: pk.bounds.integral, scale: scale)
        try #require(bands.count > 1)

        let image = try #require(PhotoRenderService.rasterizedOverlayImage([.drawing(drawing)], extent: extent))
        let data = try #require(image.dataProvider?.data as Data?)
        let column = Int(150 * scale)
        // Every 8 rows from just below the top stroke to just above the end cap.
        for row in stride(from: Int(24 * scale), to: Int(185 * scale), by: 8) {
            let offset = row * image.bytesPerRow + column * 4
            #expect(data[offset] > 200, "row \(row) is not red")
        }
    }
}

