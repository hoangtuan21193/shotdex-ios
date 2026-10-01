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

/// How hard the merge looks for things that moved between frames
/// (FS-01.11 §3, §5).
public enum HDRDeghost: String, CaseIterable, Identifiable, Sendable {
    case off, low, medium, high

    public var id: String { rawValue }

    /// Disagreement with the anchor, in standard deviations of the noise,
    /// above which a frame is left out at a pixel. Spike §4: lower than 5
    /// starts dropping static pixels by the percent.
    var threshold: Double? {
        switch self {
        case .off: nil
        case .low: 12
        case .medium: 7
        case .high: 5
        }
    }

    /// How far a rejection grows, in pixels at 1536 on the long edge: the
    /// test misses the soft edge of whatever moved.
    var dilation: Double {
        switch self {
        case .off: 0
        case .low: 2
        case .medium: 4
        case .high: 8
        }
    }
}

/// The two controls of the HDR panel.
public struct HDROptions: Sendable, Equatable {
    public var deghost: HDRDeghost
    /// 0…1. 0 is one exposure at the reference's level.
    public var strength: Double

    public init(deghost: HDRDeghost, strength: Double) {
        self.deghost = deghost
        self.strength = min(1, max(0, strength))
    }

    /// Medium and 60 (FS-01.11 §3).
    public static let standard = HDROptions(deghost: .medium, strength: 0.6)
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
    ///
    /// With deghosting on, each frame is compared at every pixel with the
    /// anchor — the frame nearest the reference from below that is readable
    /// there — and left out where it disagrees beyond the noise. Comparing
    /// with the reference alone misses whatever moves where the reference
    /// is clipped (spike §4).
    public static func radiance(_ series: HDRSeries, deghost: HDRDeghost = .off) -> CIImage? {
        guard series.frames.count >= 2, series.frames.count == series.stops.count,
              series.frames.indices.contains(series.reference),
              let accumulateKernel, let resolveKernel
        else { return nil }
        let extent = series.frames[0].extent
        guard let anchor = anchor(series, extent: extent),
              let keeps = keepMasks(series, deghost: deghost, anchor: anchor, extent: extent)
        else { return nil }
        var sums = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
        for index in series.frames.indices {
            guard let next = accumulateKernel.apply(
                extent: extent,
                arguments: [sums, series.frames[index], keeps[index], Float(pow(2, series.stops[index]))]
            ) else { return nil }
            sums = next
        }
        return resolveKernel.apply(extent: extent, arguments: [sums, anchor])
    }

