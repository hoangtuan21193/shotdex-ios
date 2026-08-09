import CoreGraphics
import Foundation

/// Draws a finished collage into one bitmap. Pure Core Graphics — rounded-rect
/// clipping and aspect-fill placement are CGContext's home turf, and staying
/// out of `PhotoRenderService`'s Core Image pipeline keeps this independently
/// testable and off the actor.
///
/// `images` may be sparse: a cell whose photo failed to load simply shows the
/// background, and the caller reports the failure — a partial collage is more
/// useful than no collage.
enum CollageCompositor {
    static let exportLongEdge: CGFloat = 4096

    static func render(
        recipe: CollageRecipe,
        template: CollageTemplate,
        images: [Int: CGImage],
        pixelSize: CGSize
    ) -> CGImage? {
        let width = Int(pixelSize.width.rounded())
        let height = Int(pixelSize.height.rounded())
        guard width > 0, height > 0,
              template.cellCount == recipe.cells.count,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        let canvas = CGSize(width: CGFloat(width), height: CGFloat(height))
        context.interpolationQuality = .high
        context.setAllowsAntialiasing(true)
        context.setFillColor(TextOverlayLayout.cgColor(recipe.background))
        context.fill(CGRect(origin: .zero, size: canvas))

        let gutter = CollageGeometry.gutterPixels(recipe.gutter, canvasSize: canvas)
        let radius = CollageGeometry.cornerRadiusPixels(recipe.cornerRadius, canvasSize: canvas)
        let frames = CollageGeometry.cellFrames(
            template: template,
            canvasSize: canvas,
            gutter: gutter
        )

        // Geometry is top-down; the bitmap is bottom-up. Rects flip once here.
        func flipped(_ rect: CGRect) -> CGRect {
            CGRect(
                x: rect.minX,
                y: canvas.height - rect.maxY,
                width: rect.width,
                height: rect.height
            )
        }

        for (index, frame) in frames.enumerated() {
            guard let image = images[index] else { continue }
            let cell = recipe.cells[index]
            let imageRect = CollageGeometry.imageFrame(
                imageSize: CGSize(width: image.width, height: image.height),
                cellFrame: frame,
                scale: cell.contentScale,
                offset: cell.contentOffset
            )
            let clip = flipped(frame)
            context.saveGState()
            context.addPath(CGPath(
                roundedRect: clip,
                cornerWidth: min(radius, clip.width / 2),
                cornerHeight: min(radius, clip.height / 2),
                transform: nil
            ))
            context.clip()
            context.draw(image, in: flipped(imageRect))
            context.restoreGState()
        }

        drawOverlays(recipe.overlays, in: context, canvas: canvas)
        return context.makeImage()
    }

    /// Text layers via the shared `TextOverlayLayout`, with the same y-flip
    /// point closure the photo pipeline injects. Image overlays (signatures)
    /// are not offered in the collage panel, so `.image` layers are skipped.
    private static func drawOverlays(
        _ overlays: [PhotoOverlay],
        in context: CGContext,
        canvas: CGSize
    ) {
        let visible = overlays.filter(\.hasVisibleEffect)
        guard !visible.isEmpty else { return }
        let extent = CGRect(origin: .zero, size: canvas)
        let shortEdge = min(canvas.width, canvas.height)
        let point: (NormalizedPoint) -> CGPoint = { normalized in
            CGPoint(x: canvas.width * normalized.x, y: canvas.height * (1 - normalized.y))
        }
        for overlay in visible where overlay.kind == .text {
            TextOverlayLayout.drawText(
                overlay,
                resolvedText: overlay.text,
                in: context,
                extent: extent,
                shortEdge: shortEdge,
                point: point
            )
        }
    }
}
