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
