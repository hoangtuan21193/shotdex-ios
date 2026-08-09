import SwiftUI
import UIKit

/// Where an overlay layer sits on screen, in stage coordinates.
///
/// Computed from the same `TextOverlayLayout` functions the renderer uses, with the
/// displayed photo's rect standing in for the render extent. That is what keeps the
/// selection box, the live proxy and the baked pixels agreeing: one layout, three
/// consumers, no second implementation to drift.
struct EditorOverlayFrame {
    var center: CGPoint
    var size: CGSize
    var rotationDegrees: Double

    static func make(
        for overlay: PhotoOverlay,
        resolvedText: String,
        imageRect: CGRect,
        image: CGImage?
    ) -> EditorOverlayFrame? {
        let shortEdge = min(imageRect.width, imageRect.height)
        guard shortEdge > 0 else { return nil }
        let size: CGSize
        switch overlay.kind {
        case .text:
            guard !resolvedText.isEmpty else { return nil }
            size = TextOverlayLayout.textContentSize(
                for: overlay,
                resolvedText: resolvedText,
                extent: CGRect(origin: .zero, size: imageRect.size),
                shortEdge: shortEdge
            )
        case .image:
            guard let image else { return nil }
            size = TextOverlayLayout.imageContentSize(
                for: overlay,
                image: image,
                shortEdge: shortEdge
            )
        }
        guard size.width > 0, size.height > 0 else { return nil }
        return EditorOverlayFrame(
            center: CGPoint(
                x: imageRect.minX + imageRect.width * overlay.center.x,
                y: imageRect.minY + imageRect.height * overlay.center.y
            ),
            size: size,
            rotationDegrees: overlay.rotationDegrees
        )
    }
}

/// Draws the overlay layers live while one of them is selected.
///
/// A `Canvas` running the *renderer's own* rasterizer rather than SwiftUI `Text`:
/// an outline, a shadow and Core Text's line breaking are not reproducible with
/// SwiftUI modifiers, and a proxy that lays out even slightly differently would
/// make the caption jump the moment it is deselected and the bake takes over.
struct EditorOverlayProxyLayer: View {
    let controller: PhotoEditorController
    let imageRect: CGRect
    /// Decoded signature images, loaded by the parent — a `Canvas` body cannot
    /// read files.
    let images: [UUID: CGImage]
    /// The selected layer's outline is drawn here too, under the same transform as
    /// its glyphs. Drawn as a separate SwiftUI view it drifted off the text: the
    /// layout is Core Text's and only Core Text's numbers place it correctly.
    let selectedID: UUID?
    let accent: CGColor

    var body: some View {
        Canvas { context, size in
            context.withCGContext { cgContext in
                // SwiftUI hands out a top-left origin; the rasterizer and Core Text
                // both want bottom-up, the same as the render bitmap.
                cgContext.translateBy(x: 0, y: size.height)
                cgContext.scaleBy(x: 1, y: -1)
                draw(in: cgContext, size: size)
            }
        }
        .frame(width: imageRect.width, height: imageRect.height)
        .position(x: imageRect.midX, y: imageRect.midY)
        .allowsHitTesting(false)
    }

    private func draw(in context: CGContext, size: CGSize) {
        let extent = CGRect(origin: .zero, size: size)
        let shortEdge = min(size.width, size.height)
        let point: (NormalizedPoint) -> CGPoint = { normalized in
            CGPoint(x: size.width * normalized.x, y: size.height * (1 - normalized.y))
        }
        for overlay in controller.recipe.overlays where overlay.hasVisibleEffect {
            var contentSize = CGSize.zero
            switch overlay.kind {
            case .text:
                let text = controller.resolvedText(for: overlay)
                TextOverlayLayout.drawText(
                    overlay,
                    resolvedText: text,
                    in: context,
                    extent: extent,
                    shortEdge: shortEdge,
                    point: point
                )
                contentSize = TextOverlayLayout.textContentSize(
                    for: overlay,
                    resolvedText: text,
                    extent: extent,
                    shortEdge: shortEdge
                )
            case .image:
                guard let id = overlay.imageID, let image = images[id] else { continue }
                TextOverlayLayout.drawImage(
                    overlay,
                    image: image,
                    in: context,
                    extent: extent,
                    shortEdge: shortEdge,
                    point: point
                )
                contentSize = TextOverlayLayout.imageContentSize(
                    for: overlay,
                    image: image,
                    shortEdge: shortEdge
                )
            }
            guard overlay.id == selectedID else { continue }
            drawOutline(overlay, contentSize: contentSize, in: context, point: point)
        }
    }

