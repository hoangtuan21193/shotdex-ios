import SwiftUI
import UIKit

/// The photo and everything that floats over it. The image fills all the height
/// the panel does not use — there is no extra letterbox — and every control on
/// top of it is glass so it reads as chrome, not as part of the picture.
struct EditorImageStage: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel
    let histogramNamespace: Namespace.ID
    @Environment(\.displayScale) private var displayScale

    @State private var isDrawing = false
    @State private var gradientStart: NormalizedPoint?
    /// Set while a drag is *moving* an already-placed gradient — the previous
    /// touch point, so each change applies only the movement since the last one.
    @State private var gradientMoveLocation: CGPoint?
    /// Fingertip of the brush stroke being painted, in image-rect coordinates —
    /// drives the live brush-size cursor.
    @State private var brushLocation: CGPoint?
    /// Fingertip while the point-color eyedropper is down — drives the loupe.
    @State private var sampleLocation: CGPoint?
    /// Fingertip and painted path of the Clean Up stroke in progress. The path is
    /// kept here rather than read back from the recipe because Clean Up does not
    /// re-render while a finger is down.
    @State private var cleanUpLocation: CGPoint?
    @State private var cleanUpPath: [CGPoint] = []
    @State private var pinchStartScale: CGFloat = 1
    /// Where the pinch's two fingers were centred when it began, in stage points.
    /// Held for the whole gesture so the photo scales about that point rather than
    /// about the middle of the stage.
    @State private var pinchAnchor: CGPoint?
    /// True only while a pinch is in progress: the zoom readout is louder then, and
    /// is not a permanent badge on the photo.
    @State private var isZooming = false
    @State private var panStartOffset = CGSize.zero

    private var isMaskDetail: Bool {
        controller.selectedTool == .masks && controller.editingMaskAdjustments
    }

    /// While refining a mask the photo still has to be inspectable — pinch keeps
    /// zooming through the paint layer, and because that layer sits inside the
    /// zoomed stack, strokes and guides land where the finger is at any scale.
    private var isPaintingMask: Bool {
        isMaskDetail
    }

    /// The point-color eyedropper is armed: the next touch samples the photo.
    private var isSamplingColor: Bool {
        controller.selectedTool == .color && chrome.isEyedropperActive
    }

    /// Clean Up paints with one finger, exactly like the mask brush — so it keeps
    /// the photo-level gestures attached and pinch still zooms through the layer.
    private var isCleaningUp: Bool {
        controller.selectedTool == .cleanUp
    }

    /// An `EditorPaintTouchLayer` is installed over the photo, so it owns both the
    /// one-finger stroke and the two-finger pan.
    private var hasPaintLayer: Bool {
        isPaintingMask || isCleaningUp
    }

    /// Disables the photo-level gestures (zoom, pan, double-tap, hold-before)
    /// while the Crop tool is up or the eyedropper is armed, so only the
    /// crop frame / sampling layer reacts to a drag.
    private var imageGestureMask: GestureMask {
        controller.selectedTool == .crop || isSamplingColor ? .subviews : .all
    }

    var body: some View {
        GeometryReader { proxy in
            // Cropping insets the photo so the frame's edges and corners are never
            // flush with the screen — a handle on the very edge of the display is
            // hard to grab, and the crop frame starts out on the photo's border.
            let inset = controller.selectedTool == .crop
                ? EditorLayoutMetrics.cropStageInset
                : 0
            let contentSize = CGSize(
                width: max(1, proxy.size.width - inset * 2),
                height: max(1, proxy.size.height - inset * 2)
            )
            let imageRect = imageRect(in: contentSize)
                .offsetBy(dx: (proxy.size.width - contentSize.width) / 2,
                          dy: (proxy.size.height - contentSize.height) / 2)
            ZStack {
                Color.black
                content(
                    imageRect: imageRect,
                    container: contentSize,
                    stageSize: proxy.size
                )
                overlays(
                    imageRect: imageRect,
                    stageRect: CGRect(origin: .zero, size: proxy.size)
                )
            }
            .contentShape(Rectangle())
            // How big the photo actually is on screen, so the render that runs
            // while a slider is moving can aim at exactly that instead of a flat
            // 1024 — which was below the display on any modern phone and made
            // every drag look like the picture lost resolution.
            .onChange(of: imageRect.size, initial: true) { _, size in
                controller.setDisplaySize(size, scale: displayScale * chrome.zoomScale)
            }
        }
        .clipped()
    }

    @ViewBuilder
    private func content(
        imageRect: CGRect,
        container: CGSize,
        stageSize: CGSize
    ) -> some View {
        if let image = controller.previewImage {
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: container.width, height: container.height)
                    .position(x: stageSize.width / 2, y: stageSize.height / 2)

                if chrome.showsSplitCompare, let original = controller.originalPreviewImage {
                    splitCompare(original: original, imageRect: imageRect)
                }

                if controller.selectedTool == .crop {
                    EditorCropOverlay(controller: controller, imageRect: imageRect)
                }

                // The paint layer sits *inside* the zoomed stack, so a stroke lands
                // where the finger is even at 4×. It reports in stage coordinates —
                // its own bounds plus `imageRect.origin` — because that is the space
                // the cursor and the guides above it position in.
                if isPaintingMask {
                    EditorPaintTouchLayer(
                        origin: imageRect.origin,
                        onTracked: { brushLocation = $0 },
                        onBegan: { paintMask($0, in: imageRect) },
                        onMoved: { paintMask($0, in: imageRect) },
                        onEnded: { endMaskPaint($0, in: imageRect) },
                        onCancelled: cancelMaskPaint,
                        onPanBegan: beginPhotoPan,
                        onPanChanged: { panPhoto($0, imageRect: imageRect, stage: stageSize) },
                        onPanEnded: endPhotoPan
                    )
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)

                    // Above the paint layer: knob drags win, empty-photo drags
                    // fall through and re-place the gradient as before.
                    if !chrome.isFullBleed {
                        EditorMaskGuideOverlay(
                            controller: controller,
                            imageRect: imageRect,
                            zoomScale: chrome.zoomScale
                        )
                    }

                    // While a Size/Feather/Flow popup is up, the footprint the
                    // next stroke will lay down previews in the middle of the
                    // photo — Lightroom's own move — so the sliders are never
                    // adjusting an invisible number.
                    if !isDrawing,
                       controller.selectedComponent?.kind == .brush,
                       let control = chrome.activeMaskControl,
                       control != .shapeFeather {
                        EditorBrushCursor(
                            point: CGPoint(x: imageRect.midX, y: imageRect.midY),
                            size: controller.brushSize,
                            feather: controller.brushFeather,
                            isEraser: controller.brushIsEraser,
                            imageRect: imageRect,
                            zoomScale: chrome.zoomScale
                        )
                    }

                    if let brushLocation,
                       controller.selectedComponent?.kind == .brush {
                        EditorBrushCursor(
                            point: brushLocation,
                            size: controller.brushSize,
                            feather: controller.brushFeather,
                            isEraser: controller.brushIsEraser,
                            imageRect: imageRect,
                            zoomScale: chrome.zoomScale
                        )
                    }
                }

                // Same slot and shape as the mask paint layer: one finger paints,
                // two still pinch, and the guides above claim their own knobs.
                if isCleaningUp {
                    EditorPaintTouchLayer(
                        origin: imageRect.origin,
                        onTracked: { cleanUpLocation = $0.map { clamped($0, in: imageRect) } },
                        onBegan: { paintCleanUp($0, in: imageRect) },
                        onMoved: { paintCleanUp($0, in: imageRect) },
                        onEnded: { _ in endCleanUpPaint() },
                        onCancelled: cancelCleanUpPaint,
                        onPanBegan: beginPhotoPan,
                        onPanChanged: { panPhoto($0, imageRect: imageRect, stage: stageSize) },
                        onPanEnded: endPhotoPan
                    )
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)

                    if !chrome.isFullBleed {
                        EditorCleanUpOverlay(
                            controller: controller,
                            imageRect: imageRect,
                            livePath: cleanUpPath,
                            zoomScale: chrome.zoomScale
                        )
                    }

                    // The brush footprint previews in the middle of the photo
                    // while Size or Feather is being dragged, so neither slider
                    // ever adjusts an invisible number.
                    if cleanUpLocation == nil,
                       chrome.activePlainSliderID?.hasPrefix("cleanup.") == true {
                        EditorBrushCursor(
                            point: CGPoint(x: imageRect.midX, y: imageRect.midY),
                            size: controller.cleanUpSize,
                            feather: controller.cleanUpFeather,
                            isEraser: false,
                            imageRect: imageRect,
                            zoomScale: chrome.zoomScale
                        )
                    }

                    if let cleanUpLocation {
                        EditorBrushCursor(
                            point: cleanUpLocation,
                            size: controller.cleanUpSize,
                            feather: controller.cleanUpFeather,
                            isEraser: false,
                            imageRect: imageRect,
                            zoomScale: chrome.zoomScale
                        )
                    }
                }

                // Same slot and shape as the mask paint layer, and for the same
                // reason: inside the zoomed stack, a sample lands where the
                // finger is at any zoom.
                if isSamplingColor {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX, y: imageRect.midY)
                        .gesture(eyedropperGesture(in: imageRect))

                    if let sampleLocation {
                        let anchor = clamped(sampleLocation, in: imageRect)
                        if let sample = pinnedNormalized(anchor, in: imageRect) {
                            EditorColorLoupe(
                                point: sampleLocation,
                                anchor: anchor,
                                readout: controller.previewColorReadout(at: sample),
                                image: image,
                                imageRect: imageRect,
                                zoomScale: chrome.zoomScale
                            )
                        }
                    }
                }
            }
            // Anchor for the eyedropper's touches: the un-zoomed stack, the same
            // space every overlay in it positions in. The paint layers do not need
            // it — a `UIView` reports in its own bounds, transform and all.
            .coordinateSpace(name: Self.stageSpace)
            .scaleEffect(chrome.zoomScale)
            .offset(chrome.zoomOffset)
            // While cropping, the frame's own corner/edge/move gestures own the
            // photo. Leaving zoom, pan, double-tap and hold-before attached let
            // the parent's high-priority recognisers swallow handle drags, which
            // is what made the crop frame jump around.
            // Zoom is simultaneous, not exclusive: the paint layer inside the
            // stack has a recogniser of its own, and an exclusive pinch here lost
            // every arbitration against it — which is why two fingers did nothing
            // at all while the mask brush or Clean Up was up.
            .simultaneousGesture(
                zoomGesture(imageRect: imageRect, stage: stageSize),
                including: imageGestureMask
            )
            // A paint layer takes panning over entirely: one finger there is a
            // stroke, so leaving this gesture attached meant either no pan at all
            // or two recognisers moving the photo twice as far.
            .simultaneousGesture(
                panGesture(imageRect: imageRect, stage: stageSize),
                including: hasPaintLayer ? .subviews : imageGestureMask
            )
            // In a paint tool a double tap is two dabs — which is what tapping a
            // brush twice should do — so it must not also toggle full-bleed. It
            // stays live in one case only: getting *out* of full-bleed, which
            // nothing else in the chrome can do.
            .highPriorityGesture(
                doubleTapGesture,
                including: hasPaintLayer && !chrome.isFullBleed
                    ? .subviews
                    : imageGestureMask
            )
            // Off in a paint tool as well: a finger resting on the photo there is
            // the start of a stroke, not a request to see the original, and a
            // press that flashed the original and then laid down a dab on release
            // was the worst of both.
            .simultaneousGesture(
                holdBeforeGesture,
                including: hasPaintLayer ? .subviews : imageGestureMask
            )
        } else if controller.isLoading {
            ProgressView("Loading full-quality preview…")
                .tint(.white)
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func overlays(imageRect: CGRect, stageRect: CGRect) -> some View {
        ZStack {
            // Expanded, the card roams the whole stage — not just the photo: a
            // landscape shot leaves black bands above and below, and parking the
            // card there keeps it off the picture entirely. Collapsed, it is not
            // here at all: the pill lives in the top bar.
            if !chrome.isHistogramCollapsed {
                EditorHistogramCard(
                    histogram: controller.histogram,
                    chrome: chrome,
                    bounds: stageRect,
                    namespace: histogramNamespace
                )
            }

            // Live zoom readout while the fingers are still on the photo, top-left
            // like Lightroom's. It replaces a permanent `1:1` pill that said
            // nothing true past 100% and had to be read at the wrong corner.
            //
            // It stays up while the photo is zoomed, because it is also the way
            // back to 100%: pinching a photo all the way out again is fiddly, and
            // in a paint tool a double tap is two dabs, so nothing else could do
            // it. Tapping while the fingers are still down would fight the pinch,
            // so the button only acts once the gesture is over.
            if isZooming || chrome.isZoomedIn {
                Button {
                    withAnimation(EditorTheme.animation) { chrome.resetZoom() }
                    pinchStartScale = 1
                    panStartOffset = .zero
                    refreshRenderResolution(imageRect: imageRect)
                } label: {
                    EditorPillLabel(
                        text: "\(EditorLayoutMetrics.zoomPercent(chrome.zoomScale))%",
                        systemImage: isZooming
                            ? nil
                            : "arrow.down.right.and.arrow.up.left",
                        isActive: isZooming
                    )
                }
                .buttonStyle(.plain)
                .disabled(isZooming)
                .position(x: stageRect.minX + 52, y: stageRect.minY + 24)
                .transition(.opacity)
                .accessibilityLabel("Zoom \(EditorLayoutMetrics.zoomPercent(chrome.zoomScale)) percent")
                .accessibilityHint("Tap to fit the photo")
            }

            if chrome.isFullBleed {
                EditorPillLabel(text: "DOUBLE TAP TO EXIT · PINCH TO ZOOM")
                    .position(x: imageRect.midX, y: imageRect.maxY - 24)
            }

            if isSamplingColor {
                EditorPillLabel(
                    text: "DRAG ON THE PHOTO · LIFT TO PICK",
                    systemImage: "eyedropper"
                )
                    .position(x: imageRect.midX, y: imageRect.maxY - 24)
            }

            if isCleaningUp, !chrome.isFullBleed {
                // A Remove is the one edit here that is not instant, so it says so
                // rather than looking like a dropped touch.
                EditorPillLabel(
                    text: controller.isCleanUpProcessing
                        ? "FILLING…"
                        : cleanUpHint,
                    systemImage: controller.cleanUpMode.systemImage
                )
                .position(x: imageRect.midX, y: imageRect.maxY - 24)
            }
        }
    }

    private var cleanUpHint: String {
        switch controller.cleanUpMode {
        case .clone: "PAINT, THEN DRAG THE SOURCE RING"
        case .heal: "PAINT, THEN DRAG THE SOURCE RING"
        case .remove: "BRUSH OVER WHAT TO REMOVE"
        }
    }

    private func splitCompare(original: UIImage, imageRect: CGRect) -> some View {
        let dividerX = imageRect.minX + imageRect.width * chrome.splitFraction
        return ZStack {
            Image(uiImage: original)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: imageRect.width, height: imageRect.height)
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: imageRect.width * chrome.splitFraction)
                }
                .position(x: imageRect.midX, y: imageRect.midY)

            Rectangle()
                .fill(.white.opacity(0.9))
                .frame(width: 1, height: imageRect.height)
                .position(x: dividerX, y: imageRect.midY)

            Circle()
                .fill(.white)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .position(x: dividerX, y: imageRect.midY)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard imageRect.width > 0 else { return }
                            let fraction = (value.location.x - imageRect.minX)
                                / imageRect.width
                            chrome.splitFraction = min(1, max(0, fraction))
                        }
                )

            EditorPillLabel(text: "BEFORE")
                .position(x: imageRect.minX + 46, y: imageRect.minY + 24)
            EditorPillLabel(text: "AFTER", isActive: true)
                .position(x: imageRect.maxX - 44, y: imageRect.minY + 24)
        }
    }

    // MARK: Gestures

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                guard controller.selectedTool != .crop else { return }
                withAnimation(EditorTheme.animation) {
                    chrome.isFullBleed.toggle()
                }
            }
    }

    /// Press and hold anywhere on the photo to see the original, exactly like the
    /// `HOLD · BEFORE` pill. Sequencing a long press before a zero-distance drag
    /// is what gives a press that stays down until the finger lifts.
    private var holdBeforeGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                if case .second = value {
                    controller.showsOriginal = true
                }
            }
            .onEnded { _ in
                controller.showsOriginal = false
            }
    }

    private func zoomGesture(imageRect: CGRect, stage: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let anchor = pinchAnchor ?? CGPoint(
                    x: value.startAnchor.x * stage.width,
                    y: value.startAnchor.y * stage.height
                )
                if pinchAnchor == nil {
                    pinchAnchor = anchor
                    pinchStartScale = chrome.zoomScale
                }
                let scale = min(
                    EditorLayoutMetrics.maximumZoomScale,
                    max(1, pinchStartScale * value.magnification)
                )
                // Stepped from the *previous* frame rather than from the start of
                // the gesture, so a two-finger drag arriving between frames is not
                // undone: that gesture writes the offset too, and rebuilding it
                // from a start value would put it back every frame — which is
                // exactly what stopped the photo panning while zoomed.
                chrome.zoomOffset = EditorLayoutMetrics.anchoredZoomOffset(
                    anchor: anchor,
                    stage: stage,
                    startScale: chrome.zoomScale,
                    startOffset: chrome.zoomOffset,
                    scale: scale
                )
                chrome.zoomScale = scale
                // Pinching back out shrinks the photo, so an offset that was legal
                // a moment ago can now be pushing empty space onto the screen.
                clampPan(imageRect: imageRect, stage: stage)
                isZooming = true
            }
            .onEnded { _ in
                pinchAnchor = nil
                pinchStartScale = chrome.zoomScale
                if chrome.zoomScale <= 1.02 {
                    withAnimation(EditorTheme.animation) { chrome.resetZoom() }
                    pinchStartScale = 1
                }
                panStartOffset = chrome.zoomOffset
                // The picture is now drawn at `zoomScale` times the size it was
                // rendered for, so re-render at the resolution it is actually being
                // shown at. Nothing else in the editor asks for this: an edit
                // schedules its own render, a zoom does not change the recipe.
                refreshRenderResolution(imageRect: imageRect)
                withAnimation(EditorTheme.animation) { isZooming = false }
            }
    }

    /// Tells the controller how many pixels of photo are actually on screen, zoom
    /// included, and re-renders for it.
    private func refreshRenderResolution(imageRect: CGRect) {
        controller.setDisplaySize(
            imageRect.size,
            scale: displayScale * chrome.zoomScale
        )
        controller.scheduleRender()
    }

    /// Drags the zoomed photo around with one finger. Only attached when there is
    /// no paint layer: inside the brush tools the layer's own two-finger recogniser
    /// pans instead, because one finger there means paint.
    private func panGesture(imageRect: CGRect, stage: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                panPhoto(value.translation, imageRect: imageRect, stage: stage)
            }
            .onEnded { _ in
                panStartOffset = chrome.zoomOffset
            }
    }

    // MARK: Two-finger pan from a paint layer

    private func beginPhotoPan() {
        panStartOffset = chrome.zoomOffset
    }

    private func panPhoto(_ translation: CGSize, imageRect: CGRect, stage: CGSize) {
        guard chrome.isZoomedIn else { return }
        chrome.zoomOffset = EditorLayoutMetrics.clampedZoomOffset(
            CGSize(
                width: panStartOffset.width + translation.width,
                height: panStartOffset.height + translation.height
            ),
            imageSize: imageRect.size,
            zoomScale: chrome.zoomScale,
            stage: stage
        )
    }

    private func endPhotoPan() {
        panStartOffset = chrome.zoomOffset
    }

    /// Pulls the photo back until it covers at least half the stage on both axes.
    /// Without this the picture could be flung until a sliver was left at the edge,
    /// with nothing under the finger to drag it back with.
    private func clampPan(imageRect: CGRect, stage: CGSize) {
        chrome.zoomOffset = EditorLayoutMetrics.clampedZoomOffset(
            chrome.zoomOffset,
            imageSize: imageRect.size,
            zoomScale: chrome.zoomScale,
            stage: stage
        )
    }

    /// Coordinate space name for the un-zoomed content stack — what the paint
    /// gesture reads and what the brush cursor positions in.
    static let stageSpace = "editorStage"

    private func paintMask(_ touch: EditorPaintTouchLayer.Touch, in imageRect: CGRect) {
        guard let point = normalized(touch.location, in: imageRect)
        else { return }
        switch controller.selectedComponent?.kind {
        case .brush:
            brushLocation = touch.location
            if isDrawing {
                controller.continueBrushStroke(at: point)
            } else {
                isDrawing = true
                // The finger is now the control: the popup dialog gets
                // out of the way of the area being painted.
                chrome.activeMaskControl = nil
                controller.beginBrushStroke(at: point, zoomScale: chrome.zoomScale)
            }
        case .linearGradient, .radialGradient:
            // Either way, nothing happens until the finger has clearly
            // dragged. Without the gate a plain tap edited the gradient —
            // a radial collapsed to its minimum ellipse — when all the
            // tap meant was "show me the mask".
            guard gradientStart != nil || gradientMoveLocation != nil
                || hypot(touch.translation.width, touch.translation.height)
                    >= EditorLayoutMetrics.gestureArbitrationDistance
            else { return }
            if controller.selectedComponentAwaitsPlacement {
                // First drag after adding the mask: draw the shape out.
                if gradientStart == nil {
                    gradientStart = normalized(
                        touch.startLocation,
                        in: imageRect
                    ) ?? point
                    controller.beginContinuousChange()
                }
                controller.setGradient(start: gradientStart ?? point, end: point)
            } else if let previous = gradientMoveLocation {
                // Placed already: a drag anywhere on the photo moves the
                // whole shape, Snapseed control-point style. Re-dragging
                // from scratch destroyed the gradient the user was trying
                // to adjust — the single biggest "I can't refine this".
                gradientMoveLocation = touch.location
                controller.moveSelectedComponent(
                    dx: (touch.location.x - previous.x) / imageRect.width,
                    dy: (touch.location.y - previous.y) / imageRect.height
                )
            } else {
                gradientMoveLocation = touch.location
                controller.beginContinuousChange()
            }
        default:
            break
        }
    }

    private func endMaskPaint(_ touch: EditorPaintTouchLayer.Touch, in imageRect: CGRect) {
        defer { resetMaskPaintState() }
        guard let point = normalized(touch.location, in: imageRect)
        else { return }
        switch controller.selectedComponent?.kind {
        case .brush:
            controller.endBrushStroke()
        case .linearGradient, .radialGradient:
            if gradientStart == nil, gradientMoveLocation == nil {
                // The finger never travelled: a tap on the mask, answered
                // by lighting the shape (and its guides) back up.
                controller.revealMaskShape()
            } else {
                controller.endContinuousChange()
            }
        case .subject, .colorRange:
            controller.setAutomaticMaskPoint(point)
        default:
            // Sky and luminance masks have no on-image geometry to edit;
            // a tap still answers with "where is the mask".
            controller.revealMaskShape()
        }
    }

    /// A second finger arrived, so the touch was a pinch. A brush stroke rolls
    /// all the way back — a dab of paint is not what "zoom in" asks for — while a
    /// gradient that was already being dragged just settles where it is, since
    /// moving a shape is reversible by eye and by one undo.
    private func cancelMaskPaint() {
        defer { resetMaskPaintState() }
        if isDrawing {
            controller.cancelBrushStroke()
        } else if gradientStart != nil || gradientMoveLocation != nil {
            controller.endContinuousChange()
        }
    }

    private func resetMaskPaintState() {
        isDrawing = false
        gradientStart = nil
        gradientMoveLocation = nil
        brushLocation = nil
    }

    /// Paints one Clean Up stroke. The pixels only change on release — a Remove
    /// has to solve for its fill, and doing that per touch-move would stall the
    /// drag — so the drawn path is the feedback while the finger is down.
    private func paintCleanUp(_ touch: EditorPaintTouchLayer.Touch, in imageRect: CGRect) {
        cleanUpLocation = clamped(touch.location, in: imageRect)
        guard let point = normalized(touch.location, in: imageRect) else { return }
        if cleanUpPath.isEmpty {
            controller.beginCleanUpStroke(at: point, zoomScale: chrome.zoomScale)
        } else {
            controller.continueCleanUpStroke(at: point)
        }
        if let last = cleanUpPath.last,
           hypot(touch.location.x - last.x, touch.location.y - last.y) < 1 {
            return
        }
        cleanUpPath.append(touch.location)
    }

    private func endCleanUpPaint() {
        cleanUpLocation = nil
        guard !cleanUpPath.isEmpty else { return }
        cleanUpPath = []
        controller.endCleanUpStroke()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func cancelCleanUpPaint() {
        cleanUpLocation = nil
        guard !cleanUpPath.isEmpty else { return }
        cleanUpPath = []
        controller.cancelCleanUpStroke()
    }

    /// Touch-down shows the loupe, dragging refines the spot, lifting commits
    /// the sample and disarms the eyedropper. The spot is pinned to the photo, so
    /// a finger that wanders onto the letterbox picks the nearest pixel — the one
    /// the loupe was showing all along — rather than nothing at all.
    private func eyedropperGesture(in imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.stageSpace))
            .onChanged { value in
                sampleLocation = value.location
            }
            .onEnded { value in
                defer { sampleLocation = nil }
                let anchor = clamped(value.location, in: imageRect)
                guard let point = pinnedNormalized(anchor, in: imageRect) else { return }
                controller.addPointColor(sampledAt: point)
                withAnimation(EditorTheme.animation) {
                    chrome.isEyedropperActive = false
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
    }

    // MARK: Geometry

    /// Laid out from the controller's *stable* aspect rather than the preview
    /// bitmap: re-rendering the same recipe at a different resolution must not move
    /// the photo, or every guide and stroke on top of it shifts with it.
    private func imageRect(in container: CGSize) -> CGRect {
        guard controller.previewImage != nil else {
            return CGRect(origin: .zero, size: container)
        }
        return EditorLayoutMetrics.fittedRect(
            aspectRatio: controller.previewAspectRatio,
            in: container
        )
    }

    /// Keeps the brush ring on the photo. A drag that started on the picture keeps
    /// arriving once the finger wanders onto the letterbox, and points out there
    /// are dropped — so a ring floating over the black would promise a stroke that
    /// never lands.
    private func clamped(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(rect.maxX, max(rect.minX, point.x)),
            y: min(rect.maxY, max(rect.minY, point.y))
        )
    }

    private func normalized(_ point: CGPoint, in rect: CGRect) -> NormalizedPoint? {
        guard rect.contains(point), rect.width > 0, rect.height > 0 else { return nil }
        return NormalizedPoint(
            x: min(1, max(0, (point.x - rect.minX) / rect.width)),
            y: min(1, max(0, (point.y - rect.minY) / rect.height))
        )
    }

    /// Same conversion, minus the "must be on the photo" guard: a point already
    /// clamped to the image rect lands exactly on its edge, which `contains`
    /// rejects on the trailing side.
    private func pinnedNormalized(_ point: CGPoint, in rect: CGRect) -> NormalizedPoint? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        return NormalizedPoint(
            x: min(1, max(0, (point.x - rect.minX) / rect.width)),
            y: min(1, max(0, (point.y - rect.minY) / rect.height))
        )
    }
}

