import CoreImage
import Foundation
import ShotDexKit

/// Power windows and qualifiers for the video compositor.
///
/// The photo pipeline's own mask stage lives on `PhotoRenderService`, which is
/// actor-isolated and keeps caches keyed to one still image. A video
/// compositor runs on AVFoundation's own queue, thirty times a second, over a
/// frame that is different every time — so it gets this instead: the same
/// component model (`PhotoMask` / `PhotoMaskComponent`, so a mask means the
/// same thing in both editors), rebuilt as pure Core Image with no shared
/// state to isolate.
///
/// **Four kinds, not seven.** Radial and linear windows, a luminance range
/// and a colour range — the four a colourist reaches for, and the four that
/// are cheap enough to evaluate per frame. Brush, subject and sky are absent
/// on purpose: brush strokes are authored against one still's geometry, and
/// subject and sky need a segmentation pass per frame that a 30fps render has
/// no budget for. A window that silently did nothing would be worse than one
/// that is not offered.
enum VideoMaskRenderer {
    /// Which component kinds a video mask may use.
    static let supportedKinds: [PhotoMaskComponentKind] = [
        .radialGradient, .linearGradient, .luminanceRange, .colorRange,
    ]

    /// The two qualifier kernels, passed down so a test can hand in `nil` —
    /// what a release build gets when the metallib does not load (FS-16 AC-7).
    struct Kernels {
        var luminanceKey: CIColorKernel? = VideoMaskRenderer.luminanceKeyKernel
        var colorKey: CIColorKernel? = VideoMaskRenderer.colorKeyKernel
    }

    static func apply(_ masks: [PhotoMask], to image: CIImage, kernels: Kernels = Kernels()) -> CIImage {
        var output = image
        for mask in masks where mask.isVisible {
            guard let matte = matte(for: mask, extent: image.extent, source: output, kernels: kernels) else { continue }
            let adjusted = PhotoRenderService.applyAdjustments(
                mask.adjustments,
                to: output,
                appliesExposure: true
            )
            output = blend(adjusted: adjusted, original: output, matte: matte)
        }
        return output
    }

    // MARK: Matte

    private static func matte(
        for mask: PhotoMask,
        extent: CGRect,
        source: CIImage,
        kernels: Kernels
    ) -> CIImage? {
        var accumulated: CIImage?
        for component in mask.components where supportedKinds.contains(component.kind) {
            guard var incoming = componentMatte(component, extent: extent, source: source, kernels: kernels) else { continue }
            if component.opacity < 0.999 {
                incoming = scaled(incoming, by: component.opacity, extent: extent)
            }
            accumulated = accumulated.map { combine($0, incoming, operation: component.operation, extent: extent) }
                ?? (component.operation == .subtract ? nil : incoming)
        }
        guard var matte = accumulated else { return nil }
        if mask.isInverted {
            matte = matte.applyingFilter("CIColorInvert").cropped(to: extent)
        }
        return matte
    }

    private static func componentMatte(
        _ component: PhotoMaskComponent,
        extent: CGRect,
        source: CIImage,
        kernels: Kernels
    ) -> CIImage? {
        switch component.kind {
        case .radialGradient:
            return radial(component, extent: extent)
        case .linearGradient:
            return linear(component, extent: extent)
        case .luminanceRange:
            return luminanceRange(component, extent: extent, source: source, kernel: kernels.luminanceKey)
        case .colorRange:
            return colorRange(component, extent: extent, source: source, kernel: kernels.colorKey)
        default:
            return nil
        }
    }

    /// A soft ellipse. `CIRadialGradient` is circular, so the ellipse comes
    /// from drawing a circle and scaling the result — the same trick the
    /// photo editor's radial window uses.
    private static func radial(_ component: PhotoMaskComponent, extent: CGRect) -> CIImage? {
        let centre = point(component.center, in: extent)
        let radiusX = max(2, component.radiusX * extent.width)
        let radiusY = max(2, component.radiusY * extent.height)
        let feather = max(0.001, component.feather)
        guard let gradient = CIFilter(name: "CIRadialGradient") else { return nil }
        gradient.setValue(CIVector(x: 0, y: 0), forKey: "inputCenter")
        gradient.setValue(radiusX * (1 - feather), forKey: "inputRadius0")
        gradient.setValue(radiusX, forKey: "inputRadius1")
        gradient.setValue(CIColor.white, forKey: "inputColor0")
        gradient.setValue(CIColor.black, forKey: "inputColor1")
        guard let circle = gradient.outputImage else { return nil }
        let squashed = circle.transformed(by: CGAffineTransform(scaleX: 1, y: radiusY / radiusX))
        return squashed
            .transformed(by: CGAffineTransform(translationX: centre.x, y: centre.y))
            .cropped(to: extent)
    }

