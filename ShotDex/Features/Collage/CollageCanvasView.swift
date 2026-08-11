import SwiftUI

/// The live collage canvas. Cells are plain `Image` views framed by the same
/// `CollageGeometry` math the exporter uses — WYSIWYG comes from shared pure
/// functions, not from re-rendering.
///
/// Three gestures, kept strictly apart (§7):
/// - **Drag straight on a photo** pans it inside its still cell; pinch zooms.
///   This is the cheapest, most common move — no select-first, it just works.
/// - **Hold, then drag onto another photo** swaps the two cells. The lifted
///   cell floats (scaled, tilted, shadowed, yellow border); the target tints.
/// - **Hold, then drag up to the tray** sets the photo aside; the source cell
///   goes empty at once.
///
/// The lifted-cell shadow/tilt is the *only* signal separating "carrying the
/// whole cell" from "sliding the photo inside it".
struct CollageCanvasView: View {
    @Bindable var model: CollageEditorModel
    let onFillRequest: (Int) -> Void
    let onEditText: (PhotoOverlay) -> Void

    /// In-flight pan/zoom for the cell under the finger; committed (clamped) on end.
    @State private var draftOffset: CGSize = .zero
    @State private var draftScale: CGFloat = 1
    /// Which cell is being panned/zoomed right now — drives the zoom badge.
    @State private var contentCell: Int?

    /// The whole in-flight lift, held in `@GestureState`. SwiftUI **guarantees**
    /// this resets to nil the moment the gesture ends *or is cancelled*, so the
    /// floating thumbnail is driven entirely off it and can never get stuck
    /// on-screen — the previous freeze came from a model flag surviving a
    /// cancelled gesture.
    @GestureState private var lift: LiftInfo?

    /// Haptic triggers.
    @State private var liftFeedback = 0
    @State private var dropFeedback = 0

    /// A live hold-drag: which cell is carried and where the finger is.
    private struct LiftInfo: Equatable {
        var index: Int
        var location: CGPoint
        var isOverTray: Bool
        var dropTarget: Int?
    }

