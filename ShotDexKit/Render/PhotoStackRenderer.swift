import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

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

    /// Whether the mode needs the frames lined up first. Blending modes tolerate
    /// a little drift (it reads as motion); a focus stack does not — a two-pixel
    /// shift turns the sharpness comparison into noise.
    public var needsAlignment: Bool { self == .focusStack }
}

/// A combined image and the frames that did not make it in.
public struct PhotoStackResult: @unchecked Sendable {
    public var image: CIImage
    /// Indices into the input frames that were left out, in order.
    public var excludedFrames: [Int]
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
        try combineReportingFrames(images: images, mode: mode, alignmentProgress: alignmentProgress).image
    }

    /// Like `combine`, and also says which frames were left out.
    ///
    /// A focus stack drops every frame it cannot line up (FS-01.10 §4): a frame
    /// stacked unaligned smears its sharp detail across the others, which is
    /// worse than not having it. The other modes use every frame.
    public func combineReportingFrames(
        images: [CIImage],
        mode: PhotoStackMode,
        alignmentProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> PhotoStackResult {
        guard images.count >= 2 else { throw PhotoStackError.needsTwoImages }
        let base = images[0]
        let extent = base.extent
        guard extent.width > 0, extent.height > 0 else { throw PhotoStackError.renderFailed }

        let fittedFrames = [base] + images.dropFirst().map { Self.fitted($0, to: extent) }
        var frames: [CIImage] = [base]
        var excluded: [Int] = []
        let maps: [CGAffineTransform?] = mode.needsAlignment
            ? alignedMaps(fittedFrames, extent: extent)
            : Array(repeating: .identity, count: fittedFrames.count)
        for index in fittedFrames.indices.dropFirst() {
            alignmentProgress?(index, fittedFrames.count - 1)
            guard let map = maps[index] else {
                excluded.append(index)
                continue
            }
            if map == .identity {
                frames.append(fittedFrames[index])
            } else {
                // Clamped before cropping: a shift of a few pixels leaves that
                // much of the frame uncovered, and transparent edges composite
                // as a white border around the whole stack. Clamping repeats the
                // edge pixel instead, invisible at the scale alignment moves.
                frames.append(fittedFrames[index].transformed(by: map).clampedToExtent().cropped(to: extent))
            }
        }
        guard frames.count >= 2 else { throw PhotoStackError.needsTwoImages }

        let image: CIImage
        switch mode {
        case .average: image = Self.averaged(frames)
        case .lighten: image = Self.reduced(frames, using: CIFilter.lightenBlendMode())
        case .darken: image = Self.reduced(frames, using: CIFilter.darkenBlendMode())
        case .focusStack: image = focusStacked(frames)
        }
        return PhotoStackResult(image: image, excludedFrames: excluded)
    }

    /// Focus-bracket alignment (`FocusStackAligner`) on small renders of the
    /// frames, handed back as Core Image transforms moving each frame onto the
    /// base, or nil for a frame that would not line up.
    private func alignedMaps(_ frames: [CIImage], extent: CGRect) -> [CGAffineTransform?] {
        let scale = min(1, CGFloat(PanoramaImage.workingEdge) / max(extent.width, extent.height))
        let shrink = CGAffineTransform(scaleX: scale, y: scale)
        let small: [CGImage] = frames.compactMap { frame in
            let scaled = frame.transformed(by: shrink)
            return context.createCGImage(scaled, from: scaled.extent.integral)
        }
        guard small.count == frames.count else {
            return [.identity] + Array(repeating: nil, count: max(0, frames.count - 1))
        }
        // The aligner answers in working pixels, top-left origin. Core Image
        // wants full-resolution pixels, bottom-left origin: shrink, apply, grow
        // back — each side of that flipped about the frame's height.
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: extent.height)
        return FocusStackAligner.align(small).map { working in
            working.map { map in
                let topLeftFull = shrink.concatenating(map).concatenating(shrink.inverted())
                return flip.concatenating(topLeftFull).concatenating(flip)
            }
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

    /// Renders a combined image to a CGImage for saving or display.
    public func render(_ image: CIImage) throws -> CGImage {
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            throw PhotoStackError.renderFailed
        }
        return cgImage
    }
}
