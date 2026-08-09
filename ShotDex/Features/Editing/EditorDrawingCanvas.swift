import PencilKit
import SwiftUI

/// The live state of a drawing session, shared between the canvas that owns the
/// strokes and the action row's Clear / Done buttons.
///
/// The canvas is the source of truth while a session is open: it writes the
/// `drawing` and its `canvasSize` back here as the user draws, and adopts a new
/// `drawing` when `clearToken` bumps (Clear, or loading an existing drawing).
@MainActor
@Observable
final class EditorDrawSession {
    private(set) var drawing = PKDrawing()
    /// The canvas's own point size, so the renderer can scale the vector to any
    /// resolution. Recorded by the canvas from its laid-out bounds.
    var canvasSize: CGSize = .zero
    /// Bumped whenever `drawing` is replaced from the outside (load or clear), so
    /// the canvas knows to adopt it rather than treating it as its own edit.
    private(set) var clearToken = 0

    /// Called by the canvas as the user draws.
    func adopt(from canvas: PKDrawing) {
        drawing = canvas
    }

    /// Loads an existing drawing (or a blank one) at the start of a session.
    func load(data: Data?) {
        drawing = data.flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
        clearToken += 1
    }

    /// Empties the canvas. The recipe is not touched until Done.
    func clear() {
        drawing = PKDrawing()
        clearToken += 1
    }

    var isEmpty: Bool { drawing.strokes.isEmpty }
}

/// Hosts a `PKCanvasView` and its `PKToolPicker` over the photo — the iOS Photos
/// Markup drawing surface. Finger and Pencil both draw (`.anyInput`); the canvas is
/// transparent so the photo shows through, and scrolling/zoom is off so canvas
/// points map straight to the fitted photo rect.
struct EditorDrawingCanvas: UIViewRepresentable {
    @Bindable var session: EditorDrawSession
    /// The session's `clearToken`, passed explicitly so the enclosing view reads it
    /// and re-invokes `updateUIView` when Clear (or the initial load) replaces the
    /// drawing — fine-grained `@Observable` tracking would not fire otherwise.
    let clearSignal: Int

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.drawing = session.drawing
        canvas.delegate = context.coordinator
        context.coordinator.appliedClearToken = session.clearToken

        let picker = PKToolPicker()
        picker.addObserver(canvas)
        picker.setVisible(true, forFirstResponder: canvas)
        context.coordinator.toolPicker = picker

        // First responder can only be taken once the view is in a window.
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        // Adopt an externally replaced drawing (Clear, or the initial load).
        if context.coordinator.appliedClearToken != session.clearToken {
            context.coordinator.appliedClearToken = session.clearToken
            canvas.drawing = session.drawing
        }
        // Record the laid-out size so Done can scale the vector, even if the user
        // never added a stroke this session (an existing drawing kept as-is).
        let size = canvas.bounds.size
        if size != .zero, session.canvasSize != size {
            session.canvasSize = size
        }
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.toolPicker?.setVisible(false, forFirstResponder: canvas)
        canvas.resignFirstResponder()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let session: EditorDrawSession
        var appliedClearToken = 0
        /// Held so the tool picker outlives `makeUIView`.
        var toolPicker: PKToolPicker?

        init(session: EditorDrawSession) {
            self.session = session
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            session.adopt(from: canvasView.drawing)
            let size = canvasView.bounds.size
            if size != .zero { session.canvasSize = size }
        }
    }
}
