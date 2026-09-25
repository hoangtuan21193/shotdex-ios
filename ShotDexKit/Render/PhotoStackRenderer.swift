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

/// How a focus stack picks its pixels (FS-01.10 §3).
public struct FocusStackOptions: Sendable, Equatable {
    public enum Method: String, CaseIterable, Identifiable, Sendable {
        /// Each point from the frame that is sharpest there, with the choice
        /// smoothed like a depth map — Helicon's B, Zerene's DMap. Smooth, keeps
        /// colour, good on long stacks and smooth surfaces.
        case depthMap
        /// Every frame, weighted by how sharp it is at that point — Helicon's
        /// A, Zerene's PMax. Holds fine crossing detail: hair, bristles.
        case weighted
        public var id: String { rawValue }
    }

    public var method: Method
    /// Size of the neighbourhood sharpness is judged over, 1…10 pixels of the
    /// working image. Small keeps fine detail and can add noise.
    public var radius: Int
    /// How much the choice between frames is blurred, 0…10. Low is sharper
    /// and can show artefacts.
    public var smoothing: Int

    public init(method: Method, radius: Int, smoothing: Int) {
        self.method = method
        self.radius = min(10, max(1, radius))
        self.smoothing = min(10, max(0, smoothing))
    }

    /// Starting values per method. No vendor publishes defaults. Depth Map's
    /// are the spike's ([2026-09-24](../../docs/_intents/2026-09-24-focus-stack-spike.md) §3);
    /// Weighted's were too (Radius 2, Smoothing 0) until the 16-frame bracket
    /// in `FocusStackBracketTests` measured them: 30.0 dB there against 35.5
    /// at Radius 4, Smoothing 4.
    public static func defaults(for method: Method) -> FocusStackOptions {
        switch method {
        case .weighted: FocusStackOptions(method: .weighted, radius: 4, smoothing: 4)
        case .depthMap: FocusStackOptions(method: .depthMap, radius: 4, smoothing: 4)
        }
    }

    public static let standard = defaults(for: .weighted)
}

/// A focus bracket already fitted and lined up, ready to be stacked any
/// number of times: changing method or a slider re-stacks it without
/// registering the frames again.
public struct PreparedFocusStack: @unchecked Sendable {
    public var frames: [CIImage]
    /// Indices into the input frames that would not line up and were left out.
    public var excludedFrames: [Int]
    /// For each of `frames`, its index among the input frames. A retouch
    /// stroke names its frame this way, so the same stroke finds the same
    /// frame at preview size and at full resolution.
    public var inputIndices: [Int]

    public init(frames: [CIImage], excludedFrames: [Int], inputIndices: [Int]) {
        self.frames = frames
        self.excludedFrames = excludedFrames
        self.inputIndices = inputIndices
    }
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
    /// A focus stack where fewer than two frames lined up: they are not one
    /// bracket, and saying "pick two photos" to someone who picked eight is a
    /// wrong answer (FS-01.10 §4).
    case framesDoNotLineUp

