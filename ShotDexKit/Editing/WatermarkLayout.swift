import CoreGraphics
import Foundation

/// Where a watermark block lands on one photo.
public struct WatermarkFrame: Equatable, Sendable {
    /// The block's bounding box on the photo, in pixels, y measured down from
    /// the top — the box the spec measures (FS-05.04 AC-1).
    public var box: CGRect
    /// The preset's frame at the scale it is drawn: the layers are laid out in
    /// a frame of this size, exactly as in the editor, and only the part of it
    /// under `box` is ever rasterized.
    public var frameSize: CGSize
    /// Where that frame's top-left corner sits on the photo, top-down pixels.
    /// Usually outside the photo: the frame is only a coordinate system.
    public var frameOrigin: CGPoint

    public init(box: CGRect, frameSize: CGSize, frameOrigin: CGPoint) {
        self.box = box
        self.frameSize = frameSize
        self.frameOrigin = frameOrigin
    }
}

/// The geometry of a watermark, with no drawing in it (FS-05.04 §3).
///
/// A preset's layers are positioned against the photo they were saved on. On
/// export they are laid out in a stand-in frame of that photo's shape — so the
/// logo stays beside its credit line and a caption wraps the way it did when
/// it was saved — then the block they form is scaled by the **short edge**
/// and anchored with a margin. The caller measures the layers (Core Text,
/// images, strokes) through `measure`, which keeps this file pure and lets the
/// tests drive it with a rectangle.
public enum WatermarkLayout {
    /// Short edge of the stand-in frame the natural size is measured in. Any
    /// value works; the block is measured again at the size it is drawn.
    public static let referenceShortEdge: CGFloat = 1000

    /// A frame of `aspect` (width ÷ height) whose short edge is `shortEdge`.
    public static func frameSize(aspect: Double, shortEdge: CGFloat) -> CGSize {
        let ratio = CGFloat(aspect > 0.01 ? aspect : 1.5)
        return ratio >= 1
            ? CGSize(width: shortEdge * ratio, height: shortEdge)
            : CGSize(width: shortEdge, height: shortEdge / ratio)
    }

    /// The block's height as a fraction of the frame's short edge — the size
    /// the preset was saved at, which is Size's default.
    public static func naturalSize(blockBounds: CGRect, frameSize: CGSize) -> Double {
        let shortEdge = min(frameSize.width, frameSize.height)
        guard shortEdge > 0 else { return 0 }
        return Double(blockBounds.height / shortEdge)
    }

    /// Lays the block out on a photo of `imageSize` pixels.
    ///
    /// - `measure`: the union of the layers' boxes, top-down, in a frame of the
    ///   given size; nil when nothing would be drawn.
    ///
    /// Rules, in order: height = Size × short edge; a block wider (or taller)
    /// than the photo less two margins shrinks evenly until it fits — never
    /// clipped, never re-wrapped; a corner anchor puts the block's corner
    /// `margin` from both edges, an edge anchor `margin` from that edge and
    /// centred along it, the centre anchor ignores the margin.
    public static func place(
        sourceAspect: Double,
        placement: WatermarkPlacement,
        imageSize: CGSize,
        measure: (CGSize) -> CGRect?
    ) -> WatermarkFrame? {
        guard imageSize.width >= 1, imageSize.height >= 1 else { return nil }
        let reference = frameSize(aspect: sourceAspect, shortEdge: referenceShortEdge)
        guard let natural = measure(reference), natural.width > 0, natural.height > 0 else { return nil }

        let shortEdge = min(imageSize.width, imageSize.height)
        let margin = CGFloat(placement.margin) * shortEdge
        let size = placement.size ?? naturalSize(blockBounds: natural, frameSize: reference)
        var scale = CGFloat(size) * shortEdge / natural.height
        let available = CGSize(
            width: max(1, imageSize.width - 2 * margin),
            height: max(1, imageSize.height - 2 * margin)
        )
        scale = min(scale, available.width / natural.width, available.height / natural.height)
        guard scale > 0, scale.isFinite else { return nil }

        // Measured again at the drawn size: text measurement rounds up to whole
        // pixels, so the scaled reference box can be a pixel off the real one.
        let drawnFrame = frameSize(aspect: sourceAspect, shortEdge: referenceShortEdge * scale)
        let scaledNatural = CGRect(
            x: natural.minX * scale,
            y: natural.minY * scale,
            width: natural.width * scale,
            height: natural.height * scale
        )
        let bounds = measure(drawnFrame) ?? scaledNatural

        let x: CGFloat = switch placement.anchor.column {
        case 0: margin
        case 1: (imageSize.width - bounds.width) / 2
        default: imageSize.width - margin - bounds.width
        }
        let y: CGFloat = switch placement.anchor.row {
        case 0: margin
        case 1: (imageSize.height - bounds.height) / 2
        default: imageSize.height - margin - bounds.height
        }
        return WatermarkFrame(
            box: CGRect(x: x, y: y, width: bounds.width, height: bounds.height),
            frameSize: drawnFrame,
            frameOrigin: CGPoint(x: x - bounds.minX, y: y - bounds.minY)
        )
    }

    /// Size as the stepper shows it: pixels of the photo being previewed.
    public static func pixels(forSize size: Double, shortEdge: CGFloat) -> Int {
        Int((CGFloat(size) * shortEdge).rounded())
    }

    /// The stepper's typed pixels back to a fraction of the short edge, snapped
    /// into Size's range.
    public static func size(forPixels pixels: Int, shortEdge: CGFloat) -> Double {
        guard shortEdge > 0 else { return WatermarkPlacement.sizeRange.lowerBound }
        let fraction = Double(CGFloat(pixels) / shortEdge)
        return min(max(fraction, WatermarkPlacement.sizeRange.lowerBound), WatermarkPlacement.sizeRange.upperBound)
    }
}
