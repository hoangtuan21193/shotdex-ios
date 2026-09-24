import SwiftUI
import UIKit
import ShotDexKit

/// The on-canvas layer for text and sticker overlays in the Video Studio preview.
///
/// The preview player shows the baked video *without* overlays
/// (`VideoRenderRecipe.bakesOverlays == false`); these are drawn live on top by a
/// `Canvas` running the renderer's own `TextOverlayLayout`, and manipulated by the
/// same one-finger-moves / two-fingers-scale-and-rotate gestures the photo editor
/// uses. One layout, two consumers (this proxy and the export bake), so a caption
/// lands in export exactly where it sits here.
///
/// `contentRect` is the aspect-fitted video rect inside the preview bounds — the
/// stand-in for the render extent, the same role `imageRect` plays in the editor.
struct VideoOverlayCanvas: View {
    @Bindable var model: VideoStudioModel
    let contentRect: CGRect
    /// Decoded sticker images by their `imageID`, loaded by the parent — a `Canvas`
    /// body cannot read files each frame.
    let images: [UUID: CGImage]

    @State private var snappedAxes: Set<String> = []

    /// Overlays visible at the playhead, in recipe (z) order, with their timing so
    /// the proxy can play each one's in/out animation.
    private var activeTimed: [TimedOverlay] {
        model.recipe.overlays.filter {
            $0.isActive(at: model.currentTime, total: model.totalDuration) && $0.overlay.hasVisibleEffect
        }
    }

    /// The resting overlays, for the move targets (which track the placed position,
    /// not the mid-animation offset).
    private var activeOverlays: [PhotoOverlay] { activeTimed.map(\.overlay) }

    var body: some View {
        ZStack {
            VideoOverlayProxyLayer(
                timedOverlays: activeTimed,
                currentTime: model.currentTime,
                totalDuration: model.totalDuration,
                selectedID: model.selectedOverlayID,
                images: images,
                contentRect: contentRect,
                accent: UIColor(EditorTheme.accent).cgColor
            )

            // Two-finger scale/rotate for the selected layer, and a single-finger
            // tap on empty canvas to deselect. Below the per-layer move targets so
            // a tap on a caption still selects it.
            if let overlay = selectedActiveOverlay {
                VideoOverlayPinchLayer(model: model, overlay: overlay, contentRect: contentRect)
            } else {
                Color.clear.allowsHitTesting(false)
            }

            ForEach(activeOverlays, id: \.id) { overlay in
                if let frame = frame(for: overlay) {
                    VideoOverlayMoveTarget(
                        model: model,
                        overlay: overlay,
                        frame: frame,
                        contentRect: contentRect,
                        onSnap: { snappedAxes = $0 }
                    )
                }
            }

            VideoOverlaySnapGuides(snappedAxes: snappedAxes, contentRect: contentRect)
        }
        .frame(width: contentRect.width, height: contentRect.height)
        .position(x: contentRect.midX, y: contentRect.midY)
    }

    private var selectedActiveOverlay: PhotoOverlay? {
        guard let id = model.selectedOverlayID else { return nil }
        return activeOverlays.first { $0.id == id }
    }

    private func frame(for overlay: PhotoOverlay) -> EditorOverlayFrame? {
        EditorOverlayFrame.make(
            for: overlay,
            resolvedText: overlay.text,
            imageRect: CGRect(origin: .zero, size: contentRect.size),
            image: overlay.imageID.flatMap { images[$0] }
        )
    }
}

/// Draws the active overlays live, plus a dashed selection box around the selected
/// one. Runs the renderer's rasterizer, never SwiftUI `Text`, so an outline, a
/// shadow and Core Text's line breaking match the export bake to the pixel.
private struct VideoOverlayProxyLayer: View {
    let timedOverlays: [TimedOverlay]
    let currentTime: Double
    let totalDuration: Double
    let selectedID: UUID?
    let images: [UUID: CGImage]
    let contentRect: CGRect
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
        .frame(width: contentRect.width, height: contentRect.height)
        .allowsHitTesting(false)
    }

    private func draw(in context: CGContext, size: CGSize) {
        let extent = CGRect(origin: .zero, size: size)
        let shortEdge = min(size.width, size.height)
        let point: (NormalizedPoint) -> CGPoint = { normalized in
            CGPoint(x: size.width * normalized.x, y: size.height * (1 - normalized.y))
        }
        for timed in timedOverlays {
            let overlay = timed.overlay
            let anim = timed.animationTransform(at: currentTime, total: totalDuration)
            guard anim.opacity > 0.001, anim.scale > 0.0001 else { continue }

            context.saveGState()
            applyAnimation(anim, center: overlay.center, size: size, in: context)
            context.setAlpha(CGFloat(anim.opacity))

            var contentSize = CGSize.zero
            switch overlay.kind {
            case .text:
                TextOverlayLayout.drawText(
                    overlay,
                    resolvedText: overlay.text,
                    in: context,
                    extent: extent,
                    shortEdge: shortEdge,
                    point: point
                )
                contentSize = TextOverlayLayout.textContentSize(
                    for: overlay,
                    resolvedText: overlay.text,
                    extent: extent,
                    shortEdge: shortEdge
                )
            case .image:
                if let id = overlay.imageID, let image = images[id] {
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
            case .shape, .magnifier, .drawing:
                // Photo-editor markup. The studio never creates these and the
                // export compositor does not draw them, so the preview must not
                // either — showing one here would promise an export that does
                // not happen.
                break
            }
            if overlay.id == selectedID {
                drawSelectionBox(overlay, contentSize: contentSize, in: context, point: point)
            }
            context.restoreGState()
        }
    }

    /// Scale the caption about its own centre and translate it, in the Canvas's
    /// bottom-up space — the same pose the export compositor bakes.
    private func applyAnimation(
        _ transform: OverlayAnimationMath.Transform,
        center: NormalizedPoint,
        size: CGSize,
        in context: CGContext
    ) {
        guard transform.scale != 1 || transform.translation != .zero else { return }
        let cx = size.width * center.x
        let cy = size.height * (1 - center.y)
        let dx = transform.translation.width * size.width
        // Screen-down translation is negative in the bottom-up drawing space.
        let dy = -transform.translation.height * size.height
        context.translateBy(x: cx + dx, y: cy + dy)
        context.scaleBy(x: CGFloat(transform.scale), y: CGFloat(transform.scale))
        context.translateBy(x: -cx, y: -cy)
    }

    private func drawSelectionBox(
        _ overlay: PhotoOverlay,
        contentSize: CGSize,
        in context: CGContext,
        point: (NormalizedPoint) -> CGPoint
    ) {
        guard contentSize.width > 0, contentSize.height > 0 else { return }
        context.saveGState()
        context.concatenate(
            TextOverlayLayout.transform(for: overlay, contentSize: contentSize, point: point)
        )
        context.setStrokeColor(accent)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [5, 4])
        context.stroke(CGRect(origin: .zero, size: contentSize).insetBy(dx: -4, dy: -4))
        context.restoreGState()
    }
}

