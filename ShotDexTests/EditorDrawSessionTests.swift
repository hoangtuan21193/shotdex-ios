import CoreGraphics
import PencilKit
import Testing
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
