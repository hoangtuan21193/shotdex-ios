import CoreGraphics
import Foundation

/// Orientation and fitting math for video composition. `naturalSize` lies for
/// any phone video shot in portrait — the pixels are stored landscape and
/// `preferredTransform` says how to display them. Historically the #1 source
/// of composition bugs, which is why this lives here as pure functions with
/// tests instead of inline in the builder.
enum VideoGeometry {
    /// The size a track displays at: `naturalSize` run through its
    /// `preferredTransform` (a 90° transform swaps width and height).
    static func displaySize(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform
    ) -> CGSize {
        let rect = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    /// The full per-clip transform: normalize orientation (preferredTransform,
    /// shifted back to a zero origin), apply the user's quarter-turn rotation,
    /// then aspect-fit into `renderSize`, centred — portrait sources pillarbox
    /// on the render canvas.
    static func fitTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        quarterTurns: Int,
        renderSize: CGSize
    ) -> CGAffineTransform {
        guard naturalSize.width > 0, naturalSize.height > 0,
              renderSize.width > 0, renderSize.height > 0
        else { return .identity }

        // 1. Orientation-normalize: preferredTransform can move the frame's
        // origin off zero (a 90° rotation lands it at negative x); translate
        // the transformed bounds back to the origin.
        let transformed = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        var transform = preferredTransform.concatenating(
            CGAffineTransform(translationX: -transformed.minX, y: -transformed.minY)
        )
        var displayed = CGSize(width: abs(transformed.width), height: abs(transformed.height))

        // 2. User rotation in quarter turns about the displayed frame.
        let turns = ((quarterTurns % 4) + 4) % 4
        if turns > 0 {
            let angle = CGFloat(turns) * .pi / 2
            let rotation = CGAffineTransform(rotationAngle: angle)
            let rotatedBounds = CGRect(origin: .zero, size: displayed).applying(rotation)
            transform = transform
                .concatenating(rotation)
                .concatenating(CGAffineTransform(
                    translationX: -rotatedBounds.minX,
                    y: -rotatedBounds.minY
                ))
            displayed = CGSize(width: abs(rotatedBounds.width), height: abs(rotatedBounds.height))
        }

        // 3. Aspect-fit into the render canvas, centred.
        let scale = min(renderSize.width / displayed.width, renderSize.height / displayed.height)
        let fitted = CGSize(width: displayed.width * scale, height: displayed.height * scale)
        return transform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(
                translationX: (renderSize.width - fitted.width) / 2,
                y: (renderSize.height - fitted.height) / 2
            ))
    }

    /// Where a still photo sits on the render canvas: aspect-fit, centred.
    static func stillFitRect(imageSize: CGSize, renderSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              renderSize.width > 0, renderSize.height > 0
        else { return CGRect(origin: .zero, size: renderSize) }
        let scale = min(
            renderSize.width / imageSize.width,
            renderSize.height / imageSize.height
        )
        let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (renderSize.width - fitted.width) / 2,
            y: (renderSize.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
}