    /// The seam being dragged (`nodeID#index`) and the finger's spot on it, for
    /// the highlight line and grab handle.
    @State private var activeDividerKey: String?
    @State private var dividerPoint: CGPoint = .zero

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = fittedCanvasSize(in: proxy.size)
            ZStack {
                if let template = model.template {
                    canvas(template: template, canvasSize: canvasSize)
                        .frame(width: canvasSize.width, height: canvasSize.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(EditorLayoutMetrics.cropStageInset / 2)
        .sensoryFeedback(.selection, trigger: liftFeedback)
        .sensoryFeedback(.impact, trigger: dropFeedback)
        // Mirror the gesture-state lift onto the model so the tray/HUD (in the
        // parent) can react. Because `lift` is `@GestureState`, this reliably
        // goes back to nil when the finger lifts — even on a cancelled gesture —
        // so the tray never stays stuck open.
        .onChange(of: lift?.index) { old, new in
            model.liftedCellIndex = new
            if old == nil, new != nil { liftFeedback &+= 1 }
        }
    }

    /// Fits the collage into the free space, but never wider than the frame cap
    /// (§1). Centring is the enclosing `GeometryReader` frame's job — with the
    /// tray hidden there is more free height, so the frame simply rides up.
    private func fittedCanvasSize(in available: CGSize) -> CGSize {
        let ratio = CGFloat(model.recipe.aspectRatio)
        guard available.width > 0, available.height > 0, ratio > 0 else { return .zero }
        var width = min(available.width, available.height * ratio)
        width = min(width, CollageMetrics.maxFrameWidth)
        return CGSize(width: width, height: width / ratio)
    }

    @ViewBuilder
    private func canvas(template: CollageTemplate, canvasSize: CGSize) -> some View {
        let gutter = CollageGeometry.gutterPixels(model.recipe.gutter, canvasSize: canvasSize)
        let radius = CollageGeometry.cornerRadiusPixels(model.recipe.cornerRadius, canvasSize: canvasSize)
        let frames = CollageGeometry.cellFrames(
            template: template,
            canvasSize: canvasSize,
            gutter: gutter,
            overrides: model.recipe.dividerWeights
        )

        let borderWidth = CollageGeometry.gutterPixels(model.recipe.borderWidth, canvasSize: canvasSize)

        ZStack(alignment: .topLeading) {
            backgroundView(canvasSize: canvasSize)

            ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
                cellView(index: index, frame: frame, radius: radius, borderWidth: borderWidth, frames: frames)
            }

            if !model.isShowingOriginal && !model.isLiftingCell {
                dividerLayer(template: template, canvasSize: canvasSize)
            }

            if !model.isShowingOriginal {
                overlayLayer(canvasSize: canvasSize)
            }

            if let lift, frames.indices.contains(lift.index) {
                floatingLiftSnapshot(info: lift)
            }
        }
        .coordinateSpace(name: "collageCanvas")
    }

    /// The canvas backdrop: a flat colour, or the selected photo blurred and
    /// darkened when the blurred-photo background is on (§10).
    @ViewBuilder
    private func backgroundView(canvasSize: CGSize) -> some View {
        if model.recipe.backgroundMode == .blurredPhoto, let image = blurSourceImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: canvasSize.width, height: canvasSize.height)
                .clipped()
                .blur(radius: model.recipe.backgroundBlur * min(canvasSize.width, canvasSize.height) * 0.05)
                .overlay(Color.black.opacity(model.recipe.backgroundDarken))
        } else {
            backgroundColor
        }
    }

    private var blurSourceImage: UIImage? {
        let index = model.recipe.backgroundSourceIndex
            ?? model.recipe.cells.firstIndex(where: { !$0.isEmpty })
        guard let index else { return nil }
        return model.image(for: index)
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
    private func cellView(index: Int, frame: CGRect, radius: CGFloat, borderWidth: CGFloat, frames: [CGRect]) -> some View {
        let isDropTarget = lift?.dropTarget == index && lift?.index != index
        let isLifted = lift?.index == index
        let isPolaroid = model.recipe.isPolaroid
        let cornerRadius = min(radius, min(frame.width, frame.height) / 2)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let cell = model.recipe.cells.indices.contains(index) ? model.recipe.cells[index] : nil

        Group {
            if isPolaroid {
                polaroidCell(index: index, frame: frame, radius: cornerRadius, cell: cell)
            } else {
                plainCell(index: index, frame: frame, shape: shape, cell: cell)
                    .clipShape(shape)
                    .overlay {
                        if borderWidth > 0 {
                            shape.strokeBorder(borderUIColor, lineWidth: borderWidth)
                        }
                    }
            }
        }
        .frame(width: frame.width, height: frame.height)
        .overlay { dropTargetOverlay(isDropTarget: isDropTarget, shape: shape) }
        .overlay(alignment: .bottomTrailing) { zoomBadge(index: index) }
        // The lifted source reads as vacated; the floating snapshot carries it.
        .opacity(isLifted ? 0.25 : 1)
        .contentShape(shape)
        .position(x: frame.midX, y: frame.midY)
        // A photo dragged from the tray drops into this cell (§7); any photo
        // already here is displaced back to the tray by `fillSlot`.
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            model.fillSlot(index, with: id)
            return true
        }
        .onTapGesture { tap(index) }
        .gesture(liftGesture(index: index, frames: frames))
        .simultaneousGesture(panGesture(index: index, frame: frame))
        .simultaneousGesture(contentCell == index || model.liftedCellIndex == nil
            ? pinchGesture(index: index, frame: frame) : nil)
        .accessibilityElement()
        .accessibilityLabel(cell?.isEmpty == true
            ? String(localized: "Empty slot, double tap to choose a photo")
            : String(localized: "Photo \(index + 1)"))
    }

    private var borderUIColor: Color {
        Color(red: model.recipe.borderColor.red, green: model.recipe.borderColor.green, blue: model.recipe.borderColor.blue)
    }

    /// A normal (non-Polaroid) cell: the photo aspect-filled and clipped, an
    /// empty-slot paper, or a loading placeholder.
    @ViewBuilder
    private func plainCell(index: Int, frame: CGRect, shape: RoundedRectangle, cell: CollageCell?) -> some View {
        ZStack {
            if let cell, !cell.isEmpty, let image = model.image(for: index) {
                let isActive = contentCell == index
                let placed = CollageGeometry.imageFrame(
                    imageSize: image.size,
                    cellFrame: frame,
                    scale: cell.contentScale * (isActive ? draftScale : 1),
                    offset: cell.contentOffset
                )
                Image(uiImage: image)
                    .resizable()
                    .frame(width: placed.width, height: placed.height)
                    .position(x: placed.midX - frame.minX, y: placed.midY - frame.minY)
                    .offset(isActive ? draftOffset : .zero)
            } else if let cell, cell.isEmpty {
                emptySlot(shape: shape)
            } else {
                EditorTheme.control
                ProgressView()
            }
        }
        .frame(width: frame.width, height: frame.height)
    }

    /// A Polaroid cell (§10): a white plate with a drop shadow, the photo inset
    /// into the top, a caption in the wider bottom band. Geometry comes from
    /// `CollageGeometry.polaroidLayout` so it matches the export exactly.
    @ViewBuilder
    private func polaroidCell(index: Int, frame: CGRect, radius: CGFloat, cell: CollageCell?) -> some View {
        let local = CGRect(origin: .zero, size: frame.size)
        let layout = CollageGeometry.polaroidLayout(cellFrame: local)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.white)
                .frame(width: frame.width, height: frame.height)
                .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 1)

            polaroidPhoto(index: index, layout: layout, cell: cell)

            captionView(cell: cell)
                .frame(width: layout.caption.width, height: layout.caption.height)
                .position(x: layout.caption.midX, y: layout.caption.midY)
        }
        .frame(width: frame.width, height: frame.height)
    }

    @ViewBuilder
    private func polaroidPhoto(index: Int, layout: (photo: CGRect, caption: CGRect), cell: CollageCell?) -> some View {
        let photoLocal = CGRect(origin: .zero, size: layout.photo.size)
        Group {
            if let cell, !cell.isEmpty, let image = model.image(for: index) {
                let isActive = contentCell == index
                let placed = CollageGeometry.imageFrame(
                    imageSize: image.size,
                    cellFrame: photoLocal,
                    scale: cell.contentScale * (isActive ? draftScale : 1),
                    offset: cell.contentOffset
                )
                Image(uiImage: image)
                    .resizable()
                    .frame(width: placed.width, height: placed.height)
                    .position(x: placed.midX, y: placed.midY)
                    .offset(isActive ? draftOffset : .zero)
            } else if let cell, cell.isEmpty {
                emptySlot(shape: RoundedRectangle(cornerRadius: 0, style: .continuous))
            } else {
                EditorTheme.control
                ProgressView()
            }
        }
        .frame(width: layout.photo.width, height: layout.photo.height)
        .clipped()
        .position(x: layout.photo.midX, y: layout.photo.midY)
    }

    @ViewBuilder
    private func captionView(cell: CollageCell?) -> some View {
        let text = cell?.caption ?? ""
        if text.isEmpty {
            Text("Add caption")
                .font(.system(size: 10.5).italic())
                .foregroundStyle(CollageTheme.captionPlaceholder)
                .lineLimit(1)
        } else {
            Text(text)
                .font(.custom("Georgia", size: 10.5))
                .foregroundStyle(CollageTheme.captionInk)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    @ViewBuilder
    private func dropTargetOverlay(isDropTarget: Bool, shape: RoundedRectangle) -> some View {
        if isDropTarget {
            shape.fill(EditorTheme.accent.opacity(0.16))
            shape.strokeBorder(EditorTheme.accent, lineWidth: 2)
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 3)
        }
    }

    @ViewBuilder
    private func zoomBadge(index: Int) -> some View {
        if contentCell == index, let cell = cellAt(index), !cell.isEmpty {
            let percent = Int((cell.contentScale * Double(draftScale) * 100).rounded())
            Text("\(percent)%")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.55), in: Capsule())
                .padding(AppTheme.Spacing.xs)
                .allowsHitTesting(false)
        }
    }

    /// The paper look of an unfilled cell (§6): warm off-white, an inner
    /// hairline, a `+` and `Add photo` in muted ink.
    private func emptySlot(shape: RoundedRectangle) -> some View {
        ZStack {
            CollageTheme.slotPaper
            shape
                .inset(by: 1.5)
                .strokeBorder(CollageTheme.slotBorder, lineWidth: 1.5)
            VStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .regular))
                Text("Add photo")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(CollageTheme.slotInk)
        }
    }

    // MARK: - Gesture handlers

    private func cellAt(_ index: Int) -> CollageCell? {
        model.recipe.cells.indices.contains(index) ? model.recipe.cells[index] : nil
    }

    private func isEmpty(_ index: Int) -> Bool { cellAt(index)?.isEmpty ?? true }

    private func tap(_ index: Int) {
        guard model.recipe.cells.indices.contains(index) else { return }
        if model.recipe.cells[index].isEmpty {
            onFillRequest(index)
            return
        }
        model.selectedOverlayID = nil
        model.selectedCellIndex = model.selectedCellIndex == index ? nil : index
    }

    /// Straight drag = pan the photo inside its cell. Idle while a cell is
    /// lifted or the cell is empty, so it never fights the hold-drag.
    private func panGesture(index: Int, frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("collageCanvas"))
            .onChanged { value in
                guard lift == nil, !isEmpty(index) else { return }
                contentCell = index
                draftOffset = value.translation
            }
            .onEnded { value in
                guard lift == nil, !isEmpty(index), contentCell == index else { return }
                commitPan(index: index, frame: frame, translation: value.translation)
                contentCell = nil
            }
    }

    private func pinchGesture(index: Int, frame: CGRect) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard !isEmpty(index) else { return }
                contentCell = index
                draftScale = value.magnification
            }
            .onEnded { value in
                guard !isEmpty(index), let cell = cellAt(index) else { return }
                model.commitContentGesture(
                    cell: index,
                    scale: cell.contentScale * value.magnification,
                    offset: cell.contentOffset,
                    cellFrame: frame
                )
                draftScale = 1
                contentCell = nil
            }
    }

    /// Hold, then drag: lift the whole cell. The entire in-flight state lives in
    /// `@GestureState` (`$lift`), so it is impossible for the floating thumbnail
    /// to outlive the touch — SwiftUI clears it on end *and* on cancel. The drop
    /// is committed in `onEnded`; a cancelled gesture simply returns the photo.
    /// The 0.5s hold keeps a plain pan from being mistaken for a lift.
    private func liftGesture(index: Int, frames: [CGRect]) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("collageCanvas")))
            .updating($lift) { value, state, _ in
                guard !isEmpty(index), frames.indices.contains(index) else { return }
                guard case .second(true, let drag) = value else { return }
                let location = drag?.location ?? CGPoint(x: frames[index].midX, y: frames[index].midY)
                let overTray = location.y < 0
                state = LiftInfo(
                    index: index,
                    location: location,
                    isOverTray: overTray,
                    dropTarget: overTray ? nil : CollageGeometry.cellIndex(at: location, frames: frames)
                )
            }
            .onEnded { value in
                guard case .second(_, let drag?) = value, !isEmpty(index) else { return }
                let location = drag.location
                if location.y < 0 {
                    model.setAside(index)
                    dropFeedback &+= 1
                } else if let target = CollageGeometry.cellIndex(at: location, frames: frames),
                          target != index, !isEmpty(target) {
                    model.swapCells(index, target)
                    dropFeedback &+= 1
                }
            }
    }

    private func commitPan(index: Int, frame: CGRect, translation: CGSize) {
        guard let cell = cellAt(index) else { return }
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

    // MARK: - Dividers (§9)

    /// Transparent grab strips over each seam, above the cells so a drag on a
    /// seam resizes instead of panning. The seam only shows itself — a 3pt bright
    /// line and a 14×46 handle — while it is being dragged; there is deliberately
    /// no ratio readout. Double-tap returns the seam to the template's default.
    @ViewBuilder
    private func dividerLayer(template: CollageTemplate, canvasSize: CGSize) -> some View {
        let dividers = template.dividers(overrides: model.recipe.dividerWeights)
        ForEach(Array(dividers.enumerated()), id: \.offset) { _, divider in
            dividerHandle(divider, canvasSize: canvasSize)
        }
    }

    @ViewBuilder
    private func dividerHandle(_ divider: CollageDivider, canvasSize: CGSize) -> some View {
        let key = "\(divider.nodeID)#\(divider.index)"
        let isActive = activeDividerKey == key
        let isVertical = divider.axis == .vertical
        let seam = isVertical ? divider.position * canvasSize.width : divider.position * canvasSize.height
        let crossA = isVertical ? divider.crossStart * canvasSize.height : divider.crossStart * canvasSize.width
        let crossB = isVertical ? divider.crossEnd * canvasSize.height : divider.crossEnd * canvasSize.width
        let crossMid = (crossA + crossB) / 2
        let length = crossB - crossA
        let center = isVertical ? CGPoint(x: seam, y: crossMid) : CGPoint(x: crossMid, y: seam)
        // Finger position along the seam, clamped so the handle stays on it.
        let half: CGFloat = 23
        let along = min(max(isVertical ? dividerPoint.y : dividerPoint.x, crossA + half), crossB - half)
        let gripCenter = isVertical ? CGPoint(x: seam, y: along) : CGPoint(x: along, y: seam)

        // All three pieces are siblings positioned in canvas coordinates.
        Group {
            // Grab strip — invisible, but it owns the drag in the seam region.
            Color.clear
                .frame(width: isVertical ? 24 : length, height: isVertical ? length : 24)
                .contentShape(Rectangle())
                .position(center)
                .gesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .named("collageCanvas"))
                        .onChanged { value in
                            if activeDividerKey != key {
                                model.beginDividerEdit()
                                activeDividerKey = key
                            }
                            dividerPoint = value.location
                            applyDivider(divider, at: value.location, canvasSize: canvasSize, snap: false)
                        }
                        .onEnded { value in
                            applyDivider(divider, at: value.location, canvasSize: canvasSize, snap: true)
                            activeDividerKey = nil
                        }
                )
                .onTapGesture(count: 2) { model.resetDivider(divider.nodeID) }
                .accessibilityLabel(String(localized: "Divider, drag to resize, double tap to reset"))

            if isActive {
                RoundedRectangle.app(2)
                    .fill(EditorTheme.accent)
                    .frame(width: isVertical ? 3 : length, height: isVertical ? length : 3)
                    .position(center)
                    .allowsHitTesting(false)
                RoundedRectangle.app(7)
                    .fill(EditorTheme.accent)
                    .frame(width: isVertical ? 14 : 46, height: isVertical ? 46 : 14)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    .position(gripCenter)
                    .allowsHitTesting(false)
            }
        }
    }

    private func applyDivider(_ divider: CollageDivider, at location: CGPoint, canvasSize: CGSize, snap: Bool) {
        let axisPixel = divider.axis == .vertical ? location.x : location.y
        let dimension = divider.axis == .vertical ? canvasSize.width : canvasSize.height
        let nodeStart = divider.nodeStart * dimension
        let nodeSpan = divider.nodeSpan * dimension
        guard nodeSpan > 0 else { return }
        let fraction = (axisPixel - nodeStart) / nodeSpan
        let weights = CollageDividerMath.adjustedWeights(
            divider.weights,
            boundary: divider.index,
            toFraction: Double(fraction),
            snap: snap
        )
        model.setDividerWeights(divider.nodeID, weights)
    }

    // MARK: - Lifted snapshot

    /// A small thumbnail that rides the finger — just enough to show what's being
    /// carried, not a full-size cell (kept compact per feedback). Driven entirely
    /// by `@GestureState`, so it vanishes the instant the touch ends.
    private static let liftThumbnailSize: CGFloat = 84

    @ViewBuilder
    private func floatingLiftSnapshot(info: LiftInfo) -> some View {
        if let image = model.image(for: info.index) {
            let shape = RoundedRectangle.app(AppTheme.Radius.sm)
            let side = Self.liftThumbnailSize
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipShape(shape)
                .overlay { shape.strokeBorder(EditorTheme.accent, lineWidth: 2) }
                .rotationEffect(.degrees(4))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 5)
                .opacity(info.isOverTray ? 0.75 : 1)
                .position(info.location)
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
        return RoundedRectangle.app(AppTheme.Radius.sm)
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
