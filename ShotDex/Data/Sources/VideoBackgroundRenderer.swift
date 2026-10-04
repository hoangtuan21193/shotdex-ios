import CoreImage
import Foundation

/// What a fitted clip sits on (FS-12.01 §7b): one colour, the clip's own
/// frame filled and blurred, or a library photo filled. Drawn **per side,
/// before the blend** — in a crossfade each clip brings its own backdrop,
/// the way each brings its own effect.
///
/// Blur is computed at an eighth of the canvas's long edge with a radius
/// proportional to it and scaled back up, so a 1280 preview and a 3840
/// export are the same picture at different sizes, and a 4K blur costs a
/// 480-pixel blur.
enum VideoBackgroundRenderer {
    /// The fraction of the canvas the blur is computed at.
    static let blurScale: CGFloat = 1.0 / 8
    /// Sigma at Blur 100, as a fraction of the reduced long edge.
    static let blurSigmaAtFull: CGFloat = 0.06

    static func backdrop(
        behind placed: CIImage,
        canvas: CGRect,
        kind: VideoBackground.Kind,
        colour: CIColor,
        blurAmount: Double,
        image: CIImage?
    ) -> CIImage {
        switch kind {
        case .colour:
            return CIImage(color: colour).cropped(to: canvas)
        case .image:
            // A photo that is gone (deleted, or no longer shared) leaves
            // black, not the old colour (FS-12.10 §5).
            guard let image, !image.extent.isEmpty else { return CIImage(color: .black).cropped(to: canvas) }
            return cover(image, canvas: canvas)
        case .blur:
            guard !placed.extent.isEmpty, !placed.extent.isInfinite else {
                return CIImage(color: colour).cropped(to: canvas)
            }
            return blurred(cover(placed, canvas: canvas), canvas: canvas, amount: blurAmount)
        }
    }

    /// `image` scaled to cover `canvas`, centred, cropped to it.
    static func cover(_ image: CIImage, canvas: CGRect) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, !extent.isInfinite else { return image.cropped(to: canvas) }
        let scale = max(canvas.width / extent.width, canvas.height / extent.height)
        let scaled = CGSize(width: extent.width * scale, height: extent.height * scale)
        return image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(
                    translationX: canvas.minX + (canvas.width - scaled.width) / 2,
                    y: canvas.minY + (canvas.height - scaled.height) / 2
                )))
            .cropped(to: canvas)
    }

    /// The covered frame blurred at an eighth of the canvas and scaled back.
    static func blurred(_ covered: CIImage, canvas: CGRect, amount: Double) -> CIImage {
        // Lanczos, not a plain transform: an 8× bilinear shrink aliases, and
        // aliasing differs with the canvas size — the preview and the export
        // would blur different pictures.
        let small = covered.applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: blurScale,
            kCIInputAspectRatioKey: 1,
        ])
        let smallExtent = small.extent
        let sigma = CGFloat(min(max(amount, 0), 100) / 100) * max(smallExtent.width, smallExtent.height) * blurSigmaAtFull
        let soft = sigma > 0.01
            ? small.clampedToExtent().applyingGaussianBlur(sigma: Double(sigma)).cropped(to: smallExtent)
            : small
        return soft
            .samplingLinear()
            .transformed(by: CGAffineTransform(scaleX: 1 / blurScale, y: 1 / blurScale))
            .cropped(to: canvas)
    }
}
