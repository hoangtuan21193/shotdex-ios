import SwiftUI

/// The live preview at the top of a photo widget's settings — and the surface
/// the user arranges the widget on.
///
/// It draws the widget's own `PhotoWidgetArrangedFace` over the widget's own
/// `PhotoWidgetImageLayer`, at the proportions of a real family, so what is
/// set up here is what appears on the Home Screen. It is also where the
/// arranging happens: tap a piece to select it, drag it anywhere, pinch it to
/// resize it, and move the photo behind with two fingers. Sliders for those
/// would be six more rows in a screen that already has thirty, and none of
/// them would show where the words land.
struct PhotoWidgetPreview: View {
    let kind: PhotoWidgetKind
    let settings: PhotoWidgetSettings
    let date: Date
    let weather: WeatherSnapshot?
    let calendarSnapshot: CalendarSnapshot?
    let family: PhotoWidgetPreviewFamily
    let image: Image?
    let imageAspectRatio: Double
    /// Which piece is selected, so the outline and the size controls know.
    @Binding var selection: PhotoWidgetComponent?
    /// Called **once, when a gesture ends**. While a finger is down the
    /// preview draws from its own state: writing every frame into the store
    /// fed an observable change back into the view that was measuring itself,
    /// and SwiftUI came apart in a preference-update loop.
    let onMove: (PhotoWidgetComponent, PhotoWidgetSettings.Anchor) -> Void
    let onResize: (PhotoWidgetComponent, Double) -> Void
    let onPhotoTransformChange: (_ scale: Double, _ offsetX: Double, _ offsetY: Double) -> Void

    /// Where each group landed, for hit-testing a touch.
    @State private var groupFrames: [String: (components: [PhotoWidgetComponent], rect: CGRect)] = [:]
    @State private var dragging: PhotoWidgetComponent?
    @State private var dragStartAnchor: PhotoWidgetSettings.Anchor?
    @State private var liveAnchor: PhotoWidgetSettings.Anchor?
    @State private var guides = PhotoWidgetSnapping.Result(
        anchor: .center, verticalGuides: [], horizontalGuides: []
    )
    @State private var resizeStartSize: Double?
    @State private var liveSize: Double?
    @State private var pinchStartScale: Double?
    @State private var panStartOffset: CGPoint?
    @State private var livePhotoScale: Double?
    @State private var livePhotoOffset: CGPoint?

