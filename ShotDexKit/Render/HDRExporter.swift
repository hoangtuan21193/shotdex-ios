import CoreGraphics
import CoreImage
import Foundation
import UniformTypeIdentifiers

/// Saves an HDR merge at full resolution without holding the picture
/// (FS-01.11 §6).
///
/// Two passes. The radiance is rendered strip by strip into one half-float
/// buffer, every frame's decoder alive and read band by band — the merge and
/// the deghost only look a few pixels past the strip. The decoders then go,
/// and the tone map runs over the buffer as one Core Image picture, streamed
/// to the encoder: its coarsest band reaches a sixteenth of the picture, too
/// far to compute strip by strip from the raw files.
public enum HDRExporter {
    /// JPEG and HEIC quality, as Focus Stack (FS-01.11 §6).
    public static let quality = 0.95

    /// Rows of radiance rendered per call.
    static let stripHeight = 256

    /// Writes the merge to `url`.
    ///
    /// `frame` hands back input frame `index` at full resolution, linear,
    /// decoded lazily; `inputIndices`, `maps`, `stops` and `reference` are
    /// the prepared preview's (`PreparedHDR`), its maps scaled by
    /// `previewScale` (preview pixels per full pixel). Progress runs 0…1 over
    /// both passes.
    public static func write(
        frame: (Int) -> CIImage?,
        prepared: PreparedHDR,
        previewScale: Double,
        options: HDROptions,
        type: UTType,
        to url: URL,
        properties: [CFString: Any],
        context: CIContext = CIContext(options: [.workingFormat: CIFormat.RGBAh, .cacheIntermediates: false]),
        progress: (@Sendable (Double) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) throws {
        let radiance = try autoreleasepool { () throws -> StackBuffer in
            try renderRadiance(frame: frame, prepared: prepared, previewScale: previewScale, deghost: options.deghost,
                               context: context, progress: { progress?($0 * 0.5) }, isCancelled: isCancelled)
        }
        if isCancelled?() == true { throw StripImageWriter.Failure.cancelled }
        // Each strip of the tone map gets only the radiance rows its widest
        // band reaches: handed the whole buffer, Core Image uploads all
        // 192 MB of it for every strip.
        let size = CGSize(width: radiance.width, height: radiance.height)
        let margin = HDRMerge.toneMapMargin(pictureSize: size)
        let stops = prepared.series.stops
        try StripImageWriter.write(
            rect: CGRect(origin: .zero, size: size), to: url, type: type, quality: quality, properties: properties,
            context: context, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, stripHeight: toneStripHeight,
            progress: { progress?(0.5 + $0 * 0.5) }, isCancelled: isCancelled
        ) { strip in
            HDRMerge.toneMapped(radiance.image(near: strip, margin: margin), stops: stops,
                                strength: options.strength, pictureSize: size)
        }
    }

    /// Rows of the tone map rendered per strip: every strip reads `margin`
    /// rows either side, so taller strips waste less of that reading.
    static let toneStripHeight = 512

    /// The merged radiance at full resolution, in a buffer of the frames'
    /// working space.
    static func renderRadiance(
        frame: (Int) -> CIImage?,
        prepared: PreparedHDR,
        previewScale: Double,
        deghost: HDRDeghost,
        context: CIContext,
        progress: (Double) -> Void,
        isCancelled: (() -> Bool)?
    ) throws -> StackBuffer {
        let referenceInput = prepared.inputIndices[prepared.series.reference]
        guard let reference = frame(referenceInput) else { throw StripImageWriter.Failure.cannotEncode }
        let extent = reference.extent
        // Preview maps to full size: shrink to the preview, move, grow back.
        let k = CGFloat(previewScale)
        let shrink = CGAffineTransform(scaleX: k, y: k)
        var frames: [CIImage] = []
        for (position, input) in prepared.inputIndices.enumerated() {
            guard let image = input == referenceInput ? reference : frame(input)
            else { throw StripImageWriter.Failure.cannotEncode }
            let fitted = PhotoStackRenderer.fitted(image, to: extent)
            let map = shrink.concatenating(prepared.maps[position]).concatenating(shrink.inverted())
            frames.append(prepared.maps[position] == .identity ? fitted
                          : fitted.transformed(by: map).clampedToExtent().cropped(to: extent))
        }
        let series = HDRSeries(frames: frames, stops: prepared.series.stops, reference: prepared.series.reference,
                               noise: prepared.series.noise, pixelScale: 1)
        guard let merged = HDRMerge.radiance(series, deghost: deghost) else { throw StripImageWriter.Failure.cannotEncode }

        let buffer = StackBuffer(width: Int(extent.width), height: Int(extent.height), bytesPerPixel: 8,
                                 format: .RGBAh, colorSpace: nil)
        var top = 0
        let height = buffer.height
        var cancelled = false
        let placed = merged.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        buffer.render(context: context) { bounds in
            if cancelled || isCancelled?() == true { cancelled = true; return nil }
            top += Int(bounds.height)
            progress(Double(top) / Double(height))
            return placed
        }
        if cancelled { throw StripImageWriter.Failure.cancelled }
        return buffer
    }
}
