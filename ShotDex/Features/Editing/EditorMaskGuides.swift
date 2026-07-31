import SwiftUI

/// Lightroom-style on-image guides for refining a mask after it has been placed.
/// Placement alone was not enough: dragging on the photo re-creates the whole
/// gradient, so the moment the finger lifted there was no way to nudge a size or
/// position — the shape was invisible and untouchable. The guides make the shape
/// visible and give it handles.
///
/// Lives *inside* the zoomed stack, above the paint layer: local coordinates are
/// un-zoomed image space (same trick the paint layer uses), and being on top means
/// a knob drag wins over the paint layer's drag underneath, while a drag on empty
/// photo still falls through — placing the gradient the first time, moving it
/// whole every time after.
struct EditorMaskGuideOverlay: View {
    @Bindable var controller: PhotoEditorController
    /// The fitted photo rect, in the stage's coordinates.
    let imageRect: CGRect
    /// Values captured on the first change of a knob drag, so every subsequent
    /// change is an absolute delta from where the drag started — the same pattern
    /// as the crop frame's move gesture, and for the same reason: accumulating
    /// per-frame deltas drifts.
    @State private var dragAnchor: DragAnchor?

    private struct DragAnchor {
        var start: NormalizedPoint
        var end: NormalizedPoint
        var center: NormalizedPoint
        var touch: CGPoint
    }

    var body: some View {
        ZStack {
            if let component = controller.selectedComponent {
                switch component.kind {
                case .linearGradient:
                    linearGuide(component)
                case .radialGradient:
                    radialGuide(component)
                case .subject:
                    subjectPin(component)
                default:
                    // Brush has no persistent guide: Size and Feather are set in
                    // the action-row popup, previewed by the cursor footprint.
                    EmptyView()
                }
            }
        }
        .coordinateSpace(name: Self.space)
    }

    private static let space = "maskGuides"

    // MARK: Linear gradient

    /// Three rails, like Lightroom: a solid line through the start point (full
    /// effect), a dashed one through the end point (no effect), and the axis
    /// between them. Knobs on start, end and midpoint — midpoint moves the whole
    /// band, the ends reshape and rotate it.
    @ViewBuilder
    private func linearGuide(_ component: PhotoMaskComponent) -> some View {
        let start = EditorLayoutMetrics.maskViewPoint(component.startPoint, in: imageRect)
        let end = EditorLayoutMetrics.maskViewPoint(component.endPoint, in: imageRect)
        let axis = CGVector(dx: end.x - start.x, dy: end.y - start.y)
        let railLength = hypot(imageRect.width, imageRect.height) * 2
        let startRail = EditorLayoutMetrics.perpendicularSegment(
            through: start, axis: axis, length: railLength
        )
        let endRail = EditorLayoutMetrics.perpendicularSegment(
            through: end, axis: axis, length: railLength
        )
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)

        guideLines { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        guideLines { path in
            path.move(to: startRail.0)
            path.addLine(to: startRail.1)
        }
        guideLines(dash: [4, 4]) { path in
            path.move(to: endRail.0)
            path.addLine(to: endRail.1)
        }

        knob(at: start, label: "Gradient start") { anchor, translation in
            controller.updateSelectedComponent {
                $0.startPoint = moved(anchor.start, by: translation)
            }
        }
        knob(at: end, label: "Gradient end") { anchor, translation in
            controller.updateSelectedComponent {
                $0.endPoint = moved(anchor.end, by: translation)
            }
        }
        knob(at: mid, isFilled: false, label: "Move gradient") { anchor, translation in
            controller.updateSelectedComponent {
                $0.startPoint = moved(anchor.start, by: translation)
                $0.endPoint = moved(anchor.end, by: translation)
            }
        }
    }

    // MARK: Radial gradient

