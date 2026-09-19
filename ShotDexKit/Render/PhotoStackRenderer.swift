import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Vision

/// How several frames of the same subject are combined into one.
public enum PhotoStackMode: String, CaseIterable, Identifiable, Sendable {
    /// Every frame at equal weight — the film double-exposure look, and the way
    /// to average noise out of a handheld burst.
    case average
    /// Keeps the brightest pixel of the stack. Light trails, fireworks, star
    /// trails: the classic reason to shoot a sequence.
    case lighten
    /// Keeps the darkest. Removes passers-by from a tripod sequence of a busy
    /// street, because a given pixel is background in most frames.
    case darken
    /// Keeps the sharpest pixel of the stack — focus stacking, the macro
    /// shooter's reason to take eight frames of one insect.
    case focusStack

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .average: "Average"
        case .lighten: "Lighten"
        case .darken: "Darken"
        case .focusStack: "Focus Stack"
        }
    }

    /// One line under the picker. Says what the mode is *for*, not what it does
    /// arithmetically — the arithmetic is visible in the preview.
    public var explanation: String {
        switch self {
        case .average: "Every frame at equal weight, like a film double exposure."
        case .lighten: "Keeps the brightest pixel of each spot — light trails and fireworks."
        case .darken: "Keeps the darkest — clears people out of a tripod sequence."
        case .focusStack: "Keeps the sharpest pixel of each spot, for macro depth of field."
        }
    }

    /// Whether the mode needs the frames lined up first. Blending modes tolerate
    /// a little drift (it reads as motion); a focus stack does not — a two-pixel
    /// shift turns the sharpness comparison into noise.
    public var needsAlignment: Bool { self == .focusStack }
}

public enum PhotoStackError: LocalizedError {
    case needsTwoImages
    case renderFailed

    public var errorDescription: String? {
        switch self {
        case .needsTwoImages: "Pick at least two photos to combine."
        case .renderFailed: "Those photos couldn't be combined."
        }
    }
}