/// Magnifying glass over the eyedropper finger: the photo blown up around the
/// crosshair with one cell per photo pixel, the cell being read outlined in the
/// middle, and the color's hex under it. A plain swatch said *what* was under
/// the finger but not *where* to move it — the fingertip covers the pixels, so
/// aiming at one of them needs the pixels drawn somewhere the finger is not.
///
/// Held above the fingertip and free to leave the photo with it: the glass is
/// chrome floating over the stage, so at the picture's edges it hangs over the
/// letterbox instead of being shoved back inside — pinning it to the photo
/// dragged the glass out from under the hand exactly where aiming is hardest.
private struct EditorColorLoupe: View {
    /// The fingertip, unpinned — where the glass and the crosshair go.
    let point: CGPoint
    /// The same touch pinned to the photo — which pixel is being read. The two
    /// part company only once the finger has wandered past the edge, where the
    /// glass keeps showing the nearest column of real pixels.
    let anchor: CGPoint
    let readout: (color: Color, hex: String)?
    let image: UIImage
    let imageRect: CGRect
    /// The loupe lives inside the zoomed stack, so every length it draws is
    /// multiplied by the zoom on screen. All of them divide by it here: the glass
    /// is chrome, and chrome stays the same size under the finger at 100% and at
    /// 800% alike. Only the photo inside the glass magnifies.
    var zoomScale: CGFloat = 1