/// One overlay's touch area: tap to select it, drag to move it — even one that was
/// not selected yet. Mirrors `EditorOverlayMoveTarget`, driving `VideoStudioModel`.
private struct VideoOverlayMoveTarget: View {
    @Bindable var model: VideoStudioModel
    let overlay: PhotoOverlay
    let frame: EditorOverlayFrame
    let contentRect: CGRect
    let onSnap: (Set<String>) -> Void

    @State private var dragStartCenter: NormalizedPoint?
    @State private var snappedAxes: Set<String> = []

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
        return CGSize(width: max(44, width), height: max(44, height))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if model.selectedOverlayID != overlay.id {
                    model.selectOverlay(overlay.id)
                }
                let travelled = hypot(value.translation.width, value.translation.height)
                if dragStartCenter == nil {
                    guard travelled >= Self.moveThreshold else { return }
                    model.beginOverlayGesture()
                    dragStartCenter = overlay.center
                }
                guard let start = dragStartCenter else { return }
                var x = start.x + value.translation.width / max(1, contentRect.width)
                var y = start.y + value.translation.height / max(1, contentRect.height)
                var axes: Set<String> = []
                if abs(x - 0.5) < 0.012 { x = 0.5; axes.insert("x") }
                if abs(y - 0.5) < 0.012 { y = 0.5; axes.insert("y") }
                if axes != snappedAxes, !axes.isEmpty {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                setSnapped(axes)
                model.moveSelectedOverlay(toCenter: NormalizedPoint(
                    x: min(1, max(0, x)),
                    y: min(1, max(0, y))
                ))
            }
            .onEnded { _ in
                if dragStartCenter != nil { model.endOverlayGesture() }
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

/// The centre-snap guide lines, drawn across the whole video rect while a layer is
/// dragged onto an axis.
private struct VideoOverlaySnapGuides: View {
    let snappedAxes: Set<String>
    let contentRect: CGRect

    var body: some View {
        ZStack {
            if snappedAxes.contains("x") {
                Rectangle()
                    .fill(EditorTheme.accent.opacity(0.75))
                    .frame(width: 1, height: contentRect.height)
            }
            if snappedAxes.contains("y") {
                Rectangle()
                    .fill(EditorTheme.accent.opacity(0.75))
                    .frame(width: contentRect.width, height: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Two-finger scale and rotate for the selected layer, over the whole video rect,
/// plus a single-finger tap on empty canvas to deselect. Mirrors
/// `EditorOverlayPinchLayer`.
private struct VideoOverlayPinchLayer: View {
    @Bindable var model: VideoStudioModel
    let overlay: PhotoOverlay
    let contentRect: CGRect

    @State private var startSize: Double?
    @State private var startRotation: Double?
    @State private var isSnappedToDetent = false

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: contentRect.width, height: contentRect.height)
            .onTapGesture { model.clearSelection() }
            .simultaneousGesture(pinchGesture)
            .simultaneousGesture(rotateGesture)
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                let start = begin(current: overlay.size, state: $startSize)
                model.setSelectedOverlaySize(min(1, max(0.005, start * Double(value.magnification))))
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
                model.setSelectedOverlayRotation(detented(start + value.rotation.degrees))
            }
            .onEnded { _ in
                startRotation = nil
                endIfIdle()
            }
    }

    /// Wraps to −180…180 and snaps every 45°.
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
        model.beginOverlayGesture()
        state.wrappedValue = current
        return current
    }

    private func endIfIdle() {
        guard startSize == nil, startRotation == nil else { return }
        isSnappedToDetent = false
        model.endOverlayGesture()
    }
}
