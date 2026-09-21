import SwiftUI

/// The live preview at the top of a photo widget's settings — and the surface
/// the user arranges the widget on.
///
/// It draws the widget's own `PhotoWidgetArrangedFace` over the widget's own
/// `PhotoWidgetImageLayer`, at the proportions of a real family, so what is
/// set up here is what appears on the Home Screen. It is also where the
/// arranging happens: tap a piece to select it, drag it anywhere, pinch it to
/// resize it; with nothing selected the same finger moves the photo behind
/// and the same pinch zooms it. Sliders for those would be six more rows in a
/// screen that already has thirty, and none of them would show where the words
/// land.
struct PhotoWidgetPreview: View {
    let kind: PhotoWidgetKind
    let settings: PhotoWidgetSettings
    let date: Date
    let weather: WeatherSnapshot?
    let calendarSnapshot: CalendarSnapshot?
    let family: PhotoWidgetPreviewFamily
    let image: Image?
    let imageAspectRatio: Double
    /// How bright the picture is, for the Smart colour. Nil when the user
    /// picked a fixed swatch or there is no picture to measure.
    var lumaGrid: PhotoWidgetLumaGrid?
    /// Which piece is selected, so the outline and the size controls know.
    @Binding var selection: PhotoWidgetComponent?
    /// Called **once, when a gesture ends**. While a finger is down the
    /// preview draws from its own state: writing every frame into the store
    /// fed an observable change back into the view that was measuring itself,
    /// and SwiftUI came apart in a preference-update loop.
    let onMove: (PhotoWidgetComponent, PhotoWidgetSettings.Anchor) -> Void
    let onResize: (PhotoWidgetComponent, Double) -> Void
    let onPhotoTransformChange: (_ scale: Double, _ offsetX: Double, _ offsetY: Double) -> Void

    /// Where each individual line landed, for hit-testing a touch. Per line,
    /// not per stack: hit-testing the stack meant tapping the date selected
    /// the clock, and nothing below the first line could be reached at all.
    @State private var componentFrames: [PhotoWidgetComponent: CGRect] = [:]
    /// What the finger picked up when it went down, decided once per drag.
    /// One gesture, not two: a `DragGesture` for the text and a second one for
    /// the photo both recognise the same single finger, so a drag used to move
    /// a line *and* slide the picture under it at once.
    @State private var dragTarget: DragTarget?
    @State private var dragStartAnchor: PhotoWidgetSettings.Anchor?
    @State private var liveAnchor: PhotoWidgetSettings.Anchor?
    @State private var guides = PhotoWidgetSnapping.Result(
        anchor: .center, verticalGuides: [], horizontalGuides: []
    )
    @State private var resizeStartScale: Double?
    @State private var liveScale: Double?
    @State private var pinchStartScale: Double?
    @State private var panStartOffset: CGPoint?
    @State private var livePhotoScale: Double?
    @State private var livePhotoOffset: CGPoint?

    /// The piece being dragged, or nil when the photo is.
    private var dragging: PhotoWidgetComponent? {
        if case .component(let component) = dragTarget { return component }
        return nil
    }

    /// The settings as drawn: the stored ones, with whatever a gesture is
    /// currently changing laid over them.
    private var live: PhotoWidgetSettings {
        var live = settings
        if let dragging, let liveAnchor {
            live.setAnchor(liveAnchor, for: dragging, in: componentsShown)
        }
        if let selection, let liveScale {
            live.setScale(liveScale, for: selection)
        }
        if let livePhotoScale { live.photoScale = livePhotoScale }
        if let livePhotoOffset {
            live.photoOffsetX = livePhotoOffset.x
            live.photoOffsetY = livePhotoOffset.y
        }
        return live
    }