    /// The ellipse itself, a dashed inner ellipse showing where the feather ramp
    /// begins (which finally makes the Feather slider's effect visible), four
    /// cardinal knobs that each resize one axis, and a centre knob. Dragging
    /// anywhere — inside or out — moves it; only the knobs resize.
    @ViewBuilder
    private func radialGuide(_ component: PhotoMaskComponent) -> some View {
        let outer = EditorLayoutMetrics.radialGuideRect(
            center: component.center,
            radiusX: component.radiusX,
            radiusY: component.radiusY,
            in: imageRect
        )
        let inner = EditorLayoutMetrics.radialGuideRect(
            center: component.center,
            radiusX: component.radiusX,
            radiusY: component.radiusY,
            feather: component.feather,
            in: imageRect
        )
        let mid = EditorLayoutMetrics.maskViewPoint(component.center, in: imageRect)

        guideLines { path in
            path.addEllipse(in: outer)
        }
        if component.feather > 0.01 {
            guideLines(dash: [4, 4]) { path in
                path.addEllipse(in: inner)
            }
        }

        // Move target: the inside of the ellipse. Sits under the knobs, so a drag
        // that starts on a knob resizes and one that starts inside moves.
        Color.clear
            .frame(width: max(1, outer.width), height: max(1, outer.height))
            .contentShape(Ellipse())
            .position(x: outer.midX, y: outer.midY)
            .gesture(dragGesture { anchor, translation in
                controller.updateSelectedComponent {
                    $0.center = moved(anchor.center, by: translation)
                }
            })
            .accessibilityLabel("Move ellipse")

        knob(at: CGPoint(x: outer.minX, y: outer.midY), label: "Ellipse width") {
            _, _, location in resizeRadius(\.radiusX, to: location, component: component)
        }
        knob(at: CGPoint(x: outer.maxX, y: outer.midY), label: "Ellipse width") {
            _, _, location in resizeRadius(\.radiusX, to: location, component: component)
        }
        knob(at: CGPoint(x: outer.midX, y: outer.minY), label: "Ellipse height") {
            _, _, location in resizeRadius(\.radiusY, to: location, component: component)
        }
        knob(at: CGPoint(x: outer.midX, y: outer.maxY), label: "Ellipse height") {
            _, _, location in resizeRadius(\.radiusY, to: location, component: component)
        }
        // Feather handle, on the inner ellipse and off the cardinal axes so it
        // never fights a resize knob: drag it towards the centre for a softer
        // edge, out to the rim for a hard one.
        let featherKnob = CGPoint(
            x: mid.x + inner.width / 2 * cos(.pi / 4),
            y: mid.y - inner.height / 2 * sin(.pi / 4)
        )
        knob(at: featherKnob, isSmall: true, label: "Feather") { _, _, location in
            let feather = EditorLayoutMetrics.maskFeather(
                at: location,
                center: mid,
                radii: CGSize(width: outer.width / 2, height: outer.height / 2)
            )
            controller.updateSelectedComponent { $0.feather = feather }
        }

        knob(at: mid, isFilled: false, label: "Move ellipse") { anchor, translation in
            controller.updateSelectedComponent {
                $0.center = moved(anchor.center, by: translation)
            }
        }
    }

    /// A cardinal knob writes the distance from the ellipse's centre to the
    /// finger, in the axis it owns — absolute, not a delta, so the ellipse edge
    /// tracks the finger exactly.
    private func resizeRadius(
        _ keyPath: WritableKeyPath<PhotoMaskComponent, Double>,
        to location: CGPoint,
        component: PhotoMaskComponent
    ) {
        let mid = EditorLayoutMetrics.maskViewPoint(component.center, in: imageRect)
        let value = keyPath == \.radiusX
            ? abs(location.x - mid.x) / max(1, imageRect.width)
            : abs(location.y - mid.y) / max(1, imageRect.height)
        controller.updateSelectedComponent {
            $0[keyPath: keyPath] = EditorLayoutMetrics.clampedMaskRadius(value)
        }
    }

    // MARK: Subject

    /// Just says where the subject was picked. Not interactive — tapping somewhere
    /// else on the photo re-picks, which the paint layer underneath already does.
    private func subjectPin(_ component: PhotoMaskComponent) -> some View {
        let point = EditorLayoutMetrics.maskViewPoint(component.subjectPoint, in: imageRect)
        return Circle()
            .fill(EditorTheme.accent)
            .frame(width: 10, height: 10)
            .overlay { Circle().stroke(.white, lineWidth: 1.5) }
            .shadow(color: .black.opacity(0.5), radius: 2)
            .position(point)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Pieces

    /// Guide strokes never take a touch: everything between the handles falls
    /// through to the paint layer, which is what keeps drag-to-replace working.
    private func guideLines(
        dash: [CGFloat] = [],
        _ draw: @escaping (inout Path) -> Void
    ) -> some View {
        Path(draw)
            .stroke(
                Color.white.opacity(0.85),
                style: StrokeStyle(lineWidth: 1, dash: dash)
            )
            .shadow(color: .black.opacity(0.5), radius: 1)
            // Lines run to infinity; only the part over the photo is guide, the
            // rest would scribble on the letterbox.
            .mask {
                Rectangle()
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)
            }
            .allowsHitTesting(false)
    }