    private static let diameter: CGFloat = 84
    /// Photo pixels across the glass. 10 over 84pt is 8.4pt a pixel: still an
    /// easy cell to aim at, and the glass covers a quarter less of the photo.
    private static let pixelsAcross: CGFloat = 10
    private static let hexHeight: CGFloat = 18
    private static let hexSpacing: CGFloat = 5

    var body: some View {
        let scale = max(1, zoomScale)
        ZStack {
            glass
                .scaleEffect(1 / scale)
                .position(center(scale: scale))

            // Crosshair at the exact pixel being read, left uncovered by the
            // glass so the finger has something to aim with.
            Group {
                Rectangle().frame(width: 11 / scale, height: 1 / scale)
                Rectangle().frame(width: 1 / scale, height: 11 / scale)
            }
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black.opacity(0.6), radius: 1 / scale)
            .position(point)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Full height of the glass plus its hex label — the lift above the fingertip
    /// is measured from it.
    private static var height: CGFloat {
        diameter + hexSpacing + hexHeight
    }

    /// Straight above the finger, nothing clamped: the glass goes where the hand
    /// goes, off the edge of the picture included.
    private func center(scale: CGFloat) -> CGPoint {
        CGPoint(
            x: point.x,
            y: point.y - (Self.height / 2 + 30) / scale
        )
    }

    private var glass: some View {
        VStack(spacing: Self.hexSpacing) {
            ZStack {
                magnifiedPhoto
                pixelGrid
                sampledCell
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .background(.black)
            .clipShape(Circle())
            // The rim carries the sampled color, so the answer is readable
            // without looking away from the pixels.
            .overlay {
                Circle().strokeBorder(readout?.color ?? Color(white: 0.2), lineWidth: 3)
            }
            .overlay {
                Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.45), radius: 5, y: 2)

            Text(readout?.hex ?? "—")
                .font(.system(size: 10, weight: .semibold).monospaced())
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .frame(height: Self.hexHeight)
                .background(.black.opacity(0.6), in: Capsule())
        }
    }

    /// Layout points one photo pixel occupies on the un-zoomed stage, and the
    /// magnification that turns it into one cell of the glass.
    private var pixelSize: CGFloat {
        guard let cgImage = image.cgImage, cgImage.width > 0, imageRect.width > 0 else {
            return 1
        }
        return imageRect.width / CGFloat(cgImage.width)
    }

    private var cell: CGFloat { Self.diameter / Self.pixelsAcross }

    private var magnification: CGFloat { cell / pixelSize }

    /// The photo, scaled about the *centre of the pixel* under the finger rather
    /// than about the finger itself: the cell being read then sits square in the
    /// middle of the glass instead of straddling the crosshair.
    private var magnifiedPhoto: some View {
        let centre = CGPoint(
            x: imageRect.minX + (floor((anchor.x - imageRect.minX) / pixelSize) + 0.5) * pixelSize,
            y: imageRect.minY + (floor((anchor.y - imageRect.minY) / pixelSize) + 0.5) * pixelSize
        )
        return Image(uiImage: image)
            .resizable()
            // Nearest-neighbour: a pixel loupe that smooths its pixels is a
            // blur, and the cell under the crosshair has to be one flat colour.
            .interpolation(.none)
            .frame(
                width: imageRect.width * magnification,
                height: imageRect.height * magnification
            )
            .offset(
                x: (imageRect.midX - centre.x) * magnification,
                y: (imageRect.midY - centre.y) * magnification
            )
    }

    private var pixelGrid: some View {
        Canvas { context, size in
            let cellSize = cell
            guard cellSize >= 4 else { return }
            let middle = CGPoint(x: size.width / 2, y: size.height / 2)
            let steps = Int(ceil(size.width / cellSize / 2)) + 1
            var path = Path()
            for step in -steps...steps {
                let x = middle.x + (CGFloat(step) + 0.5) * cellSize
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                let y = middle.y + (CGFloat(step) + 0.5) * cellSize
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.white.opacity(0.16)), lineWidth: 0.5)
        }
        .frame(width: Self.diameter, height: Self.diameter)
    }

