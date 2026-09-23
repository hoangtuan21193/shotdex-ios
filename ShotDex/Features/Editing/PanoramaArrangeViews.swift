import SwiftUI

/// The coordinate space both halves of Arrange drag in: an outline lifted off
/// the picture and a photo lifted out of the strip have to end up in the same
/// numbers, or a drop means one thing from the stage and another from below it.
enum PanoramaArrangeSpace {
    static let name = "panoramaStage"
}

/// Frame outlines over the preview, each with a numbered handle to drag
/// (FS-14.01 §5).
///
/// The handle is a disc at the frame's centre rather than the outline itself.
/// Frames in a sweep overlap by about a third by definition, so outlines
/// overlap too, and a drag that starts inside two of them has to guess which
/// one was meant. A disc per frame cannot be ambiguous, and it doubles as the
/// element VoiceOver reads and acts on.
struct PanoramaArrangeOverlay: View {
    @Bindable var model: PanoramaMergeModel
    /// Where the preview is actually drawn inside the stage — `scaledToFit`
    /// letterboxes it, and a unit point means nothing without this rectangle.
    let imageRect: CGRect

    @State private var dragging: Int?
    @State private var translation: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.arrangedFrames.filter(\.isPlaced)) { frame in
                outline(frame)
                handle(frame)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(EditorTheme.animation, value: model.arrangedFrames)
    }

    private func outline(_ frame: PanoramaMergeModel.ArrangedFrame) -> some View {
        Path { path in
            let points = frame.outline.map(place)
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
        .stroke(
            dragging == frame.id ? EditorTheme.accent : Color.white.opacity(0.55),
            style: StrokeStyle(lineWidth: dragging == frame.id ? 2 : 1, dash: [6, 4])
        )
        .offset(dragging == frame.id ? translation : .zero)
        .allowsHitTesting(false)
    }

    private func handle(_ frame: PanoramaMergeModel.ArrangedFrame) -> some View {
        let centre = centroid(frame.outline)
        return Text("\(frame.id + 1)")
            .font(EditorTheme.rowLabel.weight(.semibold))
            .foregroundStyle(.black)
            .frame(width: 28, height: 28)
            .background(EditorTheme.accent, in: Circle())
            .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 1))
            // The touch target is the full 44pt even though the disc reads at
            // 28: a drag handle you have to be accurate to hit is a handle
            // that fights you.
            .frame(width: AppTheme.Size.minTouch, height: AppTheme.Size.minTouch)
            .contentShape(Circle())
            .position(x: centre.x, y: centre.y)
            .offset(dragging == frame.id ? translation : .zero)
            .gesture(drag(frame.id))
            .accessibilityLabel(frame.accessibilityLabel(of: model.assets.count))
            .accessibilityHint(Text("Drag to move this photo in the panorama"))
            .accessibilityAction(named: Text("Remove")) {
                model.removeFromPanorama(frame: frame.id)
            }
    }

    private func drag(_ frame: Int) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(PanoramaArrangeSpace.name))
            .onChanged { value in
                dragging = frame
                translation = value.translation
            }
            .onEnded { value in
                dragging = nil
                translation = .zero
                // Dropped off the picture: the photographer is putting it
                // aside, which is the same thing the strip's Remove does.
                guard imageRect.contains(value.location) else {
                    model.removeFromPanorama(frame: frame)
                    return
                }
                model.place(frame: frame, at: unit(value.location))
            }
    }

    private func place(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: imageRect.minX + point.x * imageRect.width,
            y: imageRect.minY + point.y * imageRect.height
        )
    }

    private func unit(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - imageRect.minX) / max(imageRect.width, 1),
            y: (point.y - imageRect.minY) / max(imageRect.height, 1)
        )
    }

    private func centroid(_ outline: [CGPoint]) -> CGPoint {
        guard !outline.isEmpty else { return .zero }
        let sum = outline.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return place(CGPoint(x: sum.x / CGFloat(outline.count), y: sum.y / CGFloat(outline.count)))
    }
}

/// The frames that are not in the picture, waiting to be dragged onto it.
///
/// Shown only while arranging: outside Arrange the count is what matters and a
/// strip of photos the user cannot act on is furniture.
struct PanoramaNotPlacedStrip: View {
    @Bindable var model: PanoramaMergeModel
    let imageRect: CGRect

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 0) {
                Text("NOT PLACED")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                Text("\(model.unplaced.count)")
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
            }
            .foregroundStyle(EditorTheme.secondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(model.unplaced, id: \.self) { frame in
                        chip(frame)
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.sm)
        .background(Color.white.opacity(0.05), in: RoundedRectangle.app(AppTheme.Radius.md))
        .padding(.horizontal, AppTheme.Spacing.md)
    }

    private func chip(_ frame: Int) -> some View {
        RoundedRectangle.app(AppTheme.Radius.sm)
            .fill(EditorTheme.control)
            .overlay {
                if let image = model.thumbnail(for: frame) {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle.app(AppTheme.Radius.sm))
            .overlay(alignment: .bottomLeading) {
                Text("\(frame + 1)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(2)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(2)
            }
            .contentShape(Rectangle())
            // A `DragGesture` here would never fire: these chips live in a
            // horizontal `ScrollView`, and the scroll view claims the pan
            // before SwiftUI's gesture sees it. The platform's own drag and
            // drop is the one thing that works inside one — the Collage tray
            // reached the same conclusion — and it comes with the lift, the
            // preview and the spring-back for free.
            .onDrag { NSItemProvider(object: PanoramaFrameDrag.token(frame) as NSString) }
            .accessibilityLabel(
                Text("Photo \(frame + 1) of \(model.assets.count), not placed")
            )
            .accessibilityHint(Text("Drag onto the panorama where it belongs"))
    }

}

/// What a chip carries while it is being dragged.
///
/// A frame index means nothing outside this screen, so it travels with a
/// prefix and the drop reads it back: anything else dropped on the stage —
/// a photo from another app, a line of text — is not ours and is ignored.
enum PanoramaFrameDrag {
    private static let prefix = "shotdex-panorama-frame:"

    static func token(_ frame: Int) -> String { "\(prefix)\(frame)" }

    static func frame(from token: String) -> Int? {
        guard token.hasPrefix(prefix) else { return nil }
        return Int(token.dropFirst(prefix.count))
    }
}

extension PanoramaMergeModel {
    /// Where `scaledToFit` puts a picture of `imageSize` inside `bounds`.
    /// Both Arrange views need it and neither should work it out twice.
    static func fittedRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
