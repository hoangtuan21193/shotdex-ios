import SwiftUI

/// What Clean Up draws on the photo: the stroke under the finger, a pin per
/// finished stroke, and — for Clone and Heal — the source ring you drag to choose
/// where the pixels come from.
///
/// Lives inside the zoomed stack next to `EditorMaskGuideOverlay`, so a knob drag
/// lands on the knob at any magnification and a drag on empty photo falls through
/// to the paint layer below.
struct EditorCleanUpOverlay: View {
    @Bindable var controller: PhotoEditorController
    let imageRect: CGRect
    /// Points of the stroke being painted right now, in the named stage space.
    /// Painting does not re-render — solving a fill costs real time — so this path
    /// is the only feedback until the finger lifts.
    let livePath: [CGPoint]

    var body: some View {
        ZStack {
            if livePath.count > 1 {
                Path { path in
                    path.move(to: livePath[0])
                    for point in livePath.dropFirst() { path.addLine(to: point) }
                }
                .stroke(
                    EditorTheme.accent.opacity(0.45),
                    style: StrokeStyle(
                        lineWidth: strokeWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .allowsHitTesting(false)
            }

            ForEach(controller.cleanUpStrokes) { stroke in
                pin(stroke)
            }

            if let stroke = controller.selectedCleanUpStroke,
               stroke.mode.usesSourceOffset {
                sourceRing(stroke)
            }
        }
    }

    private var strokeWidth: CGFloat {
        EditorLayoutMetrics.brushDiameter(size: controller.cleanUpSize, in: imageRect)
            * EditorLayoutMetrics.brushCoreScale(feather: controller.cleanUpFeather)
    }

    private func pin(_ stroke: CleanUpStroke) -> some View {
        let isSelected = controller.selectedCleanUpStrokeID == stroke.id
        let center = EditorLayoutMetrics.maskViewPoint(stroke.centroid, in: imageRect)
        return Circle()
            .fill(isSelected ? EditorTheme.accent : Color.white.opacity(0.85))
            .frame(width: 14, height: 14)
            .overlay {
                Circle().stroke(Color.black.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.5), radius: 2)
            // A 14pt dot is far too small to hit, so the tap target is the usual
            // 44pt and only the dot is drawn.
            .frame(
                width: EditorLayoutMetrics.maskGuideHitTarget,
                height: EditorLayoutMetrics.maskGuideHitTarget
            )
            .contentShape(Circle())
            .position(center)
            .onTapGesture { controller.selectCleanUpStroke(id: stroke.id) }
            .accessibilityLabel("\(stroke.mode.displayName) stroke")
    }

    /// Dashed circle the size of the brush, showing where Clone / Heal reads from.
    private func sourceRing(_ stroke: CleanUpStroke) -> some View {
        let source = EditorLayoutMetrics.cleanUpSourcePoint(
            centroid: stroke.centroid,
            offsetX: stroke.sourceOffsetX,
            offsetY: stroke.sourceOffsetY,
            in: imageRect
        )
        let diameter = max(
            18,
            EditorLayoutMetrics.brushDiameter(size: stroke.size, in: imageRect)
        )
        return ZStack {
            Circle()
                .stroke(
                    Color.white.opacity(0.9),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
                .frame(width: diameter, height: diameter)
                .shadow(color: .black.opacity(0.5), radius: 1)
                .allowsHitTesting(false)
            Circle()
                .fill(.white)
                .frame(
                    width: EditorLayoutMetrics.maskGuideKnobSize,
                    height: EditorLayoutMetrics.maskGuideKnobSize
                )
                .overlay {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.black.opacity(0.7))
                }
                .shadow(color: .black.opacity(0.55), radius: 2)
                .frame(
                    width: EditorLayoutMetrics.maskGuideHitTarget,
                    height: EditorLayoutMetrics.maskGuideHitTarget
                )
                .contentShape(Circle())
                .gesture(sourceDrag(stroke))
        }
        .position(source)
        .accessibilityLabel("Clone source")
    }

    private func sourceDrag(_ stroke: CleanUpStroke) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(EditorImageStage.stageSpace))
            .onChanged { value in
                controller.beginContinuousChange()
                guard imageRect.width > 0, imageRect.height > 0 else { return }
                let target = EditorLayoutMetrics.cleanUpSourceOffset(
                    from: value.location,
                    centroid: stroke.centroid,
                    in: imageRect
                )
                // The knob is dragged to an absolute point, so the delta the
                // controller wants is the difference from where the source is now.
                controller.moveSelectedCleanUpSource(
                    dx: target.x - stroke.sourceOffsetX,
                    dy: target.y - stroke.sourceOffsetY
                )
            }
            .onEnded { _ in controller.endContinuousChange() }
    }
}
