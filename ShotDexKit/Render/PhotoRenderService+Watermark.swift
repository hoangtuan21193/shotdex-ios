import CoreGraphics
import CoreImage
import Foundation
import PencilKit

/// A watermark stamped on export (FS-05.04): the preset's layers as one block,
/// composited **last**, at the export size, after every edit and every layer
/// the photo already carries.
///
/// Only the block's box is rasterized — never a bitmap the size of the photo
/// (~195 MB at 48MP, FS-05.01 AC-38) — and through the same drawing functions
/// the editor bakes with, so a stamp and a layer pasted in the editor are the
/// same pixels.
public extension PhotoRenderService {
    /// Where `stamp` lands on a photo of `imageSize` pixels. Its layers must be
    /// resolved already: tokens are per photo, the renderer has no opinion.
    static func watermarkFrame(_ stamp: WatermarkStamp, imageSize: CGSize) -> WatermarkFrame? {
        guard stamp.hasVisibleLayers else { return nil }
        return WatermarkLayout.place(
            sourceAspect: stamp.sourceAspect,
            placement: stamp.placement,
            imageSize: imageSize
        ) { frame in
            watermarkBlockBounds(stamp.layers, frame: frame)
        }
    }

    /// The block's height as the preset was saved, a fraction of the short
    /// edge — Size's default.
    static func watermarkNaturalSize(_ stamp: WatermarkStamp) -> Double? {
        let frame = WatermarkLayout.frameSize(
            aspect: stamp.sourceAspect,
            shortEdge: WatermarkLayout.referenceShortEdge
        )
        guard let bounds = watermarkBlockBounds(stamp.layers, frame: frame) else { return nil }
        return WatermarkLayout.naturalSize(blockBounds: bounds, frameSize: frame)
    }

    /// The block alone, on transparent pixels, and the rect it covers on the
    /// photo (top-down pixels). The rect is the box, grown only by what a
    /// shadow or outline paints past it, and clipped to the photo.
    static func watermarkRaster(
        _ stamp: WatermarkStamp,
        imageSize: CGSize
    ) -> (image: CGImage, rect: CGRect)? {
        guard let frame = watermarkFrame(stamp, imageSize: imageSize) else { return nil }
        let ink = watermarkInkPadding(stamp.layers, frame: frame.frameSize)
        let rect = frame.box.insetBy(dx: -ink, dy: -ink).integral
            .intersection(CGRect(origin: .zero, size: imageSize))
        let width = Int(rect.width)
        let height = Int(rect.height)
        guard !rect.isNull, width > 0, height > 0,
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
        // The layers draw into the whole stand-in frame, bottom-up; moving the
        // context puts the part of that frame under `rect` into this bitmap
        // and leaves the rest of it clipped away, unallocated.
        context.translateBy(
            x: frame.frameOrigin.x - rect.minX,
            y: rect.maxY - frame.frameOrigin.y - frame.frameSize.height
        )
        drawOverlayLayers(stamp.layers, in: context, frame: frame.frameSize)
        applyOpacity(stamp.placement.opacity, to: context)
        guard let image = context.makeImage() else { return nil }
        return (image, rect)
    }

    /// `image` with the stamp composited over it — the preview's way. A file
    /// gets the same composite through `write`, inside the box only.
    static func applyWatermark(_ stamp: WatermarkStamp, to image: CIImage) -> CIImage {
        guard let layer = watermarkLayer(stamp, extent: image.extent) else { return image }
        return layer.image.composited(over: image).cropped(to: image.extent)
    }

    /// The result's image with its pending watermark, if any, composited.
    static func watermarked(_ result: PhotoRenderResult) -> CIImage {
        guard let stamp = result.watermark else { return result.image }
        return applyWatermark(stamp, to: result.image)
    }

    /// The block as a Core Image layer on `extent`, with the rect it covers
    /// (top-down pixels from the extent's top-left).
    private static func watermarkLayer(_ stamp: WatermarkStamp, extent: CGRect) -> (image: CIImage, rect: CGRect)? {
        guard !extent.isInfinite, !extent.isEmpty,
              let raster = watermarkRaster(stamp, imageSize: extent.size)
        else { return nil }
        // Top-down pixels to Core Image's bottom-up space on this extent.
        let layer = CIImage(cgImage: raster.image).transformed(by: CGAffineTransform(
            translationX: extent.minX + raster.rect.minX,
            y: extent.minY + extent.height - raster.rect.maxY
        ))
        return (layer, raster.rect)
    }