    private static func linear(_ component: PhotoMaskComponent, extent: CGRect) -> CIImage? {
        guard let gradient = CIFilter(name: "CILinearGradient") else { return nil }
        gradient.setValue(vector(component.startPoint, in: extent), forKey: "inputPoint0")
        gradient.setValue(vector(component.endPoint, in: extent), forKey: "inputPoint1")
        gradient.setValue(CIColor.white, forKey: "inputColor0")
        gradient.setValue(CIColor.black, forKey: "inputColor1")
        return gradient.outputImage?.cropped(to: extent)
    }

    /// The tonal qualifier: everything whose luminance falls in the band,
    /// with a soft shoulder either side so the key does not tear.
    private static func luminanceRange(
        _ component: PhotoMaskComponent,
        extent: CGRect,
        source: CIImage,
        kernel: CIColorKernel?
    ) -> CIImage? {
        let low = min(component.luminanceMinimum, component.luminanceMaximum)
        let high = max(component.luminanceMinimum, component.luminanceMaximum)
        let feather = max(0.01, component.feather * 0.25)
        guard let kernel else { return nil }
        return kernel.apply(
            extent: extent,
            arguments: [source.cropped(to: extent), Float(low), Float(high), Float(feather)]
        )
    }

    /// The colour qualifier: distance from a sampled colour, inside a
    /// tolerance. This is what Resolve's HSL qualifier does at heart.
    private static func colorRange(
        _ component: PhotoMaskComponent,
        extent: CGRect,
        source: CIImage,
        kernel: CIColorKernel?
    ) -> CIImage? {
        let tolerance = max(0.01, component.colorTolerance)
        guard let kernel else { return nil }
        let target = CIVector(
            x: component.sampledRed,
            y: component.sampledGreen,
            z: component.sampledBlue
        )
        return kernel.apply(
            extent: extent,
            arguments: [source.cropped(to: extent), target, Float(tolerance)]
        )
    }

    /// Built once per process, not once per frame: the compositor calls the
    /// two qualifiers thirty times a second. `VideoMaskKernels.ci.metal`, in
    /// the app's own metallib — they are the app's, not the kit's.
    private static let appKernels = CoreImageKernelLibrary(bundle: .main)
    static let luminanceKeyKernel = appKernels.colorKernel(named: "luminanceKey")

    static let colorKeyKernel = appKernels.colorKernel(named: "colorKey")

    // MARK: Combining

    private static func combine(
        _ base: CIImage,
        _ incoming: CIImage,
        operation: MaskBlendOperation,
        extent: CGRect
    ) -> CIImage {
        let name = switch operation {
        case .add: "CILightenBlendMode"
        case .subtract: "CIDarkenBlendMode"
        }
        let source = operation == .subtract
            ? incoming.applyingFilter("CIColorInvert")
            : incoming
        return source
            .applyingFilter(name, parameters: [kCIInputBackgroundImageKey: base])
            .cropped(to: extent)
    }

    private static func scaled(_ image: CIImage, by amount: Double, extent: CGRect) -> CIImage {
        image.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: amount, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: amount, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: amount, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ]
        ).cropped(to: extent)
    }

    private static func blend(adjusted: CIImage, original: CIImage, matte: CIImage) -> CIImage {
        adjusted.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: original,
                kCIInputMaskImageKey: matte,
            ]
        ).cropped(to: original.extent)
    }

    // MARK: Geometry

    private static func point(_ normalized: NormalizedPoint, in extent: CGRect) -> CGPoint {
        CGPoint(
            x: extent.minX + normalized.x * extent.width,
            // Normalized points are top-left origin; Core Image is bottom-left.
            y: extent.minY + (1 - normalized.y) * extent.height
        )
    }

    private static func vector(_ normalized: NormalizedPoint, in extent: CGRect) -> CIVector {
        let p = point(normalized, in: extent)
        return CIVector(x: p.x, y: p.y)
    }
}