    /// The settings as drawn: the stored ones, with whatever a gesture is
    /// currently changing laid over them.
    private var live: PhotoWidgetSettings {
        var live = settings
        if let dragging, let liveAnchor {
            live.setAnchor(liveAnchor, for: dragging, in: componentsShown)
        }
        if let selection, let liveSize {
            if selection == .time { live.timeSize = liveSize } else { live.dateSize = liveSize }
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
                    overlay: { components, contentSize in
                        selectionOverlay(for: components, size: contentSize)
                    },
                    onLayout: { components, rect in
                        groupFrames[PhotoWidgetLayout.key(for: live.anchor(for: components[0]))] =
                            (components, rect)
                    }
                )
                guideLines(size: size)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: family.cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: family.cornerRadius, style: .continuous))
            .gesture(moveGesture(in: size))
            .simultaneousGesture(pinchGesture)
            .simultaneousGesture(photoPan(in: size))
        }
        .aspectRatio(family.aspectRatio, contentMode: .fit)
        .frame(maxWidth: family.maximumWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the \(kind.title) widget")
        .accessibilityHint("Drag a line of text to move it. Pinch it to resize. Two fingers move the photo.")
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

    /// A dashed outline and four corner dots on the selected piece: without
    /// them nothing on the preview says it can be touched at all.
    @ViewBuilder
    private func selectionOverlay(for components: [PhotoWidgetComponent], size: CGSize) -> some View {
        if let selection, components.contains(selection) {
            let isMoving = dragging == selection
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(isMoving ? 0.95 : 0.8),
                    style: StrokeStyle(lineWidth: 1, dash: isMoving ? [] : [4, 3])
                )
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(isMoving ? 0.12 : 0.06))
                )
                .overlay { handles }
                .padding(-3)
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
            .frame(width: 6, height: 6)
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

    /// One finger: picks up the piece under it, then moves that piece alone.
    private func moveGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragging == nil {
                    guard let hit = component(at: value.startLocation) else {
                        selection = nil
                        return
                    }
                    selection = hit
                    dragging = hit
                    dragStartAnchor = live.anchor(for: hit)
                }
                guard let dragging, let start = dragStartAnchor else { return }
                let content = groupSize(containing: dragging)
                let available = CGSize(
                    width: max(1, size.width - content.width),
                    height: max(1, size.height - content.height)
                )
                let moved = PhotoWidgetSettings.Anchor(
                    x: start.x + value.translation.width / available.width,
                    y: start.y + value.translation.height / available.height
                )
                let others = componentsShown
                    .filter { $0 != dragging }
                    .map { live.anchor(for: $0) }
                let snapped = PhotoWidgetSnapping.snap(moved, others: others)
                guides = snapped
                liveAnchor = snapped.anchor
            }
            .onEnded { _ in
                if let dragging, let liveAnchor {
                    onMove(dragging, liveAnchor)
                }
                dragging = nil
                dragStartAnchor = nil
                liveAnchor = nil
                guides = PhotoWidgetSnapping.Result(
                    anchor: .center, verticalGuides: [], horizontalGuides: []
                )
            }
    }

    /// Pinch resizes the selected piece; with nothing selected it zooms the
    /// photo. One gesture, two jobs, told apart by whether the user has picked
    /// a piece to work on — which the outline makes visible.
    private var pinchGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                if let selection {
                    let base = selection == .time ? settings.timeSize : settings.dateSize
                    let start = resizeStartSize ?? base
                    if resizeStartSize == nil { resizeStartSize = start }
                    let range = selection == .time
                        ? PhotoWidgetSettings.timeSizeRange
                        : PhotoWidgetSettings.dateSizeRange
                    liveSize = min(max(start * value.magnification, range.lowerBound), range.upperBound)
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
                if let selection, let liveSize {
                    onResize(selection, liveSize)
                }
                resizeStartSize = nil
                liveSize = nil
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

    /// Two fingers move the photo — including at 1×, where the fill has
    /// already cropped part of it away and that part is what the drag brings
    /// into view.
    private func photoPan(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .simultaneously(with: MagnifyGesture(minimumScaleDelta: 0))
            .onChanged { value in
                guard let drag = value.first, image != nil else { return }
                let slack = PhotoWidgetImageLayer.slack(
                    in: size, aspectRatio: imageAspectRatio, scale: live.photoScale
                )
                guard slack.width > 0.5 || slack.height > 0.5 else { return }
                let start = panStartOffset ?? CGPoint(x: live.photoOffsetX, y: live.photoOffsetY)
                if panStartOffset == nil { panStartOffset = start }
                livePhotoOffset = CGPoint(
                    x: min(max(start.x + drag.translation.width / max(1, slack.width), -1), 1),
                    y: min(max(start.y + drag.translation.height / max(1, slack.height), -1), 1)
                )
            }
            .onEnded { _ in
                panStartOffset = nil
                commitPhotoTransform()
            }
    }

    // MARK: Hit testing

    private func component(at point: CGPoint) -> PhotoWidgetComponent? {
        // Last drawn wins, so a piece dragged on top of another is the one
        // picked up.
        for entry in groupFrames.values.sorted(by: { $0.rect.minY > $1.rect.minY }) {
            if entry.rect.insetBy(dx: -6, dy: -6).contains(point) {
                return entry.components.first
            }
        }
        return nil
    }

    private func groupSize(containing component: PhotoWidgetComponent) -> CGSize {
        groupFrames.values.first { $0.components.contains(component) }?.rect.size ?? .zero
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