    /// Per frame, 1 where it takes part in the merge and 0 where deghosting
    /// left it out.
    static func keepMasks(_ series: HDRSeries, deghost: HDRDeghost, anchor: CIImage, extent: CGRect) -> [CIImage]? {
        let all = CIImage(color: .white).cropped(to: extent)
        guard let z = deghost.threshold else { return series.frames.map { _ in all } }
        guard let rejectKernel else { return nil }
        let noise = series.noise.vector(pixelScale: series.pixelScale)
        let radius = max(1, (deghost.dilation * max(extent.width, extent.height) / 1536).rounded())
        var keeps: [CIImage] = []
        for index in series.frames.indices {
            guard let reject = rejectKernel.apply(
                extent: extent,
                arguments: [series.frames[index], anchor, Float(pow(2, series.stops[index])), noise, Float(z)]
            ) else { return nil }
            let grown = reject.clampedToExtent()
                .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: radius])
                .cropped(to: extent)
            keeps.append(grown.applyingFilter("CIColorInvert"))
        }
        return keeps
    }

    // MARK: Tone map

    /// Bands of the fusion. Fixed in number and sized by the picture, so a
    /// preview and the full-size save are the same operation at two
    /// resolutions (spike §6: with a fixed pixel pyramid they differ by
    /// 18–23 dB).
    static let fusionBands = 9
    /// The coarsest band's σ as a fraction of the short side. A sixteenth,
    /// like the panorama blender: wider and the coarse bands pull bright
    /// exposures' white across into the highlights next to large mid-tones
    /// (an eighth left 0.9 % of a ±2 series at white, a sixteenth 0.4 %).
    static let coarsestFraction = 16.0

    /// How far past a strip the tone map reads: three of its widest σ.
    public static func toneMapMargin(pictureSize: CGSize) -> Int {
        Int((3 * Double(min(pictureSize.width, pictureSize.height)) / coarsestFraction).rounded(.up))
    }
    /// Stops below the darkest frame of the extra virtual exposure. Room for
    /// the fusion's overshoot next to a highlight the darkest frame only
    /// just held: with it, nothing of the ±2 test series is left at white at
    /// any Strength.
    static let headroom = 1.0

    /// The radiance as a displayable picture, linear, 0…1: exposure fusion
    /// of virtual exposures at `strength` × each frame's stops, plus the
    /// darkest frame's exposure less `headroom` at every strength — the
    /// highlights only it held come back however low Strength is (chosen
    /// 2026-10-01: at 60 without it, 3 % of a ±2 test series stayed white).
    /// Strength 0 is the reference with its highlights recovered; 1 is the
    /// series as shot. What every frame clipped stays white.
    ///
    /// The extra exposure is not confined to the highlights: fusion blends
    /// it in wherever it is well exposed, which darkens the reference ~⅓
    /// stop at Strength 0 (median, ±2 test series). Confining it to where
    /// the next exposure nears clipping halves that but leaves 0.2 % of the
    /// picture white at 100 — measured 2026-10-01, chose the white-free one.
    ///
    /// `pictureSize` is the whole picture's when `radiance` is only the part
    /// of it a strip needs: the bands are sized by the picture, not the part.
    public static func toneMapped(_ radiance: CIImage, stops: [Double], strength: Double,
                                  pictureSize: CGSize? = nil) -> CIImage? {
        let extent = radiance.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let clamp = min(1, max(0, strength))
        var levels: [Double] = []
        for ev in stops.map({ $0 * clamp }).sorted() where levels.last.map({ ev - $0 > 0.05 }) ?? true {
            levels.append(ev)
        }
        if levels.isEmpty { levels = [0] }
        levels.insert(min(0, stops.min() ?? 0) - headroom, at: 0)
        guard let weightKernel = fusionWeightKernel,
              let differenceKernel = PanoramaCIBlender.differenceKernel,
              let bandKernel = PanoramaCIBlender.bandKernel,
              let bandWeightKernel = PanoramaCIBlender.bandWeightKernel,
              let resolveKernel = PanoramaCIBlender.resolveKernel,
              let sumKernel = PanoramaCIBlender.sumKernel,
              let blownKernel = blownToWhiteKernel
        else { return nil }

        // Display-encoded virtual exposures and how well exposed each is.
        let exposures = levels.map { ev in
            radiance.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: ev])
                .applyingFilter("CIColorClamp")
                .applyingFilter("CILinearToSRGBToneCurve")
        }
        let weights = exposures.compactMap { weightKernel.apply(extent: extent, arguments: [$0]) }
        guard weights.count == exposures.count else { return nil }

        // σ of each band, finest first: the coarsest an eighth of the short
        // side (a pyramid whose top is ~6 px), halving down from there.
        let size = pictureSize ?? extent.size
        let short = Double(min(size.width, size.height))
        let sigmas = (0..<fusionBands).map { short / coarsestFraction / pow(2, Double(fusionBands - 1 - $0)) }
        func blurred(_ image: CIImage, _ sigma: Double) -> CIImage {
            sigma < 0.3 ? image : image.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: extent)
        }
        let imagePyramids = exposures.map { image in sigmas.map { blurred(image, $0) } }
        let weightPyramids = weights.map { weight in sigmas.map { blurred(weight, $0) } }

        var total: CIImage?
        for band in 0...fusionBands {
            var bandTotal = CIImage(color: .black).cropped(to: extent)
            var weightTotal = bandTotal
            for index in exposures.indices {
                let detail: CIImage
                let mask: CIImage
                if band == fusionBands {
                    // What is left under the coarsest band.
                    detail = imagePyramids[index][fusionBands - 1]
                    mask = weightPyramids[index][fusionBands - 1]
                } else {
                    let finer = band == 0 ? exposures[index] : imagePyramids[index][band - 1]
                    guard let difference = differenceKernel.apply(
                        extent: extent, arguments: [finer, imagePyramids[index][band]]
                    ) else { return nil }
                    detail = difference
                    mask = weightPyramids[index][band]
                }
                guard let nextBand = bandKernel.apply(extent: extent, arguments: [bandTotal, detail, mask]),
                      let nextWeight = bandWeightKernel.apply(extent: extent, arguments: [weightTotal, mask])
                else { return nil }
                bandTotal = nextBand
                weightTotal = nextWeight
            }
            guard let resolved = resolveKernel.apply(extent: extent, arguments: [bandTotal, weightTotal])
            else { return nil }
            if let running = total {
                guard let sum = sumKernel.apply(extent: extent, arguments: [running, resolved]) else { return nil }
                total = sum
            } else {
                total = resolved
            }
        }
        guard let total, let white = blownKernel.apply(
            extent: extent, arguments: [total, radiance, Float(pow(2, -(stops.min() ?? 0)))]
        ) else { return nil }
        return white.applyingFilter("CIColorClamp").applyingFilter("CISRGBToneCurveToLinear")
    }

    static let fusionWeightKernel = CoreImageKernelLibrary.kit.colorKernel(named: "hdrFusionWeight")
    static let blownToWhiteKernel = CoreImageKernelLibrary.kit.colorKernel(named: "hdrBlownToWhite")

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