    private func knob(
        at point: CGPoint,
        isFilled: Bool = true,
        isSmall: Bool = false,
        label: String,
        onDrag: @escaping (DragAnchor, CGSize) -> Void
    ) -> some View {
        knob(at: point, isFilled: isFilled, isSmall: isSmall, label: label) {
            anchor, translation, _ in onDrag(anchor, translation)
        }
    }

    /// Same knob as the crop frame — 18pt dot, 44pt hit area — so the two tools
    /// feel like one hand. The hollow variant marks "move", the solid ones "edit",
    /// and the small one marks a secondary handle like feather.
    private func knob(
        at point: CGPoint,
        isFilled: Bool = true,
        isSmall: Bool = false,
        label: String,
        onDrag: @escaping (DragAnchor, CGSize, CGPoint) -> Void
    ) -> some View {
        let diameter = isSmall
            ? EditorLayoutMetrics.maskGuideKnobSize * 0.7
            : EditorLayoutMetrics.maskGuideKnobSize
        return Circle()
            .fill(isFilled ? Color.white : Color.black.opacity(0.4))
            .overlay {
                Circle().stroke(
                    isFilled ? Color.black.opacity(0.25) : Color.white,
                    lineWidth: isFilled ? 0.5 : 1.5
                )
            }
            .frame(width: diameter, height: diameter)
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            .frame(
                width: EditorLayoutMetrics.maskGuideHitTarget,
                height: EditorLayoutMetrics.maskGuideHitTarget
            )
            .contentShape(Rectangle())
            .position(point)
            .gesture(dragGesture(onDrag))
            .accessibilityLabel(label)
            .accessibilityHint("Drag to adjust")
    }

    private func dragGesture(
        _ onDrag: @escaping (DragAnchor, CGSize) -> Void
    ) -> some Gesture {
        dragGesture { anchor, translation, _ in
            onDrag(anchor, translation)
        }
    }

    private func dragGesture(
        _ onDrag: @escaping (DragAnchor, CGSize, CGPoint) -> Void
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if dragAnchor == nil {
                    let component = controller.selectedComponent
                    dragAnchor = DragAnchor(
                        start: component?.startPoint ?? .center,
                        end: component?.endPoint ?? .center,
                        center: component?.center ?? .center,
                        touch: value.startLocation
                    )
                    controller.beginContinuousChange()
                }
                guard let dragAnchor else { return }
                let translation = CGSize(
                    width: value.location.x - dragAnchor.touch.x,
                    height: value.location.y - dragAnchor.touch.y
                )
                onDrag(dragAnchor, translation, value.location)
            }
            .onEnded { _ in
                dragAnchor = nil
                controller.endContinuousChange()
            }
    }

    /// Applies a view-space translation to a normalized point, clamped to the
    /// photo. Both ends of a linear gradient clamp independently, which also
    /// squeezes the band at the border instead of letting it escape the image.
    private func moved(_ point: NormalizedPoint, by translation: CGSize) -> NormalizedPoint {
        guard imageRect.width > 0, imageRect.height > 0 else { return point }
        return NormalizedPoint(
            x: min(1, max(0, point.x + translation.width / imageRect.width)),
            y: min(1, max(0, point.y + translation.height / imageRect.height))
        )
    }
}

/// Live brush cursor: the actual footprint of the stroke being painted, so brush
/// Size and Feather stop being abstract numbers. Outer ring is the full stamp,
/// inner ring the hard core the renderer keeps before the feather blur.
struct EditorBrushCursor: View {
    let point: CGPoint
    /// Normalized brush size — fraction of the image's short edge, matching
    /// `PhotoRenderService.brushMask`.
    let size: Double
    let feather: Double
    let isEraser: Bool
    let imageRect: CGRect
    /// The cursor lives inside the zoomed stack, so everything it draws is scaled
    /// up on screen. Dividing by the zoom is what keeps the ring — and the
    /// footprint it promises — a constant size under the finger: `size` is a
    /// screen size, and the stroke records `paintedSize(size:zoomScale:)`.
    var zoomScale: CGFloat = 1

    var body: some View {
        let diameter = max(8, size * min(imageRect.width, imageRect.height)) / zoomScale
        let core = diameter * max(0.08, 1 - feather * 0.8)
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                .frame(width: diameter, height: diameter)
            Circle()
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
                .frame(width: core, height: core)
            if isEraser {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 1)
        .position(point)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