    private func drawOutline(
        _ overlay: PhotoOverlay,
        contentSize: CGSize,
        in context: CGContext,
        point: (NormalizedPoint) -> CGPoint
    ) {
        guard contentSize.width > 0, contentSize.height > 0 else { return }
        context.saveGState()
        context.concatenate(
            TextOverlayLayout.transform(
                for: overlay,
                contentSize: contentSize,
                point: point
            )
        )
        context.setStrokeColor(accent)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [5, 4])
        context.stroke(
            CGRect(origin: .zero, size: contentSize).insetBy(dx: -4, dy: -4)
        )
        context.restoreGState()
    }
}

/// One layer's on-photo touch area: tap to select it, drag to pick it up and move
/// it — even a layer that was not selected yet. A drag anywhere on a layer grabs
/// *that* layer and moves it under the finger from the first millimetre, the way
/// Snapseed lets you shove any sticker around without selecting it first.
///
/// Rendered for every layer, selected or not, so that selecting one mid-drag never
/// changes this view's identity and cancels the gesture in progress.
///
/// No handles. They were tried and removed: at the size a caption is normally set
/// to, a 22pt knob at each corner covers the text it is meant to be adjusting, and
/// the drag translation a corner handle reports is in the layer's own rotated space
/// so resizing a tilted caption pulled in the wrong direction. Gestures do the work
/// instead, the way Snapseed's Text tool does — one finger moves, two fingers scale
/// and rotate — with the panel's Size and Rotate sliders for precision.
struct EditorOverlayMoveTarget: View {
    @Bindable var controller: PhotoEditorController
    let overlay: PhotoOverlay
    let frame: EditorOverlayFrame
    let imageRect: CGRect
    let zoomScale: CGFloat
    /// Reports which centre axes are currently snapped, so the parent can draw the
    /// guide lines across the whole photo rather than inside this small target.
    let onSnap: (Set<String>) -> Void

    /// Normalized centre at the moment a *move* began, so every frame positions from
    /// one fixed origin instead of accumulating rounding error. Nil until the finger
    /// has travelled far enough to count as a drag rather than a tap.
    @State private var dragStartCenter: NormalizedPoint?
    @State private var snappedAxes: Set<String> = []

    /// Screen points the finger must travel before a touch becomes a move. Below it
    /// the touch is a tap — select only — so a small wobble while tapping a layer
    /// does not nudge it.
    private static let moveThreshold: CGFloat = 4

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .contentShape(Rectangle())
            .frame(width: touchSize.width, height: touchSize.height)
            .position(frame.center)
            .gesture(dragGesture)
    }

    private var touchSize: CGSize {
        let radians = frame.rotationDegrees * .pi / 180
        let cosine = abs(cos(radians))
        let sine = abs(sin(radians))
        let width = frame.size.width * cosine + frame.size.height * sine
        let height = frame.size.width * sine + frame.size.height * cosine
        let minimum = 44 / zoomScale
        return CGSize(width: max(minimum, width), height: max(minimum, height))
    }

    private var dragGesture: some Gesture {
        // `minimumDistance: 0` so a plain tap still selects — the finger touching
        // the layer is enough to pick it. Movement past the threshold turns the same
        // touch into a move without a second gesture.
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Touch-down selects at once: the box appears the instant a finger
                // lands on the layer, before it has moved.
                if controller.selectedOverlayID != overlay.id {
                    controller.selectOverlay(overlay.id)
                }
                let travelled = hypot(value.translation.width, value.translation.height)
                if dragStartCenter == nil {
                    guard travelled >= Self.moveThreshold else { return }
                    controller.beginOverlayGesture()
                    dragStartCenter = overlay.center
                }
                guard let start = dragStartCenter else { return }
                // The drag is in unrotated stage points, and the layer may be
                // rotated, so the translation is taken from the gesture rather than
                // the view's own space — moving a tilted caption sideways should move
                // it sideways on screen, not along its own baseline.
                var x = start.x + value.translation.width / max(1, imageRect.width)
                var y = start.y + value.translation.height / max(1, imageRect.height)
                var axes: Set<String> = []
                if abs(x - 0.5) < 0.012 {
                    x = 0.5
                    axes.insert("x")
                }
                if abs(y - 0.5) < 0.012 {
                    y = 0.5
                    axes.insert("y")
                }
                if axes != snappedAxes, !axes.isEmpty {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                setSnapped(axes)
                controller.moveSelectedOverlay(toCenter: NormalizedPoint(
                    x: min(1, max(0, x)),
                    y: min(1, max(0, y))
                ))
            }
            .onEnded { _ in
                if dragStartCenter != nil {
                    controller.endOverlayGesture()
                }
                dragStartCenter = nil
                setSnapped([])
            }
    }

    private func setSnapped(_ axes: Set<String>) {
        guard axes != snappedAxes else { return }
        snappedAxes = axes
        onSnap(axes)
    }
}

