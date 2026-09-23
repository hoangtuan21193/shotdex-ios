import CoreGraphics
import CoreImage
import Foundation

/// One brush stroke of a focus-stack retouch: where it was painted, and the
/// frame whose pixels it puts back (FS-01.10 §5).
///
/// The frame is named by its index among the **input** frames, not among the
/// ones that lined up, and the points are normalized to the picture. Both are
/// independent of resolution, so the strokes painted on the preview are
/// replayed exactly on the full-resolution save.
public struct FocusStackRetouchStroke: Sendable, Equatable {
    public var frame: Int
    public var brush: BrushStroke

    public init(frame: Int, brush: BrushStroke) {
        self.frame = frame
        self.brush = brush
    }
}

extension PhotoStackRenderer {
    /// Long edge a retouch mask is drawn at. A brush edge is soft, so a mask
    /// scaled up from here is indistinguishable from one drawn at 48 MP — and
    /// a full-size 8-bit mask per run of strokes is what would not fit.
    public static let retouchMaskEdge: CGFloat = 2048

    /// `stacked` with every stroke's area taken from that stroke's frame, in
    /// the order painted — a later stroke over an earlier one wins.
    ///
    /// Consecutive strokes on the same frame share one mask: a retouch is a
    /// few strokes from one frame, then a few from another, so the masks held
    /// are as many as the frame changes, not the strokes.
    public func retouched(
        _ stacked: CIImage,
        prepared: PreparedFocusStack,
        strokes: [FocusStackRetouchStroke]
    ) -> CIImage {
        let extent = stacked.extent
        var result = stacked
        for run in Self.runs(strokes) {
            guard let position = prepared.inputIndices.firstIndex(of: run.frame),
                  let mask = Self.retouchMask(run.brushes, extent: extent)
            else { continue }
            let blend = CIFilter(name: "CIBlendWithMask", parameters: [
                kCIInputImageKey: prepared.frames[position],
                kCIInputBackgroundImageKey: result,
                kCIInputMaskImageKey: mask,
            ])
            result = blend?.outputImage?.cropped(to: extent) ?? result
        }
        return result
    }

    /// The input index of the frame sharpest around `point` — the one a
    /// retouch stroke starting there should paint from, as Helicon's
    /// auto-pick does (FS-01.10 §5, AC-10).
    public func sharpestFrame(
        in prepared: PreparedFocusStack,
        at point: NormalizedPoint,
        radius: Int = FocusStackOptions.standard.radius
    ) -> Int {
        guard let first = prepared.frames.first else { return 0 }
        let extent = first.extent
        let centre = PhotoRenderService.imagePoint(point, extent: extent)
        // A patch a few percent of the frame wide: a single pixel's score is
        // noise, and the patch is about the size of a fingertip on the stage.
        let side = max(8, min(extent.width, extent.height) * 0.03)
        let patch = CGRect(x: centre.x - side / 2, y: centre.y - side / 2, width: side, height: side)
            .intersection(extent)
        guard !patch.isNull, !patch.isEmpty else { return prepared.inputIndices.first ?? 0 }

        var best = 0
        var bestScore = -Float.infinity
        for (position, frame) in prepared.frames.enumerated() {
            let sharpness = Self.sharpnessMap(of: frame, radius: radius)
            let score = averageRed(of: sharpness, in: patch)
            if score > bestScore {
                bestScore = score
                best = position
            }
        }
        return prepared.inputIndices[best]
    }

    private func averageRed(of image: CIImage, in rect: CGRect) -> Float {
        let average = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: rect)])
        var pixel = [Float](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            renderingContext.render(
                average,
                toBitmap: buffer.baseAddress!,
                rowBytes: 16,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBAf,
                colorSpace: nil
            )
        }
        return pixel[0]
    }

    struct Run: Equatable {
        var frame: Int
        var brushes: [BrushStroke]
    }

    /// Strokes grouped into runs of the same frame, order kept.
    static func runs(_ strokes: [FocusStackRetouchStroke]) -> [Run] {
        var runs: [Run] = []
        for stroke in strokes {
            if runs.last?.frame == stroke.frame {
                runs[runs.count - 1].brushes.append(stroke.brush)
            } else {
                runs.append(Run(frame: stroke.frame, brushes: [stroke.brush]))
            }
        }
        return runs
    }

    /// The strokes as a grey mask over `extent`, white where painted, drawn
    /// by the editor's own brush rasterizer so the soft edge is the one the
    /// masking brush has.
    static func retouchMask(_ strokes: [BrushStroke], extent: CGRect) -> CIImage? {
        let scale = min(1, retouchMaskEdge / max(extent.width, extent.height))
        let width = max(1, Int((extent.width * scale).rounded(.up)))
        let height = max(1, Int((extent.height * scale).rounded(.up)))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let maskExtent = CGRect(x: 0, y: 0, width: width, height: height)
        BrushStrokeRasterizer.draw(strokes, in: context, shortEdge: CGFloat(min(width, height))) { point in
            PhotoRenderService.imagePoint(point, extent: maskExtent)
        }
        guard let image = context.makeImage() else { return nil }
        let mask = CIImage(cgImage: image)
        guard scale < 1 else {
            return mask.transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        }
        return mask
            .transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(width), y: extent.height / CGFloat(height)))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .clampedToExtent()
            .cropped(to: extent)
    }
}
