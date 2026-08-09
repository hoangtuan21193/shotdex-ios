import SwiftUI

/// The live collage canvas. Cells are plain `Image` views framed by the same
/// `CollageGeometry` math the exporter uses — WYSIWYG comes from shared pure
/// functions, not from re-rendering.
///
/// Gesture model ("tap selects first"):
/// - tap a cell → select it (accent border)
/// - drag the *selected* cell → pan its photo; pinch → zoom (committed
///   through `clampedContent` so the background never peeks through)
/// - drag an *unselected* cell → swap: a snapshot floats under the finger,
///   the cell underneath highlights, release swaps the two cells
/// - long-press any cell → replace its photo from the selected set
struct CollageCanvasView: View {
    @Bindable var model: CollageEditorModel
    let onReplaceRequest: (Int) -> Void
    let onEditText: (PhotoOverlay) -> Void

    /// In-flight pan/zoom for the selected cell; committed (clamped) on end.
    @State private var draftOffset: CGSize = .zero
    @State private var draftScale: CGFloat = 1
    /// In-flight swap drag.
    @State private var swappingIndex: Int?
    @State private var swapLocation: CGPoint = .zero
    @State private var dropTargetIndex: Int?

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = fittedCanvasSize(in: proxy.size)
            ZStack {
                if let template = model.template {
                    canvas(template: template, canvasSize: canvasSize)
                        .frame(width: canvasSize.width, height: canvasSize.height)
                        .clipped()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(EditorLayoutMetrics.cropStageInset / 2)
    }

    private func fittedCanvasSize(in available: CGSize) -> CGSize {
        let ratio = CGFloat(model.recipe.aspect.ratio)
        guard available.width > 0, available.height > 0 else { return .zero }
        let width = min(available.width, available.height * ratio)
        return CGSize(width: width, height: width / ratio)
    }

    @ViewBuilder
    private func canvas(template: CollageTemplate, canvasSize: CGSize) -> some View {
        let gutter = CollageGeometry.gutterPixels(model.recipe.gutter, canvasSize: canvasSize)
        let radius = CollageGeometry.cornerRadiusPixels(model.recipe.cornerRadius, canvasSize: canvasSize)
        let frames = CollageGeometry.cellFrames(
            template: template,
            canvasSize: canvasSize,
            gutter: gutter
        )

        ZStack(alignment: .topLeading) {
            backgroundColor

            ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
                cellView(index: index, frame: frame, radius: radius, frames: frames)
            }

            overlayLayer(canvasSize: canvasSize)

            if let swappingIndex, frames.indices.contains(swappingIndex) {
                floatingSwapSnapshot(index: swappingIndex, frames: frames)
            }
        }
        .coordinateSpace(name: "collageCanvas")
    }

    private var backgroundColor: Color {
        Color(
            red: model.recipe.background.red,
            green: model.recipe.background.green,
            blue: model.recipe.background.blue
        )
    }

    // MARK: - Cells