/// Combines a run of frames into one image: multiple exposure and focus
/// stacking.
///
/// Separate from `PhotoRenderService`, which renders *one* photo through an edit
/// recipe. This takes many photos and produces one, so it has no recipe, no
/// session and no asset — it is given images and hands back an image, and the
/// result is then saved or handed to the editor like any other photo.
public actor PhotoStackRenderer {
    private let context: CIContext

    public init(context: CIContext = CIContext(options: [.useSoftwareRenderer: false])) {
        self.context = context
    }

    /// Combines `images` in the given mode. The first image sets the frame:
    /// every other one is scaled to it, because a stack shot on one camera is
    /// the same size and a stack that is not is a mistake worth absorbing
    /// rather than refusing.
    public func combine(
        images: [CIImage],
        mode: PhotoStackMode,
        alignmentProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> CIImage {
        guard images.count >= 2 else { throw PhotoStackError.needsTwoImages }
        let base = images[0]
        let extent = base.extent
        guard extent.width > 0, extent.height > 0 else { throw PhotoStackError.renderFailed }

        var frames: [CIImage] = [base]
        for (offset, image) in images.dropFirst().enumerated() {
            var frame = Self.fitted(image, to: extent)
            if mode.needsAlignment {
                frame = align(frame, to: base) ?? frame
            }
            alignmentProgress?(offset + 1, images.count - 1)
            frames.append(frame)
        }

        switch mode {
        case .average: return Self.averaged(frames)
        case .lighten: return Self.reduced(frames, using: CIFilter.lightenBlendMode())
        case .darken: return Self.reduced(frames, using: CIFilter.darkenBlendMode())
        case .focusStack: return focusStacked(frames)
        }
    }

    // MARK: Modes

    /// Equal weight for every frame, done as a running mean so a stack of forty
    /// does not clip the accumulator on frame two.
    private static func averaged(_ frames: [CIImage]) -> CIImage {
        var result = frames[0]
        for (index, frame) in frames.enumerated().dropFirst() {
            // The new frame is worth 1/(n+1) of the result so far.
            let weight = 1.0 / Double(index + 1)
            let blend = CIFilter.mix()
            blend.inputImage = frame
            blend.backgroundImage = result
            blend.amount = Float(weight)
            result = blend.outputImage ?? result
        }
        return result
    }

    private static func reduced(_ frames: [CIImage], using filter: CIFilter & CICompositeOperation) -> CIImage {
        var result = frames[0]
        for frame in frames.dropFirst() {
            filter.inputImage = frame
            filter.backgroundImage = result
            result = filter.outputImage ?? result
        }
        return result
    }

    /// Keeps, at every point, the pixel from whichever frame is locally
    /// sharpest.
    ///
    /// Iterative rather than all-at-once: carry the winning pixels and their
    /// sharpness, and for each new frame build a mask of "this frame is sharper
    /// here" and blend through it. That keeps memory flat in the number of
    /// frames, which matters — a macro stack is routinely thirty exposures.
    private func focusStacked(_ frames: [CIImage]) -> CIImage {
        var result = frames[0]
        var bestSharpness = Self.sharpnessMap(of: frames[0])

        for frame in frames.dropFirst() {
            let sharpness = Self.sharpnessMap(of: frame)
            // Where this frame beats the incumbent, the difference is positive;
            // everywhere else it clamps to black, which is exactly the mask.
            let difference = CIFilter.subtractBlendMode()
            difference.inputImage = sharpness
            difference.backgroundImage = bestSharpness
            guard let raw = difference.outputImage else { continue }

            // Harden the mask and soften its edges: a per-pixel winner-takes-all
            // mask speckles on noise, and the seams read as grain that moves.
            let mask = Self.smoothed(Self.hardened(raw))

            let blend = CIFilter.blendWithMask()
            blend.inputImage = frame
            blend.backgroundImage = result
            blend.maskImage = mask
            result = blend.outputImage ?? result

            let keepBest = CIFilter.lightenBlendMode()
            keepBest.inputImage = sharpness
            keepBest.backgroundImage = bestSharpness
            bestSharpness = keepBest.outputImage ?? bestSharpness
        }
        return result
    }

    // MARK: Pieces

    /// How much local detail each point has: luminance, a Laplacian, then the
    /// magnitude of the response blurred into a neighbourhood. High where the
    /// image has edges to resolve, low where it is out of focus.
    private static func sharpnessMap(of image: CIImage) -> CIImage {
        let mono = CIFilter.photoEffectMono()
        mono.inputImage = image
        let grey = mono.outputImage ?? image

        let laplacian = CIFilter.convolution3X3()
        laplacian.inputImage = grey
        laplacian.weights = CIVector(values: [0, 1, 0, 1, -4, 1, 0, 1, 0], count: 9)
        laplacian.bias = 0
        guard let edges = laplacian.outputImage else { return grey }

        // A Laplacian is signed; what matters is the size of the response.
        let magnitude = CIFilter.colorAbsoluteDifference()
        magnitude.inputImage = edges
        magnitude.inputImage2 = CIImage(color: .black).cropped(to: edges.extent)
        let response = magnitude.outputImage ?? edges

        let blur = CIFilter.boxBlur()
        blur.inputImage = response
        blur.radius = 6
        return (blur.outputImage ?? response).cropped(to: image.extent)
    }

    /// Pushes a near-zero difference to black and anything real to white, so the
    /// mask is a decision rather than a weighting.
    private static func hardened(_ image: CIImage) -> CIImage {
        let controls = CIFilter.colorControls()
        controls.inputImage = image
        controls.contrast = 12
        controls.brightness = 0
        controls.saturation = 0
        return controls.outputImage ?? image
    }

    private static func smoothed(_ image: CIImage) -> CIImage {
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = image
        blur.radius = 3
        return (blur.outputImage ?? image).cropped(to: image.extent)
    }

    /// Scales a frame onto the base frame's extent. Same-size stacks — the
    /// normal case — pass straight through.
    private static func fitted(_ image: CIImage, to extent: CGRect) -> CIImage {
        guard image.extent != extent, image.extent.width > 0, image.extent.height > 0 else {
            return image
        }
        let scale = CGAffineTransform(
            scaleX: extent.width / image.extent.width,
            y: extent.height / image.extent.height
        )
        return image.transformed(by: scale).clampedToExtent().cropped(to: extent)
    }

    /// Lines a frame up with the base using Vision's translational registration.
    ///
    /// Translation only, not homography: a focus stack is shot on a tripod or a
    /// rail, so what drifts is a few pixels of shift, and fitting a perspective
    /// warp to that mostly fits the noise. Returns nil when Vision cannot
    /// register the pair, and the caller keeps the unaligned frame rather than
    /// dropping it.
    private func align(_ image: CIImage, to base: CIImage) -> CIImage? {
        let request = VNTranslationalImageRegistrationRequest(targetedCIImage: image)
        let handler = VNImageRequestHandler(ciImage: base)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first as? VNImageTranslationAlignmentObservation
        else { return nil }
        // Clamped before cropping: a shift of a few pixels leaves that much of
        // the frame uncovered, and transparent edges composite as a white border
        // around the whole stack. Clamping repeats the edge pixel instead, which
        // is invisible at the scale the alignment actually moves things.
        return image
            .transformed(by: observation.alignmentTransform)
            .clampedToExtent()
            .cropped(to: base.extent)
    }

    /// Renders a combined image to a CGImage for saving or display.
    public func render(_ image: CIImage) throws -> CGImage {
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            throw PhotoStackError.renderFailed
        }
        return cgImage
    }
}
