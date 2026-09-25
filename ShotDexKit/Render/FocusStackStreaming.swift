import CoreGraphics
import CoreImage
import Foundation

/// A full-resolution focus stack, and the frames it left out.
public struct StreamedFocusStack: @unchecked Sendable {
    public var image: CGImage
    /// Indices into the input frames that would not line up.
    public var excludedFrames: [Int]
}

/// A pixel buffer Core Image reads from and renders back into — the running
/// state of a streamed stack. Owned memory, freed with the buffer.
final class StackBuffer {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let format: CIFormat
    let colorSpace: CGColorSpace?
    private let pointer: UnsafeMutableRawPointer

    init(width: Int, height: Int, bytesPerPixel: Int, format: CIFormat, colorSpace: CGColorSpace?) {
        self.width = width
        self.height = height
        self.format = format
        self.colorSpace = colorSpace
        bytesPerRow = width * bytesPerPixel
        pointer = UnsafeMutableRawPointer.allocate(byteCount: bytesPerRow * height, alignment: 64)
        pointer.initializeMemory(as: UInt8.self, repeating: 0, count: bytesPerRow * height)
    }

    deinit { pointer.deallocate() }

    /// The buffer as it is now. A new image every call: Core Image caches by
    /// image, and the contents change under it between renders.
    var image: CIImage { image(rows: 0..<height) }

    /// Only the rows under `strip` (Core Image coordinates), plus `margin`
    /// rows either side for filters that read neighbours. Core Image uploads
    /// the whole of a bitmap it is given, so handing it the full buffer on
    /// every strip made each render copy a 192 MB colour sum at 24 MP.
    func image(near strip: CGRect, margin: Int) -> CIImage {
        let low = max(0, Int(strip.minY.rounded(.down)) - margin)
        let high = min(height, Int(strip.maxY.rounded(.up)) + margin)
        return image(rows: (height - high)..<(height - low))
    }

    /// Buffer rows (top-down) as an image placed where they belong in the
    /// bottom-up frame.
    private func image(rows: Range<Int>) -> CIImage {
        let data = Data(bytesNoCopy: pointer + rows.lowerBound * bytesPerRow,
                        count: rows.count * bytesPerRow, deallocator: .none)
        return CIImage(bitmapData: data, bytesPerRow: bytesPerRow,
                       size: CGSize(width: width, height: rows.count), format: format, colorSpace: colorSpace)
            .transformed(by: CGAffineTransform(translationX: 0, y: CGFloat(height - rows.upperBound)))
    }

    /// Rows rendered per call. A whole-frame render makes every intermediate
    /// of the graph — sharpness, blur, decision — a full-size texture at once;
    /// a strip keeps them a strip tall.
    static let stripHeight = 256

    /// Renders the image `build` makes for each strip into that strip. Safe
    /// in place only when every output pixel reads this buffer at that same
    /// pixel and nowhere else.
    func render(context: CIContext, _ build: (CGRect) -> CIImage?) {
        var top = 0
        while top < height {
            let rows = min(Self.stripHeight, height - top)
            // Core Image's y runs bottom-up and the buffer's rows top-down:
            // buffer rows top..<top+rows are image y from height-top-rows.
            let bounds = CGRect(x: 0, y: height - top - rows, width: width, height: rows)
            if let image = build(bounds) {
                context.render(image, toBitmap: pointer + top * bytesPerRow, rowBytes: bytesPerRow,
                               bounds: bounds, format: format, colorSpace: colorSpace)
            }
            top += rows
        }
    }

    /// Renders `image` over the whole buffer in one call.
    func render(_ image: CIImage, context: CIContext) {
        context.render(image, toBitmap: pointer, rowBytes: bytesPerRow,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       format: format, colorSpace: colorSpace)
    }
}

extension PhotoStackRenderer {
    /// Weighted's running sums in one pixel: colour × weight in RGB, the
    /// weight itself in alpha. Same weight as `weightedColourKernel` (r⁸).
    static let weightedAccumulateKernel = CoreImageKernelLibrary.kit.colorKernel(named: "focusWeightedAccumulate")

    static let weightedAlphaResolveKernel = CoreImageKernelLibrary.kit.colorKernel(named: "focusWeightedAlphaResolve")