    /// The export's last step: the stamp, at the size the file is written at.
    /// It rides on the result and is composited when the pixels are made —
    /// `write` and `previewImage` — so nothing outside its box is re-rendered.
    /// Nil or an empty stamp returns the result as it is.
    func applyingWatermark(_ stamp: WatermarkStamp?, to result: PhotoRenderResult) -> PhotoRenderResult {
        guard let stamp, stamp.hasVisibleLayers else { return result }
        var stamped = result
        stamped.watermark = stamp
        return stamped
    }

    /// The pixels `write` encodes: the render as it is, or — with a stamp
    /// pending — `stampedImage`.
    func encodablePixels(_ result: PhotoRenderResult) throws -> CGImage {
        if let watermark = result.watermark {
            return try stampedImage(result, watermark: watermark)
        }
        guard let plain = context.createCGImage(
            result.image,
            from: result.image.extent,
            format: .RGBA8,
            colorSpace: result.colorSpace
        ) else {
            throw PhotoEditingError.cannotRender
        }
        return plain
    }

    /// The pixels `write` encodes when a stamp is pending: the photo rendered
    /// exactly as an unstamped export renders it, then the stamped composite
    /// rendered over the block's rect alone, straight into the same buffer.
    /// Composited in one Core Image graph, the whole frame re-renders and
    /// thousands of pixels far from the stamp shift by a level; this way the
    /// photo outside the box is the unstamped render to the bit (FS-05.04
    /// AC-1), and no second full-size bitmap is ever made (§6).
    func stampedImage(_ result: PhotoRenderResult, watermark: WatermarkStamp) throws -> CGImage {
        let extent = result.image.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        let rowBytes = width * 4
        guard width > 0, height > 0,
              let buffer = calloc(height, rowBytes)
        else { throw PhotoEditingError.cannotRender }
        let image = result.image
        context.render(
            image, toBitmap: buffer, rowBytes: rowBytes, bounds: extent,
            format: .RGBA8, colorSpace: result.colorSpace
        )
        if let layer = Self.watermarkLayer(watermark, extent: extent) {
            let rect = layer.rect
            let bounds = CGRect(
                x: extent.minX + rect.minX,
                y: extent.minY + extent.height - rect.maxY,
                width: rect.width,
                height: rect.height
            )
            context.render(
                layer.image.composited(over: image),
                toBitmap: buffer.advanced(by: Int(rect.minY) * rowBytes + Int(rect.minX) * 4),
                rowBytes: rowBytes,
                bounds: bounds,
                format: .RGBA8,
                colorSpace: result.colorSpace
            )
        }
        guard let provider = CGDataProvider(
            dataInfo: nil, data: buffer, size: rowBytes * height,
            releaseData: { _, data, _ in free(UnsafeMutableRawPointer(mutating: data)) }
        ), let output = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: rowBytes, space: result.colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        ) else {
            free(buffer)
            throw PhotoEditingError.cannotRender
        }
        return output
    }

    /// Opacity multiplies the finished block, not each layer, so where a logo
    /// overlaps its credit line the overlap is no darker than the rest. The
    /// bitmap is premultiplied, so every channel scales alike.
    private static func applyOpacity(_ opacity: Double, to context: CGContext) {
        guard opacity < 0.999, let data = context.data else { return }
        let factor = UInt32((min(max(opacity, 0), 1) * 256).rounded())
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        let count = context.bytesPerRow * context.height
        for index in 0..<count {
            bytes[index] = UInt8((UInt32(bytes[index]) * factor) >> 8)
        }
    }

    // MARK: Measuring

    /// The union of the layers' boxes in a frame of `frame` pixels, top-down —
    /// what `WatermarkLayout` scales and anchors. A layer that draws nothing
    /// (empty text, a logo whose file is gone) takes no room.
    internal static func watermarkBlockBounds(_ layers: [PhotoOverlay], frame: CGSize) -> CGRect? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        let extent = CGRect(origin: .zero, size: frame)
        let shortEdge = min(frame.width, frame.height)
        var union: CGRect?
        for layer in layers where layer.hasVisibleEffect {
            let center = CGPoint(x: frame.width * layer.center.x, y: frame.height * layer.center.y)
            let box: CGRect?
            switch layer.kind {
            case .text:
                let size = TextOverlayLayout.textContentSize(
                    for: layer, resolvedText: layer.text, extent: extent, shortEdge: shortEdge
                )
                box = rotatedBox(center: center, size: size, degrees: layer.rotationDegrees)
            case .image:
                guard let id = layer.imageID, let image = OverlayImageCache.shared.image(for: id) else {
                    box = nil
                    break
                }
                let size = TextOverlayLayout.imageContentSize(for: layer, image: image, shortEdge: shortEdge)
                box = rotatedBox(center: center, size: size, degrees: layer.rotationDegrees)
            case .shape:
                let size = ShapeOverlayLayout.contentSize(for: layer, shortEdge: shortEdge)
                let stroke = layer.isFilled && layer.shapeStyle.supportsFill
                    ? 0
                    : ShapeOverlayGeometry.strokeWidth(layer.strokeWidth, shortEdge: shortEdge)
                box = rotatedBox(center: center, size: size, degrees: layer.rotationDegrees)?
                    .insetBy(dx: -stroke / 2, dy: -stroke / 2)
            case .drawing:
                box = layer.drawing.flatMap { drawingBounds($0, frameWidth: frame.width) }
            case .magnifier:
                box = nil
            }
            guard let box, box.width > 0, box.height > 0 else { continue }
            union = union.map { $0.union(box) } ?? box
        }
        return union
    }

    /// What a text layer's outline and shadow paint outside its box, at this
    /// frame size; zero for the plain caption, so its pixels stay inside the
    /// box the spec measures.
    private static func watermarkInkPadding(_ layers: [PhotoOverlay], frame: CGSize) -> CGFloat {
        let shortEdge = min(frame.width, frame.height)
        var padding: CGFloat = 0
        for layer in layers where layer.kind == .text && layer.hasVisibleEffect {
            let pointSize = TextOverlayLayout.pointSize(for: layer.size, shortEdge: shortEdge)
            var ink: CGFloat = 0
            if layer.hasOutline { ink += CGFloat(layer.outlineWidth) * pointSize }
            if layer.hasShadow {
                ink += (CGFloat(layer.shadowRadius) * 2 + abs(CGFloat(layer.shadowOffsetY))) * pointSize
            }
            padding = max(padding, ink)
        }
        return padding > 0 ? padding + 1 : 0
    }

    private static func rotatedBox(center: CGPoint, size: CGSize, degrees: Double) -> CGRect? {
        guard size.width > 0, size.height > 0 else { return nil }
        let box = CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        guard abs(degrees.truncatingRemainder(dividingBy: 360)) > 0.001 else { return box }
        // Top-down space: a positive angle reads clockwise on screen, as the
        // renderer draws it; the bounding box is the same either way round.
        let turn = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: CGFloat(degrees) * .pi / 180)
            .translatedBy(x: -center.x, y: -center.y)
        return box.applying(turn)
    }

    /// The strokes' box, top-down, in a frame `frameWidth` wide — the scale
    /// `drawDrawingLayer` draws them at.
    private static func drawingBounds(_ drawing: PhotoDrawing, frameWidth: CGFloat) -> CGRect? {
        guard drawing.hasVisibleEffect, drawing.canvasWidth > 0, drawing.canvasHeight > 0,
              let pkDrawing = try? PKDrawing(data: drawing.data)
        else { return nil }
        let canvas = CGRect(x: 0, y: 0, width: drawing.canvasWidth, height: drawing.canvasHeight)
        let bounds = pkDrawing.bounds.intersection(canvas).integral
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = CGFloat(Int(frameWidth.rounded())) / CGFloat(drawing.canvasWidth)
        return CGRect(
            x: bounds.minX * scale,
            y: bounds.minY * scale,
            width: bounds.width * scale,
            height: bounds.height * scale
        )
    }
}
