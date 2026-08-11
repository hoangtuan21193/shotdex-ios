import CoreGraphics
import CoreText
import Foundation
import UIKit

/// Draws a finished collage into one bitmap. Mostly Core Graphics — rounded-rect
/// clipping and aspect-fill placement are CGContext's home turf; the one Core
/// Image touch is the blurred-photo background (§10), which CG can't do alone.
///
/// `images` may be sparse: a cell whose photo failed to load simply shows the
/// background, and the caller reports the failure — a partial collage is more
/// useful than no collage.
enum CollageCompositor {
    static let exportLongEdge: CGFloat = 4096

    /// Polaroid caption ink — the `#4A443C` from `CollageTheme` (kept as a
    /// literal here so the Domain renderer needn't depend on the Features theme).
    private static let captionInk = UIColor(red: 0x4A / 255, green: 0x44 / 255, blue: 0x3C / 255, alpha: 1)
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

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

        // Geometry is top-down; the bitmap is bottom-up. Rects flip once here.
        func flipped(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: canvas.height - rect.maxY, width: rect.width, height: rect.height)
        }

        drawBackground(recipe: recipe, images: images, context: context, canvas: canvas)

        let gutter = CollageGeometry.gutterPixels(recipe.gutter, canvasSize: canvas)
        let radius = CollageGeometry.cornerRadiusPixels(recipe.cornerRadius, canvasSize: canvas)
        let borderWidth = CollageGeometry.gutterPixels(recipe.borderWidth, canvasSize: canvas)
        let frames = CollageGeometry.cellFrames(
            template: template,
            canvasSize: canvas,
            gutter: gutter,
            overrides: recipe.dividerWeights
        )

        for (index, frame) in frames.enumerated() {
            if recipe.isPolaroid {
                drawPolaroidCell(
                    index: index, frame: frame, radius: radius, recipe: recipe,
                    image: images[index], context: context, canvas: canvas, flipped: flipped
                )
            } else {
                drawPlainCell(
                    index: index, frame: frame, radius: radius, borderWidth: borderWidth,
                    recipe: recipe, image: images[index], context: context, flipped: flipped
                )
            }
        }

        drawOverlays(recipe.overlays, in: context, canvas: canvas)
        return context.makeImage()
    }

    // MARK: - Background

    private static func drawBackground(
        recipe: CollageRecipe, images: [Int: CGImage], context: CGContext, canvas: CGSize
    ) {
        let full = CGRect(origin: .zero, size: canvas)
        if recipe.backgroundMode == .blurredPhoto,
           let source = backgroundSource(recipe: recipe, images: images),
           let blurred = blurredImage(source, blur: recipe.backgroundBlur, canvas: canvas) {
            // Aspect-fill the blurred photo, then darken.
            let rect = aspectFillRect(imageSize: CGSize(width: blurred.width, height: blurred.height), in: full)
            context.saveGState()
            context.clip(to: full)
            context.draw(blurred, in: rect)
            context.restoreGState()
            context.setFillColor(UIColor(white: 0, alpha: recipe.backgroundDarken).cgColor)
            context.fill(full)
        } else {
            context.setFillColor(TextOverlayLayout.cgColor(recipe.background))
            context.fill(full)
        }
    }

    private static func backgroundSource(recipe: CollageRecipe, images: [Int: CGImage]) -> CGImage? {
        if let index = recipe.backgroundSourceIndex, let image = images[index] { return image }
        return recipe.cells.indices.compactMap { images[$0] }.first
    }

    private static func blurredImage(_ image: CGImage, blur: Double, canvas: CGSize) -> CGImage? {
        let ci = CIImage(cgImage: image)
        // Blur radius scales with the output so the look matches the preview.
        let radius = blur * Double(min(canvas.width, canvas.height)) * 0.05
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return image }
        // Clamp first so the blur doesn't pull in transparent edges.
        filter.setValue(ci.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return image }
        return ciContext.createCGImage(output, from: ci.extent)
    }

    // MARK: - Cells

    private static func drawPlainCell(
        index: Int, frame: CGRect, radius: CGFloat, borderWidth: CGFloat,
        recipe: CollageRecipe, image: CGImage?, context: CGContext, flipped: (CGRect) -> CGRect
    ) {
        let clip = flipped(frame)
        let cornerRadius = min(radius, min(clip.width, clip.height) / 2)
        if let image {
            let imageRect = CollageGeometry.imageFrame(
                imageSize: CGSize(width: image.width, height: image.height),
                cellFrame: frame,
                scale: recipe.cells[index].contentScale,
                offset: recipe.cells[index].contentOffset
            )
            context.saveGState()
            context.addPath(roundedPath(clip, radius: cornerRadius))
            context.clip()
            context.draw(image, in: flipped(imageRect))
            context.restoreGState()
        }
        if borderWidth > 0 {
            let inset = clip.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
            context.addPath(roundedPath(inset, radius: max(0, cornerRadius - borderWidth / 2)))
            context.setStrokeColor(TextOverlayLayout.cgColor(recipe.borderColor))
            context.setLineWidth(borderWidth)
            context.strokePath()
        }
    }

    private static func drawPolaroidCell(
        index: Int, frame: CGRect, radius: CGFloat, recipe: CollageRecipe,
        image: CGImage?, context: CGContext, canvas: CGSize, flipped: (CGRect) -> CGRect
    ) {
        let layout = CollageGeometry.polaroidLayout(cellFrame: frame)
        let plate = flipped(frame)
        let plateRadius = min(radius, min(plate.width, plate.height) / 2)

        // White plate with a soft drop shadow.
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -min(canvas.width, canvas.height) * 0.002),
            blur: min(canvas.width, canvas.height) * 0.01,
            color: UIColor(white: 0, alpha: 0.22).cgColor
        )
        context.addPath(roundedPath(plate, radius: plateRadius))
        context.setFillColor(UIColor.white.cgColor)
        context.fillPath()
        context.restoreGState()

        // Photo inset into the plate.
        if let image {
            let photo = flipped(layout.photo)
            let imageRect = CollageGeometry.imageFrame(
                imageSize: CGSize(width: image.width, height: image.height),
                cellFrame: layout.photo,
                scale: recipe.cells[index].contentScale,
                offset: recipe.cells[index].contentOffset
            )
            context.saveGState()
            context.addPath(roundedPath(photo, radius: 0))
            context.clip()
            context.draw(image, in: flipped(imageRect))
            context.restoreGState()
        }

        // Caption ink under the photo.
        let caption = recipe.cells[index].caption
        if !caption.isEmpty {
            drawCaption(caption, in: layout.caption, context: context, canvas: canvas)
        }
    }

    private static func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        CGPath(
            roundedRect: rect,
            cornerWidth: min(radius, rect.width / 2),
            cornerHeight: min(radius, rect.height / 2),
            transform: nil
        )
    }

    private static func aspectFillRect(imageSize: CGSize, in rect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Caption

    private static func drawCaption(_ text: String, in rect: CGRect, context: CGContext, canvas: CGSize) {
        let fontSize = min(rect.height * 0.55, min(canvas.width, canvas.height) * 0.03)
        let font = UIFont(name: "Georgia", size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: captionInk,
            .paragraphStyle: paragraph,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        // Vertically centre a single line inside the caption band (flipped).
        let flippedRect = CGRect(
            x: rect.minX,
            y: canvas.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        let path = CGPath(rect: flippedRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        context.saveGState()
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
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
