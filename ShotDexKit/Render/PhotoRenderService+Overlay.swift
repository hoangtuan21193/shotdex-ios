import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// Decoded signature images, keyed by the identifier the recipe carries.
///
/// Same shape and the same reasoning as `FilmLookTableCache`: the composite is a
/// `static` step on the render graph so it can serve the editor, the exporter and
/// the Live Photo frame processor alike, which means it cannot lean on actor
/// isolation and carries its own lock. Small capacity — a photo has one or two
/// signatures on it, not twenty.
private final class OverlayImageCache: @unchecked Sendable {
    public static let shared = OverlayImageCache()

    private static let capacity = 8
    private let lock = NSLock()
    private let store = OverlayImageStore()
    private var images: [UUID: CGImage] = [:]
    private var order: [UUID] = []

    public func image(for id: UUID) -> CGImage? {
        lock.lock()
        if let cached = images[id] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // Decoded outside the lock, like the film tables: a signature is a small
        // PNG, but holding the lock through a file read would stall every other
        // render that wants a different one.
        guard let data = try? Data(contentsOf: store.url(for: id)),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        lock.lock()
        if images[id] == nil {
            images[id] = image
            order.append(id)
            while order.count > Self.capacity {
                images.removeValue(forKey: order.removeFirst())
            }
        }
        lock.unlock()
        return image
    }
}

public extension PhotoRenderService {
    /// Draws the text and signature layers over a finished photo.
    ///
    /// Deliberately the last thing that happens to the pixels, and deliberately
    /// after any downscale: nothing in the tone, colour or film-look chain may tint
    /// a caption, the crop and straighten must not skew it, and a Lanczos pass
    /// after the fact would soften the very edges that make small text readable.
    ///
    /// `overlay.text` is expected to be already resolved — the controller expands
    /// `{camera}` before it hands a recipe to the renderer, so this layer has no
    /// opinion about tokens.
    static func applyOverlays(_ overlays: [PhotoOverlay], to input: CIImage) -> CIImage {
        // Loupes first, and against the image itself: a magnifier shows the
        // photo under it, so it has to be composited before anything drawn on
        // top of the photo — a caption inside a loupe would otherwise be the
        // caption magnified, which is not what anyone means.
        let magnified = applyMagnifiers(overlays, to: input)
        guard let layer = overlayLayer(overlays, extent: input.extent) else { return magnified }
        return layer.composited(over: magnified).cropped(to: input.extent)
    }

    /// Composites each loupe: the photo scaled about the circle's centre,
    /// masked to that circle, with a rim drawn over it.
    static func applyMagnifiers(_ overlays: [PhotoOverlay], to input: CIImage) -> CIImage {
        let loupes = overlays.filter { $0.kind == .magnifier && $0.hasVisibleEffect }
        let extent = input.extent
        guard !loupes.isEmpty, !extent.isInfinite, !extent.isEmpty else { return input }

        let shortEdge = min(extent.width, extent.height)
        var result = input
        for loupe in loupes {
            let center = CGPoint(
                x: extent.minX + extent.width * loupe.center.x,
                y: extent.minY + extent.height * (1 - loupe.center.y)
            )
            let diameter = CGFloat(loupe.size) * shortEdge
            let circle = ShapeOverlayGeometry.magnifierCircle(center: center, diameter: diameter)
            guard circle.width > 1 else { continue }

            let enlarged = result.transformed(
                by: ShapeOverlayGeometry.magnifyTransform(
                    center: center,
                    magnification: loupe.magnification
                )
            )
            guard let mask = circleMask(circle: circle, extent: extent, opacity: loupe.opacity)
            else { continue }
            // `blendWithMask` rather than a crop: a cropped CIImage keeps hard
            // pixel edges, and the loupe's rim would show a stair-stepped circle
            // at export resolution.
            guard let blend = CIFilter(name: "CIBlendWithMask", parameters: [
                kCIInputImageKey: enlarged,
                kCIInputBackgroundImageKey: result,
                kCIInputMaskImageKey: mask,
            ])?.outputImage
            else { continue }
            result = blend.cropped(to: extent)
        }
        return result
    }