    /// The full-resolution focus stack, one frame in memory at a time
    /// (FS-01.10 §6).
    ///
    /// Stacking the whole bracket as one Core Image graph pulls every frame
    /// into memory together at render time — 233 MB for four 12 MP frames and
    /// 513 MB for twelve, measured. Here each frame is decoded, folded into
    /// fixed running buffers and let go before the next one is read, so
    /// memory follows the picture's size and not the bracket's length:
    /// Depth Map keeps the result (8-bit, in the frames' colour space) and the best sharpness so far
    /// (half float), 6 bytes a pixel; Weighted keeps the sharpness peak and the
    /// weighted colour and weight sums, 10 bytes a pixel.
    ///
    /// Every buffer update reads that buffer only at the pixel it writes, so
    /// it is rendered in place. The one step that reads neighbours — Depth
    /// Map's smoothed decision — renders into a mask buffer of its own first.
    ///
    /// `frame` hands back input frame `index`, decoded lazily (from disk, at
    /// save time); it is called several times per frame and the result is
    /// never kept.
    public func streamedFocusStack(
        frameCount: Int,
        frame: @Sendable (Int) -> CIImage?,
        options: FocusStackOptions,
        strokes: [FocusStackRetouchStroke] = [],
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> StreamedFocusStack {
        guard frameCount >= 2 else { throw PhotoStackError.needsTwoImages }
        guard let first = frame(0) else { throw PhotoStackError.renderFailed }
        let extent = first.extent
        guard extent.width > 0, extent.height > 0 else { throw PhotoStackError.renderFailed }
        // Intermediates are not cached: each one is a full-size texture of a
        // frame that will not be seen again.
        let context = CIContext(options: [.cacheIntermediates: false])
        let origin = CGAffineTransform(translationX: -extent.minX, y: -extent.minY)

        // Registration, one working-size frame at a time.
        var working: [CGImage] = []
        for index in 0..<frameCount {
            try Task.checkCancellation()
            let small: CGImage? = autoreleasepool {
                guard let image = index == 0 ? first : frame(index).map({ Self.fitted($0, to: extent) }) else { return nil }
                return workingImage(of: image, extent: extent, context: context)
            }
            guard let small else { throw PhotoStackError.renderFailed }
            working.append(small)
        }
        let maps = Self.alignedMaps(working: working, extent: extent)
        working = []

        var kept: [Int] = []
        var excluded: [Int] = []
        for index in 0..<frameCount {
            if maps[index] == nil { excluded.append(index) } else { kept.append(index) }
        }
        guard kept.count >= 2 else { throw PhotoStackError.framesDoNotLineUp }

        /// Frame `index` lined up, moved to the origin the buffers use.
        func aligned(_ index: Int) -> CIImage? {
            guard let map = maps[index], let source = index == 0 ? frame(0) : frame(index).map({ Self.fitted($0, to: extent) })
            else { return nil }
            let moved = map == .identity ? source : source.transformed(by: map).clampedToExtent().cropped(to: extent)
            return moved.transformed(by: origin)
        }

        let width = Int(extent.width.rounded()), height = Int(extent.height.rounded())
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        // The first frame's own space: an iPhone's Display P3 frame stored
        // as sRGB would lose every colour outside sRGB, and eight bits in the
        // space the file was written in is exactly what was decoded.
        let space = first.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)
        var stacked: CIImage
        // What the final render still reads. Everything else is let go before
        // it: the output image is one more full-size buffer, and the peak is
        // where the budget is tight.
        var liveBuffers: [StackBuffer] = []
        // The frame being folded in, decoded once per step: every render of
        // that step reads it from here rather than decoding the file again.
        var frameBuffer: StackBuffer? = StackBuffer(width: width, height: height, bytesPerPixel: 4, format: .RGBA8, colorSpace: space)
        /// Decodes frame `index` into `frameBuffer` — one render, so the file
        /// is decoded once — and hands the buffer back to be read by strip.
        func loaded(_ index: Int) -> StackBuffer? {
            guard let image = aligned(index), let frameBuffer else { return nil }
            frameBuffer.render(image, context: context)
            return frameBuffer
        }
        // Rows beyond a strip that its sharpness and smoothing read.
        let margin = 4 + options.radius + 3 * options.smoothing

        switch options.method {
        case .depthMap:
            let result = StackBuffer(width: width, height: height, bytesPerPixel: 4, format: .RGBA8, colorSpace: space)
            var best: StackBuffer! = StackBuffer(width: width, height: height, bytesPerPixel: 2, format: .Rh, colorSpace: nil)
            var mask: StackBuffer! = StackBuffer(width: width, height: height, bytesPerPixel: 1, format: .R8, colorSpace: nil)
            liveBuffers = [result]
            for (step, index) in kept.enumerated() {
                try Task.checkCancellation()
                progress?(step + 1, kept.count)
                autoreleasepool {
                    guard let frame = loaded(index) else { return }
                    func sharpness(_ strip: CGRect) -> CIImage {
                        Self.sharpnessMap(of: frame.image(near: strip, margin: margin), radius: options.radius)
                    }
                    if step == 0 {
                        result.render(context: context) { frame.image(near: $0, margin: 0) }
                        best.render(context: context) { sharpness($0) }
                        return
                    }
                    mask.render(context: context) { strip in
                        let sharp = sharpness(strip)
                        let decision = Self.decisionKernel?.apply(
                            extent: sharp.extent, arguments: [sharp, best.image(near: strip, margin: margin)])
                        return decision.map { Self.smoothed($0, radius: options.smoothing).applyingFilter("CIColorClamp") }
                    }
                    // Red mask: the buffer is one channel, and CIBlendWithMask
                    // reads green, which a one-channel image does not have.
                    result.render(context: context) { strip in
                        CIFilter(name: "CIBlendWithRedMask", parameters: [
                            kCIInputImageKey: frame.image(near: strip, margin: 0),
                            kCIInputBackgroundImageKey: result.image(near: strip, margin: 0),
                            kCIInputMaskImageKey: mask.image(near: strip, margin: 0),
                        ])?.outputImage
                    }
                    best.render(context: context) { strip in
                        sharpness(strip).applyingFilter("CILightenBlendMode", parameters: [
                            kCIInputBackgroundImageKey: best.image(near: strip, margin: margin),
                        ])
                    }
                }
            }
            stacked = result.image
            best = nil
            mask = nil

        case .weighted:
            var peak: StackBuffer! = StackBuffer(width: width, height: height, bytesPerPixel: 2, format: .Rh, colorSpace: nil)
            // Colour sum in RGB, weight sum in alpha: one buffer and one render
            // per frame instead of two.
            let colour = StackBuffer(width: width, height: height, bytesPerPixel: 8, format: .RGBAh, colorSpace: nil)
            liveBuffers = [colour]
            func sharpness(_ frame: StackBuffer, _ strip: CGRect) -> CIImage {
                Self.smoothed(Self.sharpnessMap(of: frame.image(near: strip, margin: margin), radius: options.radius),
                              radius: options.smoothing)
            }
            // Pass 1: the sharpest any frame gets at each point.
            for (step, index) in kept.enumerated() {
                try Task.checkCancellation()
                progress?(step + 1, kept.count * 2)
                autoreleasepool {
                    guard let frame = loaded(index) else { return }
                    peak.render(context: context) { strip in
                        let map = sharpness(frame, strip)
                        return step == 0
                            ? map
                            : Self.peakKernel?.apply(extent: map.extent, arguments: [peak.image(near: strip, margin: margin), map])
                    }
                }
            }
            // Pass 2: every frame weighted against that peak.
            for (step, index) in kept.enumerated() {
                try Task.checkCancellation()
                progress?(kept.count + step + 1, kept.count * 2)
                autoreleasepool {
                    guard let frame = loaded(index) else { return }
                    colour.render(context: context) { strip in
                        let map = sharpness(frame, strip)
                        return Self.weightedAccumulateKernel?.apply(extent: map.extent, arguments: [
                            colour.image(near: strip, margin: margin), frame.image(near: strip, margin: margin),
                            map, peak.image(near: strip, margin: margin),
                        ])
                    }
                }
            }
            peak = nil
            guard let resolved = Self.weightedAlphaResolveKernel?.apply(extent: bounds, arguments: [colour.image])
            else { throw PhotoStackError.renderFailed }
            stacked = resolved
        }

        frameBuffer = nil
        if !strokes.isEmpty {
            // Only the frames a stroke names are read again, lazily, by the
            // final render.
            let used = Set(strokes.map(\.frame)).filter { kept.contains($0) }.sorted()
                .compactMap { index in aligned(index).map { (index, $0) } }
            let prepared = PreparedFocusStack(
                frames: used.map(\.1),
                excludedFrames: excluded,
                inputIndices: used.map(\.0)
            )
            stacked = retouched(stacked, prepared: prepared, strokes: strokes)
        }
        try Task.checkCancellation()
        guard let image = context.createCGImage(stacked, from: bounds, format: .RGBA8, colorSpace: space) else {
            throw PhotoStackError.renderFailed
        }
        withExtendedLifetime(liveBuffers) {}
        return StreamedFocusStack(image: image, excludedFrames: excluded)
    }
}
