import CoreGraphics
import Foundation

/// The paths a shape layer draws, in its own local box.
///
/// Pure geometry, so every style can be checked without a renderer: the drawing
/// code only has to place the box and hand it over. All paths are built in a
/// rect whose origin is the box's corner, with y up, matching Core Graphics.
public enum ShapeOverlayGeometry {

    /// The layer's box on the image, before rotation. `width` is the layer's
    /// size in pixels and the height follows `heightRatio`.
    public static func box(center: CGPoint, width: CGFloat, heightRatio: Double) -> CGRect {
        let height = width * CGFloat(max(heightRatio, 0.01))
        return CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
    }

    public static func path(for style: OverlayShapeStyle, in rect: CGRect) -> CGPath {
        switch style {
        case .rectangle: rectanglePath(in: rect)
        case .oval: CGPath(ellipseIn: rect, transform: nil)
        case .speechBubble: speechBubblePath(in: rect)
        case .arrow: arrowPath(in: rect)
        case .line: linePath(in: rect)
        }
    }

    /// Slightly rounded, like Photos' own box: a hard 90° corner reads as a UI
    /// frame rather than as something drawn on the picture.
    public static func rectanglePath(in rect: CGRect) -> CGPath {
        let radius = min(rect.width, rect.height) * 0.06
        return CGPath(
            roundedRect: rect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
    }

    /// A rounded box with a tail from its lower-left, pointing down-left.
    public static func speechBubblePath(in rect: CGRect) -> CGPath {
        // The body takes the top 78%; the tail lives in the strip below it, so
        // the whole bubble still fits the box the user sized.
        let bodyHeight = rect.height * 0.78
        let body = CGRect(
            x: rect.minX,
            y: rect.maxY - bodyHeight,
            width: rect.width,
            height: bodyHeight
        )
        let radius = min(body.width, body.height) * 0.22
        let path = CGMutablePath()
        path.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))

        let tailLeft = CGPoint(x: body.minX + body.width * 0.20, y: body.minY)
        let tailRight = CGPoint(x: body.minX + body.width * 0.38, y: body.minY)
        let tailTip = CGPoint(x: body.minX + body.width * 0.12, y: rect.minY)
        path.move(to: tailLeft)
        path.addLine(to: tailTip)
        path.addLine(to: tailRight)
        path.closeSubpath()
        return path
    }

    /// A stroked shaft from the lower-left to the upper-right with an open head,
    /// which is what a hand-drawn arrow looks like — a filled triangle head
    /// reads as a signpost.
    public static func arrowPath(in rect: CGRect) -> CGPath {
        let start = CGPoint(x: rect.minX, y: rect.minY)
        let end = CGPoint(x: rect.maxX, y: rect.maxY)
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)

        let headLength = min(rect.width, rect.height) * 0.42
        let angle = atan2(end.y - start.y, end.x - start.x)
        // 28° either side of the shaft: wide enough to read at a glance, narrow
        // enough not to look like a chevron.
        let spread = CGFloat.pi * 28 / 180
        for sign in [CGFloat(1), CGFloat(-1)] {
            let barb = angle + .pi + sign * spread
            path.move(to: end)
            path.addLine(to: CGPoint(
                x: end.x + cos(barb) * headLength,
                y: end.y + sin(barb) * headLength
            ))
        }
        return path
    }

    public static func linePath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }

    /// Stroke thickness in pixels, floored at one so a shape never vanishes on a
    /// small preview.
    public static func strokeWidth(_ fraction: Double, shortEdge: CGFloat) -> CGFloat {
        max(1, CGFloat(max(fraction, 0)) * shortEdge)
    }

    /// The loupe's circle. Always round, whatever the box: a magnifier that can
    /// be squashed into an ellipse distorts what it is supposed to clarify.
    public static func magnifierCircle(center: CGPoint, diameter: CGFloat) -> CGRect {
        CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        )
    }

    /// The transform that magnifies the photo inside the loupe: scale about the
    /// circle's centre, so the point under the middle of the glass stays put and
    /// everything around it spreads outwards.
    public static func magnifyTransform(center: CGPoint, magnification: Double) -> CGAffineTransform {
        let scale = CGFloat(max(magnification, 1))
        return CGAffineTransform(translationX: center.x, y: center.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -center.x, y: -center.y)
    }
}


/// Drawing for shape and magnifier layers, shared by the renderer and by the
/// editor's live proxy — one implementation, so a selected shape and a baked
/// one cannot disagree about where its edge is.
public enum ShapeOverlayLayout {
    /// One shape layer: its path, in its box, rotated about its centre.
    public static func drawShape(
        _ overlay: PhotoOverlay,
        in context: CGContext,
        shortEdge: CGFloat,
        point: (NormalizedPoint) -> CGPoint
    ) {
        let center = point(overlay.center)
        let width = CGFloat(overlay.size) * shortEdge
        guard width > 0.5 else { return }
        let box = ShapeOverlayGeometry.box(
            center: .zero,
            width: width,
            heightRatio: overlay.heightRatio
        )
        let path = ShapeOverlayGeometry.path(for: overlay.shapeStyle, in: box)

        context.saveGState()
        context.setAlpha(CGFloat(overlay.opacity))
        // Built around the origin and then moved, so the rotation is about the
        // layer's own centre rather than the image's.
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: -CGFloat(overlay.rotationDegrees) * .pi / 180)
        context.addPath(path)

        let color = CGColor(
            red: overlay.fill.red,
            green: overlay.fill.green,
            blue: overlay.fill.blue,
            alpha: 1
        )
        if overlay.isFilled, overlay.shapeStyle.supportsFill {
            context.setFillColor(color)
            context.fillPath()
        } else {
            context.setStrokeColor(color)
            context.setLineWidth(
                ShapeOverlayGeometry.strokeWidth(overlay.strokeWidth, shortEdge: shortEdge)
            )
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()
        }
        context.restoreGState()
    }

    /// The ring around a loupe. Drawn even when the magnified content could not
    /// be composited: a rim with nothing in it still reads as "there is a loupe
    /// here", where nothing at all reads as a lost layer.
    public static func drawMagnifierRim(
        _ overlay: PhotoOverlay,
        in context: CGContext,
        shortEdge: CGFloat,
        point: (NormalizedPoint) -> CGPoint
    ) {
        let center = point(overlay.center)
        let diameter = CGFloat(overlay.size) * shortEdge
        guard diameter > 1 else { return }
        let circle = ShapeOverlayGeometry.magnifierCircle(center: center, diameter: diameter)
        context.saveGState()
        context.setAlpha(CGFloat(overlay.opacity))
        context.setStrokeColor(CGColor(
            red: overlay.fill.red,
            green: overlay.fill.green,
            blue: overlay.fill.blue,
            alpha: 1
        ))
        context.setLineWidth(
            ShapeOverlayGeometry.strokeWidth(overlay.strokeWidth, shortEdge: shortEdge)
        )
        context.strokeEllipse(in: circle)
        context.restoreGState()
    }

    /// The box a shape occupies on screen, for the selection outline and the
    /// drag/resize handles.
    public static func contentSize(for overlay: PhotoOverlay, shortEdge: CGFloat) -> CGSize {
        switch overlay.kind {
        case .shape:
            let width = CGFloat(overlay.size) * shortEdge
            return CGSize(width: width, height: width * CGFloat(max(overlay.heightRatio, 0.01)))
        case .magnifier:
            let diameter = CGFloat(overlay.size) * shortEdge
            return CGSize(width: diameter, height: diameter)
        case .text, .image:
            return .zero
        }
    }
}
