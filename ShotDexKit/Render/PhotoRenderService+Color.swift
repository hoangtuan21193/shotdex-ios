import CoreImage
import Foundation

/// The Color tab's render stage: HSL mixer, point color, and color grading as
/// three `CIColorKernel`s. All decision math mirrors `ColorRenderMath` exactly
/// — the band centres reach the kernel as arguments, from the same constants
/// the unit tests cover.
public extension PhotoRenderService {
    // Kernels: `Kernels/ColorKernels.ci.metal`. Internal: this extension is
    // public, and its members would be too without saying so.
    internal static let hslMixerKernel = CoreImageKernelLibrary.kit.colorKernel(named: "hslMixer")
    internal static let pointColorKernel = CoreImageKernelLibrary.kit.colorKernel(named: "pointColor")
    internal static let colorGradeKernel = CoreImageKernelLibrary.kit.colorKernel(named: "colorGrade")

    /// The eight mixer bands' centres, in degrees, as the HSL kernel takes
    /// them — from `ColorMixerBand.centerDegrees`, the constants
    /// `ColorRenderMath.bandWeights` uses, so the GPU cannot drift from it.
    internal static let mixerBandCentres: (a: CIVector, b: CIVector) = {
        let centres = ColorMixerBand.allCases.map { CGFloat($0.centerDegrees) }
        return (
            CIVector(x: centres[0], y: centres[1], z: centres[2], w: centres[3]),
            CIVector(x: centres[4], y: centres[5], z: centres[6], w: centres[7])
        )
    }()

    // MARK: - Application

    private static func mixerVectors(
        _ mixer: ColorMixerAdjustments,
        property: ColorMixerProperty
    ) -> (a: CIVector, b: CIVector) {
        let values = ColorMixerBand.allCases.map { CGFloat(mixer[$0][property]) }
        return (
            CIVector(x: values[0], y: values[1], z: values[2], w: values[3]),
            CIVector(x: values[4], y: values[5], z: values[6], w: values[7])
        )
    }

    /// `kernel` is a parameter so a test can hand in `nil` — what a release
    /// build gets when the metallib does not load (FS-16 AC-7).
    internal static func applyMixer(
        _ mixer: ColorMixerAdjustments,
        to input: CIImage,
        kernel: CIColorKernel? = hslMixerKernel
    ) -> CIImage {
        guard !mixer.isIdentity, let kernel else { return input }
        let hue = mixerVectors(mixer, property: .hue)
        let sat = mixerVectors(mixer, property: .saturation)
        let lum = mixerVectors(mixer, property: .luminance)
        return kernel.apply(
            extent: input.extent,
            arguments: [
                input, hue.a, hue.b, sat.a, sat.b, lum.a, lum.b,
                mixerBandCentres.a, mixerBandCentres.b,
            ]
        ) ?? input
    }

    internal static func applyPointColors(
        _ points: [PointColorAdjustment],
        to input: CIImage,
        kernel: CIColorKernel? = pointColorKernel
    ) -> CIImage {
        let active = points.filter(\.hasVisibleEffect)
        guard !active.isEmpty, let kernel else { return input }
        var arguments: [Any] = [input]
        for index in 0..<PointColorAdjustment.maximumCount {
            if index < active.count {
                let point = active[index]
                arguments.append(CIVector(
                    x: CGFloat(point.referenceHue),
                    y: CGFloat(point.referenceSaturation),
                    z: CGFloat(point.referenceValue),
                    w: CGFloat(point.range)
                ))
                arguments.append(CIVector(
                    x: CGFloat(point.hueShift),
                    y: CGFloat(point.saturationShift),
                    z: CGFloat(point.luminanceShift),
                    w: 1
                ))
            } else {
                arguments.append(CIVector(x: 0, y: 0, z: 0, w: 0))
                arguments.append(CIVector(x: 0, y: 0, z: 0, w: 0))
            }
        }
        return kernel.apply(extent: input.extent, arguments: arguments) ?? input
    }

    private static func gradingVector(_ wheel: ColorGradingAdjustments.Wheel) -> CIVector {
        CIVector(
            x: CGFloat(wheel.hue / 360),
            y: CGFloat(wheel.saturation),
            z: CGFloat(wheel.luminance),
            w: 0
        )
    }

    internal static func applyGrading(
        _ grading: ColorGradingAdjustments,
        to input: CIImage,
        kernel: CIColorKernel? = colorGradeKernel
    ) -> CIImage {
        guard !grading.isIdentity, let kernel else { return input }
        return kernel.apply(
            extent: input.extent,
            arguments: [
                input,
                gradingVector(grading.shadows),
                gradingVector(grading.midtones),
                gradingVector(grading.highlights),
                gradingVector(grading.global),
                CIVector(x: CGFloat(grading.blending), y: CGFloat(grading.balance)),
            ]
        ) ?? input
    }

    /// Mixer → point colors → grading, matching Lightroom's stage order.
    /// Global-only by construction: only the whole-image call sites invoke it,
    /// never the per-mask adjustment pass.
    static func applyColor(_ color: PhotoColorRecipe, to input: CIImage) -> CIImage {
        guard !color.isIdentity else { return input }
        var image = applyMixer(color.mixer, to: input)
        image = applyPointColors(color.points, to: image)
        image = applyGrading(color.grading, to: image)
        return image.cropped(to: input.extent)
    }
}
