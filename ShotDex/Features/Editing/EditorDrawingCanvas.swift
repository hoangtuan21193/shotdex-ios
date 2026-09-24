import PencilKit
import SwiftUI
import ShotDexKit

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

    // MARK: Tool (phone panel, FS-05.01 §4)

    enum Mode: String, CaseIterable, Identifiable {
        case draw, erase, select
        var id: String { rawValue }
        var title: String {
            switch self {
            case .draw: "Draw"
            case .erase: "Erase"
            case .select: "Select"
            }
        }
        var systemImage: String {
            switch self {
            case .draw: "scribble"
            case .erase: "eraser"
            case .select: "lasso"
            }
        }
    }

    /// Whole strokes or the part under the eraser.
    enum EraserKind: String, CaseIterable, Identifiable {
        case strokes, pixels
        var id: String { rawValue }
        var title: String { self == .strokes ? "Strokes" : "Pixels" }
    }

    var mode: Mode = .draw
    var ink: EditorDrawInk = .pen {
        didSet { width = min(max(width, widthRange.lowerBound), widthRange.upperBound) }
    }
    var width: CGFloat = PKInkingTool.InkType.pen.defaultWidth
    var opacity: Double = 1
    var color = OverlayColor(red: 0.92, green: 0.27, blue: 0.24)
    var eraserKind: EraserKind = .strokes
    var isRulerActive = false
    /// Called after every stroke the canvas finishes — the phone panel commits
    /// each one as its own undo step.
    var onStrokeCommitted: (() -> Void)?

    var widthRange: ClosedRange<CGFloat> { ink.pkType.validWidthRange }

    /// The PencilKit tool the canvas draws with, built from the panel's rows.
    var tool: PKTool {
        switch mode {
        case .draw:
            PKInkingTool(
                ink.pkType,
                color: UIColor(
                    red: color.red, green: color.green, blue: color.blue,
                    alpha: CGFloat(min(max(opacity, 0.05), 1))
                ),
                width: width
            )
        case .erase:
            eraserKind == .strokes
                ? PKEraserTool(.vector)
                : PKEraserTool(.bitmap, width: max(width, 8))
        case .select:
            PKLassoTool()
        }
    }

    /// Pencil double-tap / squeeze: flips between drawing and erasing, the way the
    /// system tool picker does.
    func togglePencilEraser() {
        mode = mode == .erase ? .draw : .erase
    }

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

    /// Adopts a new canvas size, carrying the strokes with it.
    ///
    /// `PKDrawing` stores strokes in **absolute canvas points**, and this size
    /// used to be overwritten on every layout pass. So any relayout that changed
    /// the canvas — an iPad rotation, and routinely a fold on the Duo, where the
    /// `isWide` branch rebuilds the whole subtree — re-installed inner-sized
    /// strokes (x up to ~890) into a 382pt-wide cover canvas and then let `Done`
    /// bake those coordinates against the *new* size: strokes off-canvas, the
    /// rest scaled by 2.3×. Scaling them here keeps a drawing on the part of the
    /// photo it was drawn on. Uniform, and centred, because the photo is
    /// aspect-fitted into the canvas and a non-uniform scale would shear it.
    func reconcile(to newSize: CGSize) {
        guard newSize.width > 0, newSize.height > 0 else { return }
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            canvasSize = newSize
            return
        }
        guard canvasSize != newSize else { return }
        defer { canvasSize = newSize }
        guard !drawing.strokes.isEmpty else { return }
        let scale = min(newSize.width / canvasSize.width, newSize.height / canvasSize.height)
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(
                CGAffineTransform(
                    translationX: (newSize.width - canvasSize.width * scale) / 2,
                    y: (newSize.height - canvasSize.height * scale) / 2
                )
            )
        drawing = drawing.transformed(using: transform)
        // The canvas has to be told, or it keeps drawing the old strokes.
        clearToken += 1
    }

    var isEmpty: Bool { drawing.strokes.isEmpty }
}

/// Hosts a `PKCanvasView` over the photo — the iOS Photos Markup drawing surface.
/// On the wide sidebar it brings the system `PKToolPicker`; on the phone panel
/// (FS-05.01 §4) the picker never shows and the panel's rows set the tool. Finger and Pencil both draw (`.anyInput`); the canvas is
/// transparent so the photo shows through, and scrolling/zoom is off so canvas
/// points map straight to the fitted photo rect.
struct EditorDrawingCanvas: UIViewRepresentable {
    @Bindable var session: EditorDrawSession
    /// The session's `clearToken`, passed explicitly so the enclosing view reads it
    /// and re-invokes `updateUIView` when Clear (or the initial load) replaces the
    /// drawing — fine-grained `@Observable` tracking would not fire otherwise.
    let clearSignal: Int
    var usesSystemToolPicker = true

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        // `.default`, not `.anyInput`: with a Pencil paired this makes the Pencil
        // the only thing that draws, so the palm resting on the glass pans instead
        // of laying down a stroke. Without a Pencil it still resolves to finger
        // drawing, so nothing is lost on a phone.
        canvas.drawingPolicy = .default
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.drawing = session.drawing
        canvas.delegate = context.coordinator
        context.coordinator.appliedClearToken = session.clearToken

        if usesSystemToolPicker {
            let picker = PKToolPicker()
            picker.addObserver(canvas)
            picker.setVisible(true, forFirstResponder: canvas)
            context.coordinator.toolPicker = picker
            // First responder can only be taken once the view is in a window.
            DispatchQueue.main.async { canvas.becomeFirstResponder() }
        } else {
            // No picker: the canvas takes touches without being first responder,
            // and the tool comes from the panel.
            // Any input: without the picker there is no "draw with finger" switch,
            // and `.default` then refuses the finger outright.
            canvas.drawingPolicy = .anyInput
            canvas.tool = session.tool
            canvas.isRulerActive = session.isRulerActive
            let pencil = UIPencilInteraction()
            pencil.delegate = context.coordinator
            canvas.addInteraction(pencil)
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if !usesSystemToolPicker {
            canvas.tool = session.tool
            if canvas.isRulerActive != session.isRulerActive {
                canvas.isRulerActive = session.isRulerActive
            }
        }
        // Adopt an externally replaced drawing (Clear, or the initial load).
        if context.coordinator.appliedClearToken != session.clearToken {
            context.coordinator.appliedClearToken = session.clearToken
            canvas.drawing = session.drawing
        }
        // Record the laid-out size so Done can scale the vector, even if the user
        // never added a stroke this session (an existing drawing kept as-is) —
        // and carry any strokes across when the canvas changes shape under them.
        let size = canvas.bounds.size
        if size != .zero, session.canvasSize != size {
            session.reconcile(to: size)
            // `reconcile` may have rewritten the strokes; adopt them now rather
            // than waiting for another update pass, which would leave a frame of
            // the old geometry on screen.
            if context.coordinator.appliedClearToken != session.clearToken {
                context.coordinator.appliedClearToken = session.clearToken
                canvas.drawing = session.drawing
            }
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
    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
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
            session.onStrokeCommitted?()
        }

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            session.togglePencilEraser()
        }
    }
}
