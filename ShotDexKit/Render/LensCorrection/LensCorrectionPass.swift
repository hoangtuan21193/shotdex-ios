import CoreImage
import Foundation

/// The lens profile's passes (FS-03.16a §5): distortion and chromatic
/// aberration in one sampling pass, vignetting as a gain in linear light.
public enum LensCorrectionPass {

    /// Distortion and CA at their strengths, plus the manual Distortion, in
    /// one pass. Strengths 0 with no manual term leave the picture as it is.
    public static func apply(
        distortion: LensDistortionTerm?,
        tca: LensTCATerm?,
        distortionStrength: Double,
        chromaticAberrationStrength: Double,
        lensCropFactor: Double,
        cameraCropFactor: Double,
        calibrationAspect: Double,
        manualDistortion: Double,
        to input: CIImage
    ) -> CIImage {
        guard let kernel = correctKernel else { return input }
        let extent = input.extent
        let norm = PhotoRenderService.lensNormalizationRadius(
            extent: extent,
            lensCropFactor: lensCropFactor,
            cameraCropFactor: cameraCropFactor,
            calibrationAspect: calibrationAspect
        )
        let halfDiagonal = (extent.width * extent.width + extent.height * extent.height).squareRoot() / 2
        let manual = PhotoRenderService.manualDistortionCoefficient(manualDistortion)
        let maximumRadius = halfDiagonal / norm * 1.05
        let table = LensCorrectionTable.make(
            distortion: distortion,
            tca: tca,
            distortionStrength: min(max(distortionStrength, 0), 2),
            chromaticAberrationStrength: min(max(chromaticAberrationStrength, 0), 2),
            manual: manual,
            manualRadiusRatio: norm / halfDiagonal,
            maximumRadius: maximumRadius
        )
        guard !table.isIdentity else { return input }
        let zoom = fillZoom(table, extent: extent, norm: norm)
        let center = CGPoint(x: extent.midX, y: extent.midY)
        // The largest shift any channel makes, for the region of interest.
        let reach = zip(zip(table.red, table.green), table.blue).map { max(abs($0.0 - 1), abs($0.1 - 1), abs($1 - 1)) }.max() ?? 0
        let pad = CGFloat(Double(reach) * halfDiagonal) + 8
        let output = kernel.apply(
            extent: extent,
            roiCallback: { index, rect in
                index == 0 ? rect.insetBy(dx: -pad, dy: -pad).intersection(extent.insetBy(dx: -pad, dy: -pad))
                    : CGRect(x: 0, y: 0, width: LensCorrectionTable.sampleCount, height: 1)
            },
            arguments: [
                input.clampedToExtent(),
                table.image,
                CIVector(x: center.x, y: center.y),
                Float(norm),
                Float(zoom),
                Float(table.maximumRadius),
                Float(LensCorrectionTable.sampleCount),
            ]
        )
        return output?.cropped(to: extent) ?? input
    }

    /// The smallest zoom ≥ 1 at which the corners and edge midpoints sample
    /// inside the photo in every channel, iterated because the table is read
    /// at radius / zoom; the 1.5× ceiling of FS-03.11 §7.
    static func fillZoom(_ table: LensCorrectionTable, extent: CGRect, norm: Double) -> Double {
        let halfW = extent.width / 2, halfH = extent.height / 2
        let radii = [(halfW * halfW + halfH * halfH).squareRoot(), halfW, halfH]
        var zoom = 1.0
        for _ in 0..<6 {
            zoom = max(1, radii.map { radius in
                let s = table.scales(at: radius / (norm * zoom))
                return max(s.red, s.green, s.blue)
            }.max() ?? 1)
        }
        return min(zoom, 1.5)
    }

    /// Lensfun pa vignetting out, gain^strength; r = 1 at the corner of the
    /// calibration frame (Lensfun's own convention for pa).
    public static func applyVignetting(
        _ term: LensVignettingTerm,
        strength: Double,
        lensCropFactor: Double,
        cameraCropFactor: Double,
        calibrationAspect: Double,
        to input: CIImage
    ) -> CIImage {
        let strength = min(max(strength, 0), 2)
        guard strength > 0.0001, let kernel = vignetteKernel else { return input }
        let extent = input.extent
        let shortHalf = PhotoRenderService.lensNormalizationRadius(
            extent: extent,
            lensCropFactor: lensCropFactor,
            cameraCropFactor: cameraCropFactor,
            calibrationAspect: calibrationAspect
        )
        let norm = shortHalf * (1 + calibrationAspect * calibrationAspect).squareRoot()
        let output = kernel.apply(
            extent: extent,
            arguments: [
                input,
                CIVector(x: extent.midX, y: extent.midY),
                Float(norm),
                CIVector(x: term.k1, y: term.k2, z: term.k3),
                Float(strength),
            ]
        )
        return output ?? input
    }

    // MARK: Any source