    private var componentsShown: [PhotoWidgetComponent] {
        PhotoWidgetComponent.components(for: kind, settings: settings)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                background(size: size)
                PhotoWidgetArrangedFace(
                    date: date,
                    settings: live,
                    kind: kind,
                    size: size,
                    weather: weather,
                    calendarSnapshot: calendarSnapshot,
                    isCompact: family.isCompact,
                    lumaGrid: lumaGrid,
                    imageAspectRatio: imageAspectRatio,
                    overlay: { _, _ in EmptyView() }
                )
                .coordinateSpace(name: PhotoWidgetFaceSpace.name)
                .onPreferenceChange(PhotoWidgetComponentFrames.self) { frames in
                    componentFrames = frames
                }
                selectionOverlay()
                guideLines(size: size)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: family.cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: family.cornerRadius, style: .continuous))
            .gesture(dragGesture(in: size))
            .simultaneousGesture(pinchGesture)
        }
        .aspectRatio(family.aspectRatio, contentMode: .fit)
        .frame(maxWidth: family.maximumWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the \(kind.title) widget")
        .accessibilityHint("Drag a line of text to move it, or drag the background to move the photo. Pinch to resize whatever is selected.")
    }

    // MARK: Layers

    @ViewBuilder
    private func background(size: CGSize) -> some View {
        ZStack {
            if let image {
                PhotoWidgetImageLayer(
                    image: image, settings: live, aspectRatio: imageAspectRatio
                )
            } else {
                LinearGradient(
                    colors: [.gray.opacity(0.55), .gray.opacity(0.25)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            if live.photoDimming > 0 {
                Color.black.opacity(live.photoDimming)
            }
            if live.legibility == .scrim {
                PhotoWidgetScrim(anchor: live.anchor)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// A dashed outline and four corner dots around the selected line.
    ///
    /// Drawn from the line's measured frame rather than as an overlay inside
    /// the stack, so it marks the one line the finger will move — which is
    /// what makes "select this bit" believable.
    @ViewBuilder
    private func selectionOverlay() -> some View {
        if let selection, let rect = componentFrames[selection] {
            let isMoving = dragging == selection
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(isMoving ? 0.95 : 0.85),
                    style: StrokeStyle(lineWidth: 1, dash: isMoving ? [] : [4, 3])
                )
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(isMoving ? 0.16 : 0.08))
                )
                .overlay { handles }
                .frame(width: rect.width + 8, height: rect.height + 8)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        }
    }

    /// Four corner dots. They are the "this can be grabbed" sign — the same
    /// one every canvas app uses — not separate controls: resizing is the
    /// pinch, because a 6pt dot on a 158pt preview is not a drag target.
    private var handles: some View {
        ZStack {
            handleDot(.topLeading)
            handleDot(.topTrailing)
            handleDot(.bottomLeading)
            handleDot(.bottomTrailing)
        }
    }

    private func handleDot(_ alignment: Alignment) -> some View {
        Circle()
            .fill(.white)
            .frame(width: 7, height: 7)
            .shadow(color: .black.opacity(0.5), radius: 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    /// The lines that appear when a dragged piece lands on the middle, an
    /// edge, or in line with another piece.
    @ViewBuilder
    private func guideLines(size: CGSize) -> some View {
        if dragging != nil {
            ZStack(alignment: .topLeading) {
                ForEach(guides.verticalGuides, id: \.self) { fraction in
                    Rectangle()
                        .fill(Color.yellow.opacity(0.9))
                        .frame(width: 1, height: size.height)
                        .offset(x: size.width * fraction)
                }
                ForEach(guides.horizontalGuides, id: \.self) { fraction in
                    Rectangle()
                        .fill(Color.yellow.opacity(0.9))
                        .frame(width: size.width, height: 1)
                        .offset(y: size.height * fraction)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }

    // MARK: Gestures

    /// One finger, one job, chosen when it lands: a line if it came down on
    /// one, the photo otherwise.
    ///
    /// Touching the background also *deselects*, so "nothing selected" and
    /// "dragging moves the photo" are the same state — which is what the Photo
    /// chip above the preview names.
    private enum DragTarget: Equatable {
        case component(PhotoWidgetComponent)
        case photo
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragTarget == nil {
                    if let hit = component(at: value.startLocation) {
                        selection = hit
                        dragTarget = .component(hit)
                        dragStartAnchor = live.anchor(for: hit)
                    } else {
                        selection = nil
                        dragTarget = .photo
                    }
                }
                switch dragTarget {
                case .component:
                    // A pinch drags its own centroid about, and a line that
                    // resizes while it also slides is the same two-things-at-
                    // once the photo pan used to do. The photo keeps both:
                    // zooming a picture and choosing what stays in frame is
                    // one motion.
                    guard !isPinching else { return }
                    moveComponent(by: value.translation, in: size)
                case .photo:
                    movePhoto(by: value.translation, in: size)
                case nil:
                    break
                }
            }
            .onEnded { _ in
                if let dragging, let liveAnchor {
                    onMove(dragging, liveAnchor)
                }
                commitPhotoTransform()
                dragTarget = nil
                dragStartAnchor = nil
                liveAnchor = nil
                panStartOffset = nil
                guides = PhotoWidgetSnapping.Result(
                    anchor: .center, verticalGuides: [], horizontalGuides: []
                )
            }
    }

    private var isPinching: Bool { resizeStartScale != nil || pinchStartScale != nil }

    private func moveComponent(by translation: CGSize, in size: CGSize) {
        guard let dragging, let start = dragStartAnchor else { return }
        let content = componentFrames[dragging]?.size ?? .zero
        let available = CGSize(
            width: max(1, size.width - content.width),
            height: max(1, size.height - content.height)
        )
        let moved = PhotoWidgetSettings.Anchor(
            x: start.x + translation.width / available.width,
            y: start.y + translation.height / available.height
        )
        let others = componentsShown
            .filter { $0 != dragging }
            .map { live.anchor(for: $0) }
        let snapped = PhotoWidgetSnapping.snap(moved, others: others)
        guides = snapped
        liveAnchor = snapped.anchor
    }

    /// Moves the photo behind — including at 1x, where the fill has already
    /// cropped part of it away and that part is what the drag brings into view.
    private func movePhoto(by translation: CGSize, in size: CGSize) {
        guard image != nil else { return }
        let slack = PhotoWidgetImageLayer.slack(
            in: size, aspectRatio: imageAspectRatio, scale: live.photoScale
        )
        guard slack.width > 0.5 || slack.height > 0.5 else { return }
        let start = panStartOffset ?? CGPoint(x: live.photoOffsetX, y: live.photoOffsetY)
        if panStartOffset == nil { panStartOffset = start }
        livePhotoOffset = CGPoint(
            x: min(max(start.x + translation.width / max(1, slack.width), -1), 1),
            y: min(max(start.y + translation.height / max(1, slack.height), -1), 1)
        )
    }

    /// Pinch resizes the selected piece; with nothing selected it zooms the
    /// photo. One gesture, two jobs, told apart by whether the user has picked
    /// a piece to work on — which the outline makes visible.
    private var pinchGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                if let selection {
                    // Every line resizes, not just the two with sliders: the
                    // weather block and the calendar had no size of their own.
                    let start = resizeStartScale ?? settings.scale(for: selection)
                    if resizeStartScale == nil { resizeStartScale = start }
                    let range = PhotoWidgetSettings.componentScaleRange
                    liveScale = min(
                        max(start * value.magnification, range.lowerBound), range.upperBound
                    )
                } else {
                    let start = pinchStartScale ?? settings.photoScale
                    if pinchStartScale == nil { pinchStartScale = start }
                    livePhotoScale = min(
                        max(start * value.magnification, 1),
                        PhotoWidgetSettings.maximumPhotoScale
                    )
                }
            }
            .onEnded { _ in
                if let selection, let liveScale {
                    onResize(selection, liveScale)
                }
                resizeStartScale = nil
                liveScale = nil
                pinchStartScale = nil
                commitPhotoTransform()
            }
    }

    private func commitPhotoTransform() {
        guard livePhotoScale != nil || livePhotoOffset != nil else { return }
        let scale = livePhotoScale ?? settings.photoScale
        let offset = livePhotoOffset ?? CGPoint(x: settings.photoOffsetX, y: settings.photoOffsetY)
        livePhotoScale = nil
        livePhotoOffset = nil
        onPhotoTransformChange(scale, offset.x, offset.y)
    }

    // MARK: Hit testing

    private func component(at point: CGPoint) -> PhotoWidgetComponent? {
        PhotoWidgetHitTest.component(at: point, frames: componentFrames)
    }

}

/// The widget sizes the preview can be shown at. The point sizes are the ones
/// iOS uses on a 6.1" iPhone, which is what the type sizes in Settings are
/// measured against.
enum PhotoWidgetPreviewFamily: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    var pointSize: CGSize {
        switch self {
        case .small: CGSize(width: 158, height: 158)
        case .medium: CGSize(width: 329, height: 158)
        case .large: CGSize(width: 329, height: 345)
        }
    }

    var aspectRatio: CGFloat { pointSize.width / pointSize.height }

    /// Shown at its own size where it fits, so the preview is the widget
    /// rather than a diagram of it.
    var maximumWidth: CGFloat { pointSize.width }

    var cornerRadius: CGFloat {
        switch self {
        case .small: 22
        case .medium, .large: 24
        }
    }

    var isCompact: Bool { self == .small }
}