    /// White disc on black, the shape of one loupe, as a mask.
    private static func circleMask(circle: CGRect, extent: CGRect, opacity: Double) -> CIImage? {
        let width = Int(extent.width.rounded())
        let height = Int(extent.height.rounded())
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGImageAlphaInfo.none.rawValue
              )
        else { return nil }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.setFillColor(CGColor(gray: min(max(opacity, 0), 1), alpha: 1))
        context.fillEllipse(in: circle.offsetBy(dx: -extent.minX, dy: -extent.minY))
        guard let image = context.makeImage() else { return nil }
        return CIImage(cgImage: image)
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    /// The layers alone, on transparent pixels, positioned on `extent`.
    ///
    /// Exposed separately for the Live Photo frame processor: every frame is the
    /// same size, so it rasterizes once and composites the same layer over each
    /// frame rather than laying out Core Text ninety times.
    static func overlayLayer(_ overlays: [PhotoOverlay], extent: CGRect) -> CIImage? {
        // A loupe's magnified content is not in this bitmap — that is
        // composited against the photo itself by `applyMagnifiers`, because it
        // draws what is underneath. Its rim is, so the rim sits above the other
        // markup the way every drawn layer does.
        let visible = overlays.filter(\.hasVisibleEffect)
        guard !visible.isEmpty, !extent.isInfinite, !extent.isEmpty,
              let layer = rasterizedOverlayImage(visible, extent: extent)
        else { return nil }
        return CIImage(cgImage: layer)
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    /// All layers into one bitmap rather than one composite per layer: Core Text
    /// and `CGContext.draw` are CPU work either way, and a single source-over pass
    /// keeps the Core Image graph flat.
    ///
    /// Internal (not private) because the collage canvas previews its text
    /// overlays through the exact same rasterization — one implementation,
    /// no CI wrapper needed there.
    static func rasterizedOverlayImage(
        _ overlays: [PhotoOverlay],
        extent: CGRect
    ) -> CGImage? {
        let width = Int(extent.width.rounded())
        let height = Int(extent.height.rounded())
        guard width > 0, height > 0,
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

        // The bitmap is drawn in its own zero-origin space and the result is moved
        // onto the image's extent afterwards, so the layers never have to know
        // about a cropped image's offset origin.
        let local = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        let shortEdge = min(local.width, local.height)
        // The one place the y-flip happens, mirroring `imagePoint`: recipe
        // geometry measures y downward from the top, Core Graphics upward from
        // the bottom.
        let point: (NormalizedPoint) -> CGPoint = { normalized in
            CGPoint(
                x: local.width * normalized.x,
                y: local.height * (1 - normalized.y)
            )
        }

        context.interpolationQuality = .high
        context.setAllowsAntialiasing(true)
        for overlay in overlays {
            switch overlay.kind {
            case .text:
                TextOverlayLayout.drawText(
                    overlay,
                    resolvedText: overlay.text,
                    in: context,
                    extent: local,
                    shortEdge: shortEdge,
                    point: point
                )
            case .shape:
                ShapeOverlayLayout.drawShape(
                    overlay, in: context, shortEdge: shortEdge, point: point
                )
            case .magnifier:
                ShapeOverlayLayout.drawMagnifierRim(
                    overlay, in: context, shortEdge: shortEdge, point: point
                )
            case .drawing:
                // Stack order is the point of a drawing *layer*: it is drawn here,
                // between the layers below and above it, not under everything.
                guard let drawing = overlay.drawing,
                      let stamp = drawingStamp(drawing, pixelWidth: width, pixelHeight: height)
                else { continue }
                context.saveGState()
                context.setAlpha(CGFloat(min(max(overlay.opacity, 0), 1)))
                context.draw(stamp.image, in: stamp.rect)
                context.restoreGState()
            case .image:
                // A signature whose cache file is gone is skipped rather than
                // drawn as a placeholder — the panel is where the user is told.
                guard let id = overlay.imageID,
                      let image = OverlayImageCache.shared.image(for: id)
                else { continue }
                TextOverlayLayout.drawImage(
                    overlay,
                    image: image,
                    in: context,
                    extent: local,
                    shortEdge: shortEdge,
                    point: point
                )
            }
        }
        return context.makeImage()
    }

}