    @ViewBuilder
    private func cellView(index: Int, frame: CGRect, radius: CGFloat, frames: [CGRect]) -> some View {
        let isSelected = model.selectedCellIndex == index
        let isDropTarget = dropTargetIndex == index && swappingIndex != index
        let shape = RoundedRectangle(
            cornerRadius: min(radius, min(frame.width, frame.height) / 2),
            style: .continuous
        )
        let cell = model.recipe.cells.indices.contains(index) ? model.recipe.cells[index] : nil

        ZStack {
            if let cell, let image = model.image(for: index) {
                let placed = CollageGeometry.imageFrame(
                    imageSize: image.size,
                    cellFrame: frame,
                    scale: cell.contentScale * (isSelected ? draftScale : 1),
                    offset: cell.contentOffset
                )
                Image(uiImage: image)
                    .resizable()
                    .frame(width: placed.width, height: placed.height)
                    .position(x: placed.midX - frame.minX, y: placed.midY - frame.minY)
                    .offset(isSelected ? draftOffset : .zero)
            } else {
                EditorTheme.control
                ProgressView()
            }
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(shape)
        .overlay {
            if isSelected {
                shape.strokeBorder(EditorTheme.accent, lineWidth: 2.5)
            } else if isDropTarget {
                shape.strokeBorder(EditorTheme.accent.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6]))
            }
        }
        .opacity(swappingIndex == index ? 0.35 : 1)
        .contentShape(shape)
        .position(x: frame.midX, y: frame.midY)
        .onTapGesture { select(index) }
        .gesture(cellDragGesture(index: index, frame: frame, frames: frames))
        .simultaneousGesture(isSelected ? pinchGesture(index: index, frame: frame) : nil)
        .onLongPressGesture(minimumDuration: 0.45) { onReplaceRequest(index) }
    }

    private func select(_ index: Int) {
        model.selectedOverlayID = nil
        model.selectedCellIndex = model.selectedCellIndex == index ? nil : index
    }

    /// Drag on the selected cell = pan; on any other cell = swap.
    private func cellDragGesture(index: Int, frame: CGRect, frames: [CGRect]) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("collageCanvas"))
            .onChanged { value in
                if model.selectedCellIndex == index {
                    draftOffset = value.translation
                } else {
                    swappingIndex = index
                    swapLocation = value.location
                    dropTargetIndex = CollageGeometry.cellIndex(at: value.location, frames: frames)
                }
            }
            .onEnded { value in
                if model.selectedCellIndex == index {
                    commitPan(index: index, frame: frame, translation: value.translation)
                } else {
                    if let target = dropTargetIndex, target != index {
                        model.swapCells(index, target)
                    }
                    swappingIndex = nil
                    dropTargetIndex = nil
                }
            }
    }

    private func pinchGesture(index: Int, frame: CGRect) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                draftScale = value.magnification
            }
            .onEnded { value in
                let cell = model.recipe.cells[index]
                model.commitContentGesture(
                    cell: index,
                    scale: cell.contentScale * value.magnification,
                    offset: cell.contentOffset,
                    cellFrame: frame
                )
                draftScale = 1
            }
    }

    private func commitPan(index: Int, frame: CGRect, translation: CGSize) {
        let cell = model.recipe.cells[index]
        let offset = NormalizedPoint(
            x: cell.contentOffset.x + Double(translation.width / frame.width),
            y: cell.contentOffset.y + Double(translation.height / frame.height)
        )
        model.commitContentGesture(
            cell: index,
            scale: cell.contentScale,
            offset: offset,
            cellFrame: frame
        )
        draftOffset = .zero
    }

    @ViewBuilder
    private func floatingSwapSnapshot(index: Int, frames: [CGRect]) -> some View {
        let frame = frames[index]
        if let image = model.image(for: index) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: frame.width * 0.55, height: frame.height * 0.55)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
                .position(swapLocation)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Overlays

    /// Text overlays previewed through the exact export rasterizer — one
    /// full-canvas bitmap, recomputed when the overlays change (short captions
    /// at preview size are cheap). The selected overlay also gets a drag target.
    @ViewBuilder
    private func overlayLayer(canvasSize: CGSize) -> some View {
        let visible = model.recipe.overlays.filter(\.hasVisibleEffect)
        if !visible.isEmpty,
           let bitmap = PhotoRenderService.rasterizedOverlayImage(
               visible,
               extent: CGRect(origin: .zero, size: canvasSize)
           ) {
            Image(decorative: bitmap, scale: 1)
                .resizable()
                .frame(width: canvasSize.width, height: canvasSize.height)
                // The rasterizer draws bottom-up; SwiftUI shows top-down.
                .scaleEffect(y: -1)
                .allowsHitTesting(false)
        }

        ForEach(model.recipe.overlays) { overlay in
            overlayHandle(overlay, canvasSize: canvasSize)
        }
    }

    /// Invisible interaction target over each text layer: tap selects, tap
    /// again edits, drag moves the anchor.
    private func overlayHandle(_ overlay: PhotoOverlay, canvasSize: CGSize) -> some View {
        let isSelected = model.selectedOverlayID == overlay.id
        let center = CGPoint(
            x: canvasSize.width * overlay.center.x,
            y: canvasSize.height * overlay.center.y
        )
        let side = max(44, CGFloat(overlay.size) * min(canvasSize.width, canvasSize.height) * 1.4)
        return RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
            .strokeBorder(
                isSelected ? EditorTheme.accent.opacity(0.9) : .clear,
                style: StrokeStyle(lineWidth: 1.5, dash: [5])
            )
            .frame(width: side * 2.2, height: side)
            .contentShape(Rectangle())
            .position(center)
            .onTapGesture {
                if isSelected {
                    onEditText(overlay)
                } else {
                    model.selectedCellIndex = nil
                    model.selectedOverlayID = overlay.id
                }
            }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        guard isSelected else { return }
                        model.updateSelectedOverlay { updated in
                            updated.center = NormalizedPoint(
                                x: min(max(Double(value.location.x / canvasSize.width), 0), 1),
                                y: min(max(Double(value.location.y / canvasSize.height), 0), 1)
                            )
                        }
                    }
            )
    }
}
