import CoreImage
import Foundation

/// The sensor noise a deghost test measures disagreement against
/// (FS-01.11 §5), in electrons at the clip point.
public struct HDRNoiseModel: Sendable, Equatable {
    /// Electrons that fill a pixel to the clip point.
    public var fullWell: Double
    /// Read noise, electrons RMS.
    public var readNoise: Double
    /// Bits per sample of the data the frames came from.
    public var bitDepth: Int

    public init(fullWell: Double, readNoise: Double, bitDepth: Int) {
        self.fullWell = fullWell
        self.readNoise = readNoise
        self.bitDepth = bitDepth
    }

    /// A RAW frame. The spike's model (FS-01.11 spike §1); real sensors
    /// differ, and the deghost thresholds are tuned against this one.
    public static let raw = HDRNoiseModel(fullWell: 30_000, readNoise: 3, bitDepth: 14)
    /// A processed JPEG or HEIC, sRGB undone: noise reduction lowers the
    /// shot noise, and the eight bits dominate in the shadows.
    public static let processed = HDRNoiseModel(fullWell: 3_000, readNoise: 3, bitDepth: 8)

    /// Shot gain, read variance and quantisation variance in frame units,
    /// for frames resampled to `pixelScale` of the sensor's pixels: shrinking
    /// averages pixels, and their noise with them.
    func vector(pixelScale: Double) -> CIVector {
        let s = min(1, max(pixelScale, 0.01))
        let step = 1 / (pow(2, Double(bitDepth)) - 1)
        return CIVector(
            x: s * s / fullWell,
            y: s * s * pow(readNoise / fullWell, 2),
            z: s * s * step * step / 12
        )
    }
}

/// A bracketed series ready to merge: linear frames lined up, darkest first.
public struct HDRSeries: @unchecked Sendable {
    /// Linear, scene-referred frames, each clipping at 1, in one geometry.
    public var frames: [CIImage]
    /// Each frame's exposure in stops relative to the reference.
    public var stops: [Double]
    /// Index into `frames` of the reference exposure.
    public var reference: Int
    public var noise: HDRNoiseModel
    /// Frame pixels per sensor pixel — below 1 for a preview.
    public var pixelScale: Double

    public init(frames: [CIImage], stops: [Double], reference: Int, noise: HDRNoiseModel, pixelScale: Double) {
        self.frames = frames
        self.stops = stops
        self.reference = reference
        self.noise = noise
        self.pixelScale = pixelScale
    }
}

/// Merges a bracketed series into one radiance image (FS-01.11 §5).
public enum HDRMerge {
    /// Radiance relative to the reference exposure: 1 is where the reference
    /// clips, and the darkest frame carries the picture up to 2^-stops above.
    public static func radiance(_ series: HDRSeries) -> CIImage? {
        guard series.frames.count >= 2, series.frames.count == series.stops.count,
              series.frames.indices.contains(series.reference),
              let accumulateKernel, let resolveKernel
        else { return nil }
        let extent = series.frames[0].extent
        guard let anchor = anchor(series, extent: extent) else { return nil }
        let keep = CIImage(color: .white).cropped(to: extent)
        var sums = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
        for (frame, stops) in zip(series.frames, series.stops) {
            guard let next = accumulateKernel.apply(
                extent: extent, arguments: [sums, frame, keep, Float(pow(2, stops))]
            ) else { return nil }
            sums = next
        }
        return resolveKernel.apply(extent: extent, arguments: [sums, anchor])
    }

    /// Per pixel, the frame nearest the reference from below that is still
    /// readable there, as radiance with its noise σ in alpha. The darkest
    /// frame is the floor: where it clips too, nothing reads better.
    static func anchor(_ series: HDRSeries, extent: CGRect) -> CIImage? {
        guard let anchorKernel else { return nil }
        let noise = series.noise.vector(pixelScale: series.pixelScale)
        var anchor = CIImage(color: .black).cropped(to: extent)
        for index in 0...series.reference {
            guard let next = anchorKernel.apply(
                extent: extent,
                arguments: [anchor, series.frames[index], Float(pow(2, series.stops[index])), noise,
                            Float(index == 0 ? 1 : 0)]
            ) else { return nil }
            anchor = next
        }
        return anchor
    }

    static let accumulateKernel = CoreImageKernelLibrary.kit.colorKernel(named: "hdrAccumulate")
    static let resolveKernel = CoreImageKernelLibrary.kit.colorKernel(named: "hdrResolve")
    static let anchorKernel = CoreImageKernelLibrary.kit.colorKernel(named: "hdrAnchor")
    static let rejectKernel = CoreImageKernelLibrary.kit.colorKernel(named: "hdrReject")
}