/// The centre-snap guide lines for a layer being dragged, drawn across the whole
/// photo. A separate view from the move target because a target is only as big as
/// its layer, and these lines span the picture.
struct EditorOverlaySnapGuides: View {
    let snappedAxes: Set<String>
    let imageRect: CGRect
    let zoomScale: CGFloat

    private var lineWidth: CGFloat { 1 / zoomScale }

    var body: some View {
        ZStack {
            if snappedAxes.contains("x") {
                Rectangle()
                    .fill(EditorTheme.accent.opacity(0.7))
                    .frame(width: lineWidth, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)
            }
            if snappedAxes.contains("y") {
                Rectangle()
                    .fill(EditorTheme.accent.opacity(0.7))
                    .frame(width: imageRect.width, height: lineWidth)
                    .position(x: imageRect.midX, y: imageRect.midY)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Two-finger scale and rotate for the selected layer, over the whole photo.
///
/// Over the *whole photo* rather than over the layer's own box, which is where these
/// gestures started out: a caption is routinely narrower than the gap between two
/// fingertips, so requiring the pinch to land inside it made resizing all but
/// impossible. Snapseed pinches anywhere too.
///
/// Sits below the layer tap targets and the selection box so a one-finger tap still
/// picks a layer and a one-finger drag still moves the selected one — neither gesture
/// here can begin with a single finger, so nothing is taken away from them.
struct EditorOverlayPinchLayer: View {
    @Bindable var controller: PhotoEditorController
    let overlay: PhotoOverlay
    let imageRect: CGRect

    @State private var startSize: Double?
    @State private var startRotation: Double?
    @State private var isSnappedToDetent = false

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: imageRect.width, height: imageRect.height)
            .position(x: imageRect.midX, y: imageRect.midY)
            // Simultaneous with each other so one pinch can scale and turn at once.
            .simultaneousGesture(pinchGesture)
            .simultaneousGesture(rotateGesture)
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                let start = begin(current: overlay.size, state: $startSize)
                controller.updateSelectedOverlay {
                    $0.size = min(1, max(0.005, start * Double(value.magnification)))
                }
            }
            .onEnded { _ in
                startSize = nil
                endIfIdle()
            }
    }

    private var rotateGesture: some Gesture {
        RotateGesture(minimumAngleDelta: .degrees(1))
            .onChanged { value in
                let start = begin(current: overlay.rotationDegrees, state: $startRotation)
                controller.updateSelectedOverlay {
                    $0.rotationDegrees = detented(start + value.rotation.degrees)
                }
            }
            .onEnded { _ in
                startRotation = nil
                endIfIdle()
            }
    }

    /// Wraps to −180…180 and snaps every 45°: upright and the four diagonals are
    /// what a signature is nearly always set to.
    private func detented(_ value: Double) -> Double {
        var degrees = value.truncatingRemainder(dividingBy: 360)
        if degrees > 180 { degrees -= 360 }
        if degrees < -180 { degrees += 360 }
        let nearest = (degrees / 45).rounded() * 45
        guard abs(degrees - nearest) < 3 else {
            isSnappedToDetent = false
            return degrees
        }
        if !isSnappedToDetent {
            UISelectionFeedbackGenerator().selectionChanged()
            isSnappedToDetent = true
        }
        return nearest
    }

    private func begin<Value>(current: Value, state: Binding<Value?>) -> Value {
        if let existing = state.wrappedValue { return existing }
        controller.beginOverlayGesture()
        state.wrappedValue = current
        return current
    }

    /// A pinch and a rotation end independently, so the undo group only closes once
    /// every finger is off — otherwise letting go of the pinch a frame before the
    /// rotation would split one gesture into two history steps.
    private func endIfIdle() {
        guard startSize == nil, startRotation == nil else { return }
        isSnappedToDetent = false
        controller.endOverlayGesture()
    }
}
