import SwiftUI

/// The live preview at the top of a photo widget's settings — and the surface
/// the user arranges the widget on.
///
/// It draws the widget's own `PhotoWidgetFace` over the widget's own
/// `PhotoWidgetImageLayer`, at the proportions of a real family, so what is
/// set up here is what appears on the Home Screen. It is also where the
/// arranging happens: one finger drags the text, two fingers pinch and pan the
/// photo behind it. Sliders for those would be four more rows in a screen that
/// already has thirty, and none of them would show where the words land.
struct PhotoWidgetPreview: View {
    let kind: PhotoWidgetKind
    let settings: PhotoWidgetSettings
    let date: Date
    let weather: WeatherSnapshot?
    let calendarSnapshot: CalendarSnapshot?
    let family: PhotoWidgetPreviewFamily
    let image: Image?
    /// Called **once, when a gesture ends**. While a finger is down the
    /// preview draws from its own state: writing every frame into the store
    /// fed an observable change back into the view that was measuring itself,
    /// and SwiftUI came apart in a preference-update loop.
    let onAnchorChange: (PhotoWidgetSettings.Anchor) -> Void
    let onPhotoTransformChange: (_ scale: Double, _ offsetX: Double, _ offsetY: Double) -> Void

    @State private var contentSize: CGSize = .zero
    @State private var dragStartAnchor: PhotoWidgetSettings.Anchor?
    @State private var pinchStartScale: Double?
    @State private var panStartOffset: CGPoint?
    /// What the finger is doing right now, held here until it lifts.
    @State private var liveAnchor: PhotoWidgetSettings.Anchor?
    @State private var livePhotoScale: Double?
    @State private var livePhotoOffset: CGPoint?

    /// The settings as drawn: the stored ones, with whatever a gesture is
    /// currently changing laid over them.
    private var live: PhotoWidgetSettings {
        var live = settings
        if let liveAnchor { live.anchor = liveAnchor }
        if let livePhotoScale { live.photoScale = livePhotoScale }
        if let livePhotoOffset {
            live.photoOffsetX = livePhotoOffset.x
            live.photoOffsetY = livePhotoOffset.y
        }
        return live
    }

    /// The margin the text keeps from the widget's edges, matching
    /// `PhotoWidgetPositionedFace` so the preview places it identically.
    private static let inset: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                background(size: size)
                face(size: size)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: family.cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: family.cornerRadius, style: .continuous))
            .gesture(textDrag(in: size), including: .all)
            .simultaneousGesture(photoPinch)
            .simultaneousGesture(photoPan(in: size))
        }
        .aspectRatio(family.aspectRatio, contentMode: .fit)
        .frame(maxWidth: family.maximumWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the \(kind.title) widget")
        .accessibilityHint("Drag to move the text. Pinch with two fingers to zoom the photo.")
    }

    // MARK: Layers

    @ViewBuilder
    private func background(size: CGSize) -> some View {
        ZStack {
            if let image {
                PhotoWidgetImageLayer(image: image, settings: live)
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

    private func face(size: CGSize) -> some View {
        PhotoWidgetFace(
            date: date,
            settings: live,
            kind: kind,
            width: size.width,
            weather: weather,
            calendarSnapshot: calendarSnapshot,
            isCompact: family.isCompact
        )
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { contentSize = proxy.size }
                    .onChange(of: proxy.size) { _, new in contentSize = new }
            }
        }
        .padding(Self.inset)
        .offset(live.anchor.offset(in: size, contentSize: contentSize, inset: Self.inset))
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: live.anchor.alignment
        )
    }

    // MARK: Gestures

    /// One finger moves the text. The anchor is a fraction of the space the
    /// block can occupy, so the drag is measured against that space rather
    /// than the whole widget — otherwise the block would stop responding
    /// before the finger reached the edge.
    private func textDrag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let start = dragStartAnchor ?? settings.anchor
                if dragStartAnchor == nil { dragStartAnchor = start }
                let available = CGSize(
                    width: max(1, size.width - contentSize.width - Self.inset * 2),
                    height: max(1, size.height - contentSize.height - Self.inset * 2)
                )
                liveAnchor = PhotoWidgetSettings.Anchor(
                    x: start.x + value.translation.width / available.width,
                    y: start.y + value.translation.height / available.height
                )
            }
            .onEnded { _ in
                dragStartAnchor = nil
                if let liveAnchor { onAnchorChange(liveAnchor) }
                liveAnchor = nil
            }
    }

    private var photoPinch: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                let start = pinchStartScale ?? settings.photoScale
                if pinchStartScale == nil { pinchStartScale = start }
                livePhotoScale = min(
                    max(start * value.magnification, 1),
                    PhotoWidgetSettings.maximumPhotoScale
                )
            }
            .onEnded { _ in
                pinchStartScale = nil
                commitPhotoTransform()
            }
    }

    /// Two fingers move the photo under the text. It does nothing at 1×
    /// because an unzoomed photo already fills the widget and has nothing to
    /// give away.
    private func commitPhotoTransform() {
        guard livePhotoScale != nil || livePhotoOffset != nil else { return }
        let scale = livePhotoScale ?? settings.photoScale
        let offset = livePhotoOffset ?? CGPoint(x: settings.photoOffsetX, y: settings.photoOffsetY)
        livePhotoScale = nil
        livePhotoOffset = nil
        onPhotoTransformChange(scale, offset.x, offset.y)
    }

    private func photoPan(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .simultaneously(with: MagnifyGesture(minimumScaleDelta: 0))
            .onChanged { value in
                guard let drag = value.first, live.photoScale > 1 else { return }
                let start = panStartOffset ?? CGPoint(x: live.photoOffsetX, y: live.photoOffsetY)
                if panStartOffset == nil { panStartOffset = start }
                let slackX = max(1, size.width * (live.photoScale - 1) / 2)
                let slackY = max(1, size.height * (live.photoScale - 1) / 2)
                livePhotoOffset = CGPoint(
                    x: min(max(start.x + drag.translation.width / slackX, -1), 1),
                    y: min(max(start.y + drag.translation.height / slackY, -1), 1)
                )
            }
            .onEnded { _ in
                panStartOffset = nil
                commitPhotoTransform()
            }
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