    public var errorDescription: String? {
        switch self {
        case .needsTwoImages: "Pick at least two photos to combine."
        case .renderFailed: "Those photos couldn't be combined."
        case .framesDoNotLineUp: "These photos couldn't be lined up. A focus stack needs frames of one scene, shot from one spot."
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

    /// The context, for the renderer's extensions in other files.
    var renderingContext: CIContext { context }

    /// Combines `images` in the given mode. The first image sets the frame:
    /// every other one is scaled to it, because a stack shot on one camera is
    /// the same size and a stack that is not is a mistake worth absorbing
    /// rather than refusing.
    public func combine(
        images: [CIImage],
        mode: PhotoStackMode,
        focus: FocusStackOptions = .standard,
        alignmentProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> CIImage {
        try combineReportingFrames(images: images, mode: mode, focus: focus, alignmentProgress: alignmentProgress).image
    }

    /// Like `combine`, and also says which frames were left out.
    ///
    /// A focus stack drops every frame it cannot line up (FS-01.10 §4): a frame
    /// stacked unaligned smears its sharp detail across the others, which is
    /// worse than not having it. The other modes use every frame.
    public func combineReportingFrames(
        images: [CIImage],
        mode: PhotoStackMode,
        focus: FocusStackOptions = .standard,
        alignmentProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> PhotoStackResult {
        guard images.count >= 2 else { throw PhotoStackError.needsTwoImages }
        let base = images[0]
        let extent = base.extent
        guard extent.width > 0, extent.height > 0 else { throw PhotoStackError.renderFailed }

        if mode == .focusStack {
            let prepared = try prepareFocusStack(images: images, alignmentProgress: alignmentProgress)
            return PhotoStackResult(image: focusStack(prepared, options: focus), excludedFrames: prepared.excludedFrames)
        }
        var frames: [CIImage] = [base]
        for (offset, image) in images.dropFirst().enumerated() {
            alignmentProgress?(offset + 1, images.count - 1)
            frames.append(Self.fitted(image, to: extent))
        }
        let image: CIImage
        switch mode {
        case .average: image = Self.averaged(frames)
        case .lighten: image = Self.reduced(frames, using: CIFilter.lightenBlendMode())
        case .darken: image = Self.reduced(frames, using: CIFilter.darkenBlendMode())
        case .focusStack: image = frames[0]
        }
        return PhotoStackResult(image: image, excludedFrames: [])
    }

    /// Fits every frame to the first and lines the bracket up, dropping frames
    /// that will not line up (FS-01.10 §4).
    public func prepareFocusStack(
        images: [CIImage],
        alignmentProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> PreparedFocusStack {
        guard images.count >= 2 else { throw PhotoStackError.needsTwoImages }
        let base = images[0]
        let extent = base.extent
        guard extent.width > 0, extent.height > 0 else { throw PhotoStackError.renderFailed }
        let fittedFrames = [base] + images.dropFirst().map { Self.fitted($0, to: extent) }
        let maps = alignedMaps(fittedFrames, extent: extent)
        var frames: [CIImage] = [base]
        var kept: [Int] = [0]
        var excluded: [Int] = []
        for index in fittedFrames.indices.dropFirst() {
            alignmentProgress?(index, fittedFrames.count - 1)
            guard let map = maps[index] else {
                excluded.append(index)
                continue
            }
            kept.append(index)
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
        guard frames.count >= 2 else { throw PhotoStackError.framesDoNotLineUp }
        return PreparedFocusStack(frames: frames, excludedFrames: excluded, inputIndices: kept)
    }

    /// Stacks a prepared bracket with the given method and parameters.
    public func focusStack(_ prepared: PreparedFocusStack, options: FocusStackOptions) -> CIImage {
        switch options.method {
        case .depthMap: focusStacked(prepared.frames, options: options)
        case .weighted: Self.weightedFocusStack(prepared.frames, options: options)
        }
    }

    /// How far `map` moves the farthest corner of `extent`, in pixels.
    static func largestShift(of map: CGAffineTransform, in extent: CGRect) -> CGFloat {
        [CGPoint(x: extent.minX, y: extent.minY), CGPoint(x: extent.maxX, y: extent.minY),
         CGPoint(x: extent.minX, y: extent.maxY), CGPoint(x: extent.maxX, y: extent.maxY)]
            .map { p in let q = p.applying(map); return hypot(q.x - p.x, q.y - p.y) }
            .max() ?? 0
    }

    /// Focus-bracket alignment (`FocusStackAligner`) on small renders of the
    /// frames, handed back as Core Image transforms moving each frame onto the
    /// base, or nil for a frame that would not line up.
    private func alignedMaps(_ frames: [CIImage], extent: CGRect) -> [CGAffineTransform?] {
        let small: [CGImage] = frames.compactMap { workingImage(of: $0, extent: extent, context: context) }
        guard small.count == frames.count else {
            return [.identity] + Array(repeating: nil, count: max(0, frames.count - 1))
        }
        return Self.alignedMaps(working: small, extent: extent)
    }

    /// One frame at the aligner's working size.
    func workingImage(of frame: CIImage, extent: CGRect, context: CIContext) -> CGImage? {
        let scale = min(1, CGFloat(FocusStackAligner.workingEdge) / max(extent.width, extent.height))
        let scaled = frame.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(scaled, from: scaled.extent.integral)
    }

    /// `FocusStackAligner` on frames already at working size, as Core Image
    /// transforms at full size.
    static func alignedMaps(working small: [CGImage], extent: CGRect) -> [CGAffineTransform?] {
        let scale = min(1, CGFloat(FocusStackAligner.workingEdge) / max(extent.width, extent.height))
        let shrink = CGAffineTransform(scaleX: scale, y: scale)
        // The aligner answers in working pixels, top-left origin. Core Image
        // wants full-resolution pixels, bottom-left origin: shrink, apply, grow
        // back — each side of that flipped about the frame's height.
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: extent.height)
        return FocusStackAligner.align(small).map { working in
            working.map { map in
                let topLeftFull = shrink.concatenating(map).concatenating(shrink.inverted())
                let ci = flip.concatenating(topLeftFull).concatenating(flip)
                // A frame that moves less than a third of a pixel anywhere is left
                // where it is: resampling it would soften every pixel to correct
                // an error nobody could see — the tripod case, and the common one.
                return Self.largestShift(of: ci, in: extent) < 0.33 ? .identity : ci
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
    private func focusStacked(_ frames: [CIImage], options: FocusStackOptions) -> CIImage {
        var result = frames[0]
        var bestSharpness = Self.sharpnessMap(of: frames[0], radius: options.radius)

        for frame in frames.dropFirst() {
            let sharpness = Self.sharpnessMap(of: frame, radius: options.radius)
            // Where this frame beats the incumbent, the difference is positive;
            // everywhere else it clamps to black, which is exactly the mask.
            // 1 where this frame is sharper than every frame so far, 0 where it
            // is not, kept inside 0…1: a mask outside that range makes the blend
            // below extrapolate, and the picture comes out unlike any frame.
            // Then softened, so the choice does not speckle on noise.
            guard let decision = Self.decisionKernel?.apply(extent: frame.extent, arguments: [sharpness, bestSharpness])
            else { continue }
            let mask = Self.smoothed(decision, radius: options.smoothing).applyingFilter("CIColorClamp")

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

    /// "This frame is sharper here", as a clean 0 or 1 with a narrow ramp so a
    /// near tie does not flip on noise.
    static let decisionKernel = CoreImageKernelLibrary.kit.colorKernel(named: "focusDecision")

    /// Every frame at every point, weighted by its sharpness there relative to
    /// the sharpest frame at that point, to the eighth power (1.3 dB over the
    /// fourth on the 16-frame bracket): the sharpest frame
    /// dominates without the others being cut off, so detail that crosses
    /// between frames survives. Relative, because a sharpness map's scale
    /// depends on the picture — a fixed gain either saturates every frame or
    /// none. Two passes over frames already in hand, running totals only, so
    /// memory stays flat in the number of frames.
    private static func weightedFocusStack(_ frames: [CIImage], options: FocusStackOptions) -> CIImage {
        let extent = frames[0].extent
        let sharpness = frames.map { smoothed(sharpnessMap(of: $0, radius: options.radius), radius: options.smoothing) }
        var peak = sharpness[0]
        for map in sharpness.dropFirst() {
            peak = peakKernel?.apply(extent: extent, arguments: [peak, map]) ?? peak
        }
        var colour = CIImage(color: .black).cropped(to: extent)
        var weight = colour
        for (frame, map) in zip(frames, sharpness) {
            colour = weightedColourKernel?.apply(extent: extent, arguments: [colour, frame, map, peak]) ?? colour
            weight = weightedTotalKernel?.apply(extent: extent, arguments: [weight, map, peak]) ?? weight
        }
        return weightedResolveKernel?.apply(extent: extent, arguments: [colour, weight]) ?? frames[0]
    }

    static let peakKernel = CoreImageKernelLibrary.kit.colorKernel(named: "focusPeak")

    // The floor on w keeps every term inside a half float's normal range —
    // Core Image's working format. Below it the sums lose precision and the
    // divide drifts the picture's brightness.
    static let weightedColourKernel = CoreImageKernelLibrary.kit.colorKernel(named: "focusWeightedColour")

    static let weightedTotalKernel = CoreImageKernelLibrary.kit.colorKernel(named: "focusWeightedTotal")

    static let weightedResolveKernel = CoreImageKernelLibrary.kit.colorKernel(named: "focusWeightedResolve")

    // MARK: Pieces

    /// How much local detail each point has: luminance, a Laplacian, then the
    /// magnitude of the response blurred into a neighbourhood. High where the
    /// image has edges to resolve, low where it is out of focus.
    static func sharpnessMap(of image: CIImage, radius: Int) -> CIImage {
        let extent = image.extent
        // Edges clamped outward first, so neither the Laplacian nor the blur
        // reads past the frame: outside it Core Image returns transparent
        // black, and a Laplacian across that step is the largest response in
        // the picture — the frame border would outvote every real detail.
        guard let laplacian = laplacianKernel?.apply(
            extent: extent,
            roiCallback: { _, rect in rect.insetBy(dx: -1, dy: -1) },
            arguments: [image.clampedToExtent()]
        ) else { return image }
        let blur = CIFilter.boxBlur()
        blur.inputImage = laplacian.clampedToExtent()
        blur.radius = Float(radius)
        return (blur.outputImage ?? laplacian).cropped(to: extent)
    }

    /// |Laplacian| of luminance, never negative, opaque — a sharpness score
    /// every later blend can read as a plain number.
    static let laplacianKernel = CoreImageKernelLibrary.kit.kernel(named: "focusLaplacian")

    static func smoothed(_ image: CIImage, radius: Int) -> CIImage {
        guard radius > 0 else { return image }
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = image
        blur.radius = Float(radius)
        return (blur.outputImage ?? image).cropped(to: image.extent)
    }

    /// Scales a frame onto the base frame's extent. Same-size stacks — the
    /// normal case — pass straight through.
    static func fitted(_ image: CIImage, to extent: CGRect) -> CIImage {
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
