import CoreGraphics
import CoreImage
import Foundation
import PencilKit
import UIKit

/// Rasterized drawing layers, keyed by the drawing's data plus the render size.
///
/// Rasterizing a `PKDrawing` is CPU work that must not run per gesture frame, so
/// the composite keeps its own lock rather than actor state, shared by the editor,
/// the exporter and the Live Photo frame processor.
///
/// Bounded by **bytes**, not entries: a photo can carry many drawing layers now,
/// and a full-frame raster at 48MP is ~195MB. Each entry is only the strokes'
/// bounding box, and anything bigger than a third of the budget is drawn and
/// dropped rather than kept.
private final class DrawingLayerCache: @unchecked Sendable {
    static let shared = DrawingLayerCache()

    private static let costLimit = 192 * 1024 * 1024
    private let lock = NSLock()
    private var entries: [String: (image: CGImage, cost: Int)] = [:]
    private var order: [String] = []
    private var totalCost = 0

    func image(forKey key: String, build: () -> CGImage?) -> CGImage? {
        lock.lock()
        if let cached = entries[key] {
            lock.unlock()
            return cached.image
        }
        lock.unlock()

        // Rasterized outside the lock: holding it through a `PKDrawing.image` pass
        // would stall every other render waiting on a different size.
        guard let built = build() else { return nil }
        let cost = built.bytesPerRow * built.height
        guard cost <= Self.costLimit / 3 else { return built }

        lock.lock()
        if entries[key] == nil {
            entries[key] = (built, cost)
            order.append(key)
            totalCost += cost
            while totalCost > Self.costLimit, !order.isEmpty {
                let evicted = order.removeFirst()
                totalCost -= entries.removeValue(forKey: evicted)?.cost ?? 0
            }
        }
        lock.unlock()
        return built
    }
}

extension PhotoRenderService {
    /// One drawing layer's strokes, rasterized for a `pixelWidth`×`pixelHeight`
    /// frame: the image and the rect it goes in, in the bottom-up pixel space of
    /// the overlay bitmap. Only the strokes' bounding box is rasterized, so a
    /// signature-sized scribble on a 48MP photo costs a few megabytes, not 195.
    ///
    /// The strokes are scaled from their capture canvas by `pixelWidth /
    /// canvasWidth`, so the same vector serves every resolution crisply.
    static func drawingStamp(
        _ drawing: PhotoDrawing,
        pixelWidth: Int,
        pixelHeight: Int
    ) -> (image: CGImage, rect: CGRect)? {
        guard drawing.hasVisibleEffect, pixelWidth > 0, pixelHeight > 0,
              drawing.canvasWidth > 0, drawing.canvasHeight > 0,
              let pkDrawing = try? PKDrawing(data: drawing.data)
        else { return nil }

        let canvas = CGRect(x: 0, y: 0, width: drawing.canvasWidth, height: drawing.canvasHeight)
        let bounds = pkDrawing.bounds.intersection(canvas).integral
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = CGFloat(pixelWidth) / CGFloat(drawing.canvasWidth)

        // In-process cache only, so the data hash need not be stable across launches.
        let key = "\(drawing.data.hashValue)|\(pixelWidth)x\(pixelHeight)"
        // `PKDrawing.image(from:scale:)` renders the vector at any scale — this is
        // what keeps the marks sharp on a full-resolution export instead of
        // upscaling a bitmap.
        guard let image = DrawingLayerCache.shared.image(forKey: key, build: {
            pkDrawing.image(from: bounds, scale: scale).cgImage
        }) else { return nil }

        // Canvas y runs down from the top; the overlay bitmap's runs up.
        let rect = CGRect(
            x: bounds.minX * scale,
            y: CGFloat(pixelHeight) - bounds.maxY * scale,
            width: bounds.width * scale,
            height: bounds.height * scale
        )
        return (image, rect)
    }

    /// A stamp bigger than this is not built whole: a layer whose strokes span a
    /// 48MP frame would be a second ~192MB bitmap on top of the overlay bitmap it
    /// is drawn into (FS-05.01 AC-38). It is drawn band by band instead.
    static let largestDrawingStampBytes = 24 * 1024 * 1024

    /// The canvas-space bands a drawing is rasterized in, top to bottom: one band
    /// (its bounding box) when that fits `largestDrawingStampBytes` at this size,
    /// otherwise horizontal slices that each do. Pure, so the plan is testable
    /// without rasterizing 48 megapixels.
    static func drawingBands(bounds: CGRect, scale: CGFloat) -> [CGRect] {
        guard bounds.width > 0, bounds.height > 0, scale > 0 else { return [] }
        let rowBytes = max(1, Int((bounds.width * scale).rounded(.up))) * 4
        let rowsPerBand = max(1, largestDrawingStampBytes / rowBytes)
        let bandHeight = CGFloat(rowsPerBand) / scale
        guard bounds.height > bandHeight else { return [bounds] }
        var bands: [CGRect] = []
        var top = bounds.minY
        while top < bounds.maxY {
            let height = min(bandHeight, bounds.maxY - top)
            bands.append(CGRect(x: bounds.minX, y: top, width: bounds.width, height: height))
            top += height
        }
        return bands
    }

    /// Draws one drawing layer into the overlay bitmap. Small drawings go through
    /// the cached `drawingStamp`; large ones are rasterized one band at a time and
    /// each band is released before the next is built, so the extra memory is one
    /// band (≤ `largestDrawingStampBytes`), never a second full frame.
    static func drawDrawingLayer(
        _ drawing: PhotoDrawing,
        opacity: Double,
        in context: CGContext,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        guard drawing.hasVisibleEffect, pixelWidth > 0, pixelHeight > 0,
              drawing.canvasWidth > 0, drawing.canvasHeight > 0,
              let pkDrawing = try? PKDrawing(data: drawing.data)
        else { return }
        let canvas = CGRect(x: 0, y: 0, width: drawing.canvasWidth, height: drawing.canvasHeight)
        let bounds = pkDrawing.bounds.intersection(canvas).integral
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return }
        let scale = CGFloat(pixelWidth) / CGFloat(drawing.canvasWidth)

        context.saveGState()
        defer { context.restoreGState() }
        context.setAlpha(CGFloat(min(max(opacity, 0), 1)))

        let bands = drawingBands(bounds: bounds, scale: scale)
        if bands.count <= 1 {
            guard let stamp = drawingStamp(drawing, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
            else { return }
            context.draw(stamp.image, in: stamp.rect)
            return
        }
        for band in bands {
            autoreleasepool {
                guard let image = pkDrawing.image(from: band, scale: scale).cgImage else { return }
                // Canvas y runs down from the top; the overlay bitmap's runs up.
                context.draw(image, in: CGRect(
                    x: band.minX * scale,
                    y: CGFloat(pixelHeight) - band.maxY * scale,
                    width: band.width * scale,
                    height: band.height * scale
                ))
            }
        }
    }
}