    /// The one cell the sample comes from — black under white so it reads on a
    /// pale pixel as well as a dark one.
    private var sampledCell: some View {
        ZStack {
            Rectangle().strokeBorder(.black.opacity(0.7), lineWidth: 3)
            Rectangle().strokeBorder(.white, lineWidth: 1.5)
        }
        .frame(width: cell, height: cell)
    }
}

/// Crop frame, dimming and rule-of-thirds grid, with the three ways Photos lets
/// you reframe: drag a corner, drag an edge, or drag inside the frame to move it.
/// A corner keeps its opposite corner as a fixed anchor for the whole drag.
struct EditorCropOverlay: View {
    @Bindable var controller: PhotoEditorController
    let imageRect: CGRect
    @State private var activeCorner: EditorCropCorner?
    @State private var fixedAnchor: NormalizedPoint?
    @State private var activeEdge: CropEdge?
    @State private var isMovingFrame = false
    @State private var moveOrigin = CGPoint.zero

    var body: some View {
        let cropRect = displayRect
        ZStack {
            Path { path in
                path.addRect(imageRect)
                path.addRect(cropRect)
            }
            .fill(.black.opacity(0.58), style: FillStyle(eoFill: true))

            grid(cropRect)

            Path { path in
                path.addRect(cropRect)
            }
            .stroke(.white.opacity(0.82), lineWidth: 1)

            // Inside the frame: pan it around. Sits below the handles so the
            // edges and corners keep priority where they overlap.
            Color.clear
                .contentShape(Rectangle())
                .frame(width: max(0, cropRect.width - 44), height: max(0, cropRect.height - 44))
                .position(x: cropRect.midX, y: cropRect.midY)
                .gesture(moveGesture)
                .accessibilityLabel("Crop frame")
                .accessibilityHint("Drag to move the crop")

            ForEach(CropEdge.allCases) { edge in
                edgeHandle(edge, in: cropRect)
            }

            ForEach(EditorCropCorner.allCases) { corner in
                // Round knobs rather than L-brackets: they read the same at every
                // corner and are an obvious grab target.
                Circle()
                    .fill(.white)
                    .frame(width: 18, height: 18)
                    .overlay {
                        Circle().stroke(.black.opacity(0.25), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .position(corner.point(in: cropRect))
                    .gesture(handleGesture(corner: corner))
                    .accessibilityLabel("Crop \(corner.rawValue) corner")
                    .accessibilityHint("Drag to resize the crop")
            }
        }
        .coordinateSpace(name: "cropCanvas")
    }

    /// Short bar in the middle of each side, with a 44pt hit area that reaches
    /// outside the frame so the edge is grabbable right on the line.
    private func edgeHandle(_ edge: CropEdge, in rect: CGRect) -> some View {
        let length: CGFloat = edge.isHorizontal
            ? min(34, max(16, rect.height * 0.3))
            : min(34, max(16, rect.width * 0.3))
        return Capsule()
            .fill(.white)
            .frame(
                width: edge.isHorizontal ? 3 : length,
                height: edge.isHorizontal ? length : 3
            )
            .frame(
                width: edge.isHorizontal ? 44 : max(44, length),
                height: edge.isHorizontal ? max(44, length) : 44
            )
            .contentShape(Rectangle())
            .position(position(of: edge, in: rect))
            .gesture(edgeGesture(edge))
            .accessibilityLabel("Crop \(edge.rawValue) edge")
            .accessibilityHint("Drag to resize the crop")
    }

    private func position(of edge: CropEdge, in rect: CGRect) -> CGPoint {
        switch edge {
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        }
    }

    private func edgeGesture(_ edge: CropEdge) -> some Gesture {
        DragGesture(coordinateSpace: .named("cropCanvas"))
            .onChanged { value in
                if activeEdge != edge {
                    activeEdge = edge
                    controller.beginContinuousChange()
                }
                guard imageRect.width > 0, imageRect.height > 0 else { return }
                let position: Double = edge.isHorizontal
                    ? (value.location.x - imageRect.minX) / imageRect.width
                    : (value.location.y - imageRect.minY) / imageRect.height
                controller.setCropEdge(edge, position: min(1, max(0, position)))
            }
            .onEnded { _ in
                activeEdge = nil
                controller.endContinuousChange()
            }
    }

    private var moveGesture: some Gesture {
        DragGesture(coordinateSpace: .named("cropCanvas"))
            .onChanged { value in
                if !isMovingFrame {
                    isMovingFrame = true
                    moveOrigin = value.location
                    controller.beginContinuousChange()
                }
                guard imageRect.width > 0, imageRect.height > 0 else { return }
                controller.moveCropRect(
                    dx: (value.location.x - moveOrigin.x) / imageRect.width,
                    dy: (value.location.y - moveOrigin.y) / imageRect.height
                )
                moveOrigin = value.location
            }
            .onEnded { _ in
                isMovingFrame = false
                controller.endContinuousChange()
            }
    }

    private var displayRect: CGRect {
        let rect = controller.recipe.crop.rect
        return CGRect(
            x: imageRect.minX + imageRect.width * rect.x,
            y: imageRect.minY + imageRect.height * rect.y,
            width: imageRect.width * rect.width,
            height: imageRect.height * rect.height
        )
    }

    private func grid(_ rect: CGRect) -> some View {
        Path { path in
            for fraction in [1.0 / 3.0, 2.0 / 3.0] {
                path.move(to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.minY))
                path.addLine(
                    to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.maxY)
                )
                path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * fraction))
                path.addLine(
                    to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * fraction)
                )
            }
        }
        .stroke(.white.opacity(0.42), lineWidth: 0.7)
    }

    private func handleGesture(corner: EditorCropCorner) -> some Gesture {
        DragGesture(coordinateSpace: .named("cropCanvas"))
            .onChanged { value in
                if activeCorner != corner {
                    activeCorner = corner
                    let anchorPoint = corner.opposite.point(
                        in: controller.recipe.crop.rect.cgRect
                    )
                    fixedAnchor = NormalizedPoint(x: anchorPoint.x, y: anchorPoint.y)
                    controller.beginContinuousChange()
                }
                guard let fixedAnchor else { return }
                let point = NormalizedPoint(
                    x: min(1, max(0, (value.location.x - imageRect.minX) / imageRect.width)),
                    y: min(1, max(0, (value.location.y - imageRect.minY) / imageRect.height))
                )
                controller.setCropCorner(
                    point,
                    fixedAnchor: fixedAnchor,
                    movesRight: corner.movesRight,
                    movesDown: corner.movesDown
                )
            }
            .onEnded { _ in
                activeCorner = nil
                fixedAnchor = nil
                controller.endContinuousChange()
            }
    }
}

enum EditorCropCorner: String, CaseIterable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String { rawValue }
    var movesRight: Bool { self == .topRight || self == .bottomRight }
    var movesDown: Bool { self == .bottomLeft || self == .bottomRight }

    var opposite: EditorCropCorner {
        switch self {
        case .topLeft: .bottomRight
        case .topRight: .bottomLeft
        case .bottomLeft: .topRight
        case .bottomRight: .topLeft
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}