    /// The maker's data and Lensfun per aspect, both brought to pixels:
    /// distortion and CA in the one sampling pass. `center` is the optical
    /// centre in the frame's coordinates.
    public static func apply(
        table: LensCorrectionTable,
        center: CGPoint,
        to input: CIImage
    ) -> CIImage {
        guard !table.isIdentity, let kernel = correctKernel else { return input }
        let extent = input.extent
        let zoom = fillZoom(table, extent: extent, norm: 1)
        let halfDiagonal = (extent.width * extent.width + extent.height * extent.height).squareRoot() / 2
        let reach = zip(zip(table.red, table.green), table.blue).map { max(abs($0.0 - 1), abs($0.1 - 1), abs($1 - 1)) }.max() ?? 0
        let pad = CGFloat(Double(reach) * halfDiagonal) + 8
        let output = kernel.apply(
            extent: extent,
            roiCallback: { index, rect in
                index == 0 ? rect.insetBy(dx: -pad, dy: -pad).intersection(extent.insetBy(dx: -pad, dy: -pad))
                    : CGRect(x: 0, y: 0, width: LensCorrectionTable.sampleCount, height: 1)
            },
            arguments: [
                input.clampedToExtent(), table.image, CIVector(x: center.x, y: center.y),
                Float(1), Float(zoom), Float(table.maximumRadius), Float(LensCorrectionTable.sampleCount),
            ]
        )
        return output?.cropped(to: extent) ?? input
    }

    /// A gain curve over pixel radius, raised to `strength`.
    public static func applyVignetting(
        curve gain: (Double) -> Double,
        strength: Double,
        center: CGPoint,
        maximumRadius: Double,
        to input: CIImage
    ) -> CIImage {
        let strength = min(max(strength, 0), 2)
        guard strength > 0.0001, let kernel = vignetteCurveKernel else { return input }
        var pixels = [Float](repeating: 1, count: LensCorrectionTable.sampleCount * 4)
        for index in 0..<LensCorrectionTable.sampleCount {
            pixels[index * 4] = Float(gain(maximumRadius * Double(index) / Double(LensCorrectionTable.sampleCount - 1)))
        }
        let table = CIImage(
            bitmapData: pixels.withUnsafeBufferPointer { Data(buffer: $0) },
            bytesPerRow: LensCorrectionTable.sampleCount * 16,
            size: CGSize(width: LensCorrectionTable.sampleCount, height: 1),
            format: .RGBAf, colorSpace: nil
        )
        let extent = input.extent
        return kernel.apply(
            extent: extent,
            roiCallback: { index, rect in index == 0 ? rect : CGRect(x: 0, y: 0, width: LensCorrectionTable.sampleCount, height: 1) },
            arguments: [input, table, CIVector(x: center.x, y: center.y), Float(maximumRadius),
                        Float(LensCorrectionTable.sampleCount), Float(strength)]
        )?.cropped(to: extent) ?? input
    }

    static let vignetteCurveKernel = CoreImageKernelLibrary.kit.kernel(named: "lensVignetteCurve")

    static let correctKernel = CoreImageKernelLibrary.kit.kernel(named: "lensCorrect")
    static let vignetteKernel = CoreImageKernelLibrary.kit.colorKernel(named: "lensVignette")
}

/// Lensfun pa vignetting as a filter, for the slot `CIRAWFilter` runs in
/// linear light before its tone curve (`linearSpaceFilter`).
public final class LensVignetteFilter: CIFilter {
    @objc public var inputImage: CIImage?
    public var term = LensVignettingTerm(focal: 0, aperture: 0, distance: 0, k1: 0, k2: 0, k3: 0)
    public var strength = 1.0
    public var lensCropFactor = 1.0
    public var cameraCropFactor = 1.0
    public var calibrationAspect = 1.5

    public override var outputImage: CIImage? {
        guard let inputImage else { return nil }
        return LensCorrectionPass.applyVignetting(
            term,
            strength: strength,
            lensCropFactor: lensCropFactor,
            cameraCropFactor: cameraCropFactor,
            calibrationAspect: calibrationAspect,
            to: inputImage
        )
    }
}

/// The maker's vignetting curve for the RAW decoder's linear slot.
public final class LensVignetteCurveFilter: CIFilter {
    @objc public var inputImage: CIImage?
    public var correction: EmbeddedLensCorrection?
    public var strength = 1.0

    public override var outputImage: CIImage? {
        guard let inputImage else { return nil }
        guard let correction, let curve = correction.vignetting else { return inputImage }
        let extent = inputImage.extent
        let frame = LensFrame(correction: correction, extent: extent)
        return LensCorrectionPass.applyVignetting(
            curve: { curve.value(at: $0 / frame.unit) },
            strength: strength, center: frame.center, maximumRadius: frame.maximumRadius, to: inputImage
        )
    }
}

/// Where an embedded correction's radius 1 lands on a frame, in pixels.
public struct LensFrame: Sendable {
    public var center: CGPoint
    public var unit: Double
    public var maximumRadius: Double

    public init(correction: EmbeddedLensCorrection, extent: CGRect) {
        let c = CGPoint(
            x: extent.minX + correction.center.x * extent.width,
            y: extent.minY + (1 - correction.center.y) * extent.height
        )
        center = c
        let corners = [CGPoint(x: extent.minX, y: extent.minY), CGPoint(x: extent.maxX, y: extent.minY),
                       CGPoint(x: extent.minX, y: extent.maxY), CGPoint(x: extent.maxX, y: extent.maxY)]
        let farthest = corners.map { hypot($0.x - c.x, $0.y - c.y) }.max() ?? 1
        switch correction.unit {
        case .halfDiagonal: unit = (extent.width * extent.width + extent.height * extent.height).squareRoot() / 2
        case .halfLongSide: unit = max(extent.width, extent.height) / 2
        case .farthestCorner: unit = farthest
        }
        maximumRadius = farthest * 1.05
    }
}
