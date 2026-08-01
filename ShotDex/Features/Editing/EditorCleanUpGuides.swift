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
    /// Same reason as `EditorMaskGuideOverlay`: the overlay is inside the zoomed
    /// stack, so the pin, the source knob and the ring's dashes divide by the zoom
    /// to keep their screen size.
    ///
    /// So does the painted path, and that is not a chrome decision — it is what the
    /// stroke *is*. `beginCleanUpStroke` records `paintedSize(size, zoomScale:)`, a
    /// brush that holds its screen size so detail can be reached by zooming in, and
    /// the trail has to promise exactly that. Drawing it from the raw slider made it
    /// `zoomScale` times too fat: paint a bar at 400% and the fill lands on a quarter
    /// of it. Only the source ring keeps growing with the photo — see `sourceRing`,
    /// which reads the already-recorded `stroke.size`.
    var zoomScale: CGFloat = 1

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

    /// Taken from `paintedSize`, the same call `beginCleanUpStroke` makes, so the
    /// trail cannot drift from the stroke it is previewing.
    private var strokeWidth: CGFloat {
        EditorLayoutMetrics.brushDiameter(
            size: EditorLayoutMetrics.paintedSize(
                controller.cleanUpSize,
                zoomScale: zoomScale
            ),
            in: imageRect
        ) * EditorLayoutMetrics.brushCoreScale(feather: controller.cleanUpFeather)
    }

    private func pin(_ stroke: CleanUpStroke) -> some View {
        let isSelected = controller.selectedCleanUpStrokeID == stroke.id
        let center = EditorLayoutMetrics.maskViewPoint(stroke.centroid, in: imageRect)
        return Circle()
            .fill(isSelected ? EditorTheme.accent : Color.white.opacity(0.85))
            .frame(width: 14 / zoomScale, height: 14 / zoomScale)
            .overlay {
                Circle().stroke(Color.black.opacity(0.55), lineWidth: 1 / zoomScale)
            }
            .shadow(color: .black.opacity(0.5), radius: 2 / zoomScale)
            // A 14pt dot is far too small to hit, so the tap target is the usual
            // 44pt and only the dot is drawn.
            .frame(
                width: EditorLayoutMetrics.maskGuideHitTarget / zoomScale,
                height: EditorLayoutMetrics.maskGuideHitTarget / zoomScale
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
            18 / zoomScale,
            EditorLayoutMetrics.brushDiameter(size: stroke.size, in: imageRect)
        )
        return ZStack {
            Circle()
                .stroke(
                    Color.white.opacity(0.9),
                    style: StrokeStyle(
                        lineWidth: 1.5 / zoomScale,
                        dash: [5 / zoomScale, 4 / zoomScale]
                    )
                )
                .frame(width: diameter, height: diameter)
                .shadow(color: .black.opacity(0.5), radius: 1 / zoomScale)
                .allowsHitTesting(false)
            Circle()
                .fill(.white)
                .frame(
                    width: EditorLayoutMetrics.maskGuideKnobSize / zoomScale,
                    height: EditorLayoutMetrics.maskGuideKnobSize / zoomScale
                )
                .overlay {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 8 / zoomScale, weight: .bold))
                        .foregroundStyle(.black.opacity(0.7))
                }
                .shadow(color: .black.opacity(0.55), radius: 2 / zoomScale)
                .frame(
                    width: EditorLayoutMetrics.maskGuideHitTarget / zoomScale,
                    height: EditorLayoutMetrics.maskGuideHitTarget / zoomScale
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
