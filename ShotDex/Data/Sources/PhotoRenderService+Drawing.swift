import CoreGraphics
import CoreImage
import Foundation
import PencilKit
import UIKit

/// Rasterized Markup drawings, keyed by the drawing's data plus the render size.
///
/// Same shape and reasoning as `OverlayImageCache`: rasterizing a `PKDrawing` is
/// CPU work that must not run per gesture frame, so the composite is a `static`
/// step with its own lock rather than actor state, shared by the editor, the
/// exporter and the Live Photo frame processor. A drawing changes only on Done, so
/// a handful of entries (one per resolution — preview, settle, export) is plenty.
private final class DrawingLayerCache: @unchecked Sendable {
    static let shared = DrawingLayerCache()

    private static let capacity = 6
    private let lock = NSLock()
    private var images: [String: CGImage] = [:]
    private var order: [String] = []

    func image(forKey key: String, build: () -> CGImage?) -> CGImage? {
        lock.lock()
        if let cached = images[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // Rasterized outside the lock: holding it through a `PKDrawing.image` pass
        // would stall every other render waiting on a different size.
        guard let built = build() else { return nil }

        lock.lock()
        if images[key] == nil {
            images[key] = built
            order.append(key)
            while order.count > Self.capacity {
                images.removeValue(forKey: order.removeFirst())
            }
        }
        lock.unlock()
        return built
    }
}

extension PhotoRenderService {
    /// Draws the Markup layer over a finished photo. Like `applyOverlays`, this runs
    /// after the tone/colour/film chain and after the downscale, so nothing tints
    /// the marks and a Lanczos pass never softens them. Called *before* the text and
    /// signature overlays, so a caption stays legible over a scribble.
    static func applyDrawing(_ drawing: PhotoDrawing?, to input: CIImage) -> CIImage {
        guard let layer = drawingLayer(drawing, extent: input.extent) else { return input }
        return layer.composited(over: input).cropped(to: input.extent)
    }

    /// The drawing alone, on transparent pixels, positioned on `extent`. Exposed
    /// separately for the Live Photo frame processor, which composites the same
    /// rasterized layer over every frame rather than re-rasterizing per frame.
    static func drawingLayer(_ drawing: PhotoDrawing?, extent: CGRect) -> CIImage? {
        guard let drawing, drawing.hasVisibleEffect, !extent.isInfinite, !extent.isEmpty
        else { return nil }
        let width = Int(extent.width.rounded())
        let height = Int(extent.height.rounded())
        guard width > 0, height > 0 else { return nil }

        // In-process cache only, so the data hash need not be stable across launches.
        let key = "\(drawing.data.hashValue)|\(width)x\(height)"
        guard let raster = DrawingLayerCache.shared.image(forKey: key, build: {
            rasterizeDrawing(drawing, pixelWidth: width, pixelHeight: height)
        }) else { return nil }

        return CIImage(cgImage: raster)
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    /// Decodes the vector and rasterizes it to fill `pixelWidth`×`pixelHeight`.
    ///
    /// The strokes are scaled from their capture canvas by `pixelWidth /
    /// canvasWidth`, so the same vector serves every resolution crisply. The result
    /// is drawn into a bottom-up sRGB context — the same convention
    /// `TextOverlayLayout` uses for signature images — so `CIImage(cgImage:)` lands
    /// upright against the rest of the pipeline.
    private static func rasterizeDrawing(
        _ drawing: PhotoDrawing,
        pixelWidth: Int,
        pixelHeight: Int
    ) -> CGImage? {
        guard drawing.canvasWidth > 0, drawing.canvasHeight > 0,
              let pkDrawing = try? PKDrawing(data: drawing.data)
        else { return nil }

        let canvasRect = CGRect(
            x: 0,
            y: 0,
            width: drawing.canvasWidth,
            height: drawing.canvasHeight
        )
        let scale = CGFloat(pixelWidth) / CGFloat(drawing.canvasWidth)
        // `PKDrawing.image(from:scale:)` renders the vector at any scale — this is
        // what keeps the marks sharp on a full-resolution export instead of
        // upscaling a bitmap.
        guard let stamped = pkDrawing.image(from: canvasRect, scale: scale).cgImage,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.interpolationQuality = .high
        context.draw(
            stamped,
            in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        )
        return context.makeImage()
    }
}
