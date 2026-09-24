import CoreGraphics
import Photos
import PencilKit
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// `EditorDrawSession` holds a `PKDrawing`, which stores its strokes in
/// **absolute canvas points**. Anything that changes the canvas's size under an
/// open drawing therefore has to move the strokes with it, or the vector is
/// baked against the wrong geometry on `Done`.
@MainActor
struct EditorDrawSessionTests {
    /// A one-stroke drawing spanning most of `size`, so a scale shows up as a
    /// change in the bounds rather than as rounding.
    private func drawing(in size: CGSize) -> PKDrawing {
        let ink = PKInk(.pen, color: .white)
        let points = [
            PKStrokePoint(
                location: CGPoint(x: size.width * 0.1, y: size.height * 0.1),
                timeOffset: 0,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: 0
            ),
            PKStrokePoint(
                location: CGPoint(x: size.width * 0.9, y: size.height * 0.9),
                timeOffset: 0.1,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: 0
            ),
        ]
        return PKDrawing(strokes: [PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: Date()))])
    }

    /// The first size is simply adopted: nothing to carry.
    @Test func firstSizeIsAdoptedWithoutTouchingTheStrokes() {
        let session = EditorDrawSession()
        let inner = CGSize(width: 890, height: 600)
        session.load(data: drawing(in: inner).dataRepresentation())
        let before = session.drawing.bounds

        session.reconcile(to: inner)
        #expect(session.canvasSize == inner)
        #expect(session.drawing.bounds == before)
    }

    /// The Duo fold, which is the case this exists for: strokes drawn on the
    /// 890pt inner canvas must not stay at x≈800 on a 382pt cover canvas.
    @Test func strokesFollowTheCanvasWhenItShrinks() {
        let session = EditorDrawSession()
        let inner = CGSize(width: 890, height: 600)
        let cover = CGSize(width: 382, height: 600)
        session.load(data: drawing(in: inner).dataRepresentation())
        session.reconcile(to: inner)
        let before = session.drawing.bounds
        #expect(before.maxX > cover.width)

        let token = session.clearToken
        session.reconcile(to: cover)

        #expect(session.canvasSize == cover)
        // Everything is inside the new canvas, which is the whole point.
        #expect(session.drawing.bounds.maxX <= cover.width + 1)
        #expect(session.drawing.bounds.minX >= -1)
        // Uniform: the stroke keeps its shape rather than being sheared.
        let scale = cover.width / inner.width
        #expect(abs(session.drawing.bounds.width - before.width * scale) < 2)
        #expect(abs(session.drawing.bounds.height - before.height * scale) < 2)
        // And the canvas is told, or it goes on drawing the old strokes.
        #expect(session.clearToken > token)
    }

    /// An empty session resizes for free — no transform, and no `clearToken`
    /// bump that would make the canvas re-adopt nothing.
    @Test func anEmptyDrawingJustTakesTheNewSize() {
        let session = EditorDrawSession()
        session.reconcile(to: CGSize(width: 890, height: 600))
        let token = session.clearToken
        session.reconcile(to: CGSize(width: 382, height: 600))
        #expect(session.canvasSize == CGSize(width: 382, height: 600))
        #expect(session.clearToken == token)
    }

    /// A zero size is a canvas that has not been laid out yet; taking it would
    /// throw the recorded geometry away.
    @Test func zeroSizeIsIgnored() {
        let session = EditorDrawSession()
        let inner = CGSize(width: 890, height: 600)
        session.reconcile(to: inner)
        session.reconcile(to: .zero)
        #expect(session.canvasSize == inner)
    }
}

/// FS-05.01 §4 — drawing layers on the phone panel, PencilKit driven by the panel.
@MainActor
struct EditorDrawLayerTests {
    private func makeController() -> PhotoEditorController {
        PhotoEditorController(asset: PHAsset(), sourceAlbum: nil, service: PhotoEditingService())
    }

    private func strokes(_ count: Int) -> Data {
        let ink = PKInk(.pen, color: .red)
        let all = (0..<count).map { index -> PKStroke in
            let y = CGFloat(20 + index * 20)
            let points = [
                PKStrokePoint(location: CGPoint(x: 10, y: y), timeOffset: 0, size: CGSize(width: 4, height: 4),
                              opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
                PKStrokePoint(location: CGPoint(x: 200, y: y), timeOffset: 0.1, size: CGSize(width: 4, height: 4),
                              opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
            ]
            return PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: Date()))
        }
        return PKDrawing(strokes: all).dataRepresentation()
    }

    /// AC-29. Marker, size 20, opacity 50%: the tool the panel hands the canvas is
    /// a marker 20 wide at alpha 0.5 — the ink, not the system picker, decides.
    @Test func thePanelBuildsTheInkingTool() throws {
        let session = EditorDrawSession()
        session.ink = .marker
        session.width = 20
        session.opacity = 0.5
        let tool = try #require(session.tool as? PKInkingTool)
        #expect(tool.inkType == .marker)
        #expect(abs(tool.width - 20) < 0.5)
        var alpha: CGFloat = 0
        tool.color.getRed(nil, green: nil, blue: nil, alpha: &alpha)
        #expect(abs(alpha - 0.5) < 0.01)

        session.mode = .erase
        #expect(session.tool is PKEraserTool)
        session.mode = .select
        #expect(session.tool is PKLassoTool)
    }

    /// AC-28. Pen, a stroke, `+`, Pen, a stroke: two drawing layers, one stroke
    /// each.
    @Test func twoPenSessionsMakeTwoLayers() throws {
        let controller = makeController()
        for _ in 0..<2 {
            controller.addDrawingLayer()
            controller.beginDrawing()
            controller.commitDrawing(data: strokes(1), canvasSize: CGSize(width: 300, height: 200), endsSession: false)
            controller.endDrawing()
        }
        let layers = controller.recipe.overlays.filter { $0.kind == .drawing }
        #expect(layers.count == 2)
        for layer in layers {
            let data = try #require(layer.drawing?.data)
            #expect(try PKDrawing(data: data).strokes.count == 1)
        }
    }

    /// AC-30. Three strokes are three steps: one Undo leaves two, and the layer is
    /// still there and still the one being drawn on.
    @Test func eachStrokeIsOneUndoStep() throws {
        let controller = makeController()
        controller.addDrawingLayer()
        controller.beginDrawing()
        let layerID = try #require(controller.selectedOverlayID)
        for count in 1...3 {
            controller.commitDrawing(data: strokes(count), canvasSize: CGSize(width: 300, height: 200), endsSession: false)
        }
        controller.undo()
        let layer = try #require(controller.recipe.overlays.first { $0.id == layerID })
        let data = try #require(layer.drawing?.data)
        #expect(try PKDrawing(data: data).strokes.count == 2)
        #expect(controller.selectedOverlayID == layerID)

        // The canvas reloading the undone drawing is not a new step.
        controller.commitDrawing(data: data, canvasSize: CGSize(width: 300, height: 200), endsSession: false)
        #expect(controller.canRedo)
    }

    /// Leaving drawing drops a drawing layer that never got a stroke.
    @Test func anUntouchedDrawingLayerIsDropped() {
        let controller = makeController()
        controller.addDrawingLayer()
        controller.beginDrawing()
        controller.endDrawing()
        #expect(controller.recipe.overlays.isEmpty)
    }
}
