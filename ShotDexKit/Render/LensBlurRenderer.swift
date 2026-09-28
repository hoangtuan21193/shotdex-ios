import CoreImage

/// Lens Blur (FS-03.15e §2): the photo re-focused on a band of depth.
///
/// The picture is cut into depth layers — the sharp band, and seven steps of
/// blur on each side of it — and each layer is blurred with the bokeh's shape
/// on its own, then laid over the ones behind it from far to near. Layering is
/// what keeps edges honest: a sharp subject is drawn over the blurred
/// background, so the background cannot smear across it, and a blurred
/// foreground spills over whatever is behind it the way an out-of-focus
/// object in front of a lens does.
///
/// Runs on the untouched picture, in Core Image's linear working space, so a
/// small light becomes a bright disc rather than a grey smudge.
public enum LensBlurRenderer {

    /// Blur steps on each side of the sharp band. With the band itself, a
    /// photo focused on its nearest part is cut into eight layers.
    static let stepsPerSide = 7

    /// The largest blur radius, as a share of the short edge: Amount 100 at
    /// the far end of the depth scale.
    static let maximumRadiusShare: CGFloat = 0.035

    /// The radius the gather kernel runs at. A bigger blur shrinks its layer
    /// first, so the kernel's fixed sample count always covers the disc
    /// densely and a 140px blur costs what a 6px one does.
    static let gatherRadius: CGFloat = 6

    /// One depth layer: the photo where the normalised depth lies in
    /// `lower..<upper`, blurred by `blur` × the recipe's full radius.
    struct Layer: Equatable {
        var lower: Double
        var upper: Double
        var blur: Double
    }

    /// The layers for a focus band, ordered far to near — the order they are
    /// composited in. Each out-of-focus step blurs by the middle of its own
    /// span of distance from the band, measured as a share of the way to that
    /// side's end of the depth scale: the farthest point of the photo always
    /// gets the full radius, whatever the band.
    static func layers(focusFar: Double, focusNear: Double) -> [Layer] {
        let low = min(max(min(focusFar, focusNear), 0), 1)
        let high = min(max(max(focusFar, focusNear), 0), 1)
        let steps = Double(stepsPerSide)
        // Just past 1, so the nearest pixel falls inside the last layer.
        let top = 1.0001
        var layers: [Layer] = []
        if low > 0 {
            for step in stride(from: stepsPerSide, through: 1, by: -1) {
                let j = Double(step)
                layers.append(Layer(
                    lower: step == stepsPerSide ? 0 : low - j / steps * low,
                    upper: low - (j - 1) / steps * low,
                    blur: (j - 0.5) / steps
                ))
            }
        }
        layers.append(Layer(lower: low, upper: high >= 1 ? top : high, blur: 0))
        if high < 1 {
            for step in 1...stepsPerSide {
                let j = Double(step)
                layers.append(Layer(
                    lower: high + (j - 1) / steps * (1 - high),
                    upper: step == stepsPerSide ? top : high + j / steps * (1 - high),
                    blur: (j - 0.5) / steps
                ))
            }
        }
        return layers
    }

    /// The photo re-focused. `depth` is the normalised map (0 = farthest,
    /// 1 = nearest) at any resolution; it is stretched onto the photo.
    ///
    /// No blur, no map, or a missing kernel returns `image` itself: a recipe
    /// carrying Lens Blur can land on a photo with no depth, and the answer
    /// there is the photo as shot (FS-03.15e §3 replaces this with an
    /// estimated map).
    public static func apply(
        _ recipe: PhotoLensBlurRecipe,
        to image: CIImage,
        depth: CIImage?
    ) -> CIImage {
        guard !recipe.isIdentity, let depth,
              let slice = sliceKernel, let gather = gatherKernel,
              let resolve = PhotoStackRenderer.weightedAlphaResolveKernel
        else { return image }
        let extent = image.extent
        guard extent.width > 1, extent.height > 1, !extent.isInfinite else { return image }
        let fullRadius = min(extent.width, extent.height) * maximumRadiusShare * CGFloat(min(max(recipe.amount, 0), 1))
        guard fullRadius > 0.5 else { return image }

        let map = stretched(depth, onto: extent)
        var accumulated: CIImage?
        for layer in layers(focusFar: recipe.focusFar, focusNear: recipe.focusNear) {
            guard let cut = slice.apply(
                extent: extent,
                arguments: [image, map, CIVector(x: layer.lower, y: layer.upper)]
            ) else { return image }
            let blurred = blur(
                cut,
                radius: fullRadius * CGFloat(layer.blur),
                shape: recipe.bokeh,
                extent: extent,
                kernel: gather
            )
            accumulated = accumulated.map { blurred.composited(over: $0) } ?? blurred
        }
        guard let accumulated,
              let output = resolve.apply(extent: extent, arguments: [accumulated])
        else { return image }
        return output.cropped(to: extent)
    }

    /// One premultiplied layer spread over the bokeh. Outside the
    /// frame the layer is transparent, so a disc that hangs over the edge
    /// loses coverage rather than pulling in black; the final resolve divides
    /// that back out.
    static func blur(
        _ layer: CIImage,
        radius: CGFloat,
        shape: PhotoBokehShape,
        extent: CGRect,
        kernel: CIKernel
    ) -> CIImage {
        guard radius > 0.5 else { return layer }
        let scale = max(1, radius / gatherRadius)
        let small: CIImage
        if scale > 1 {
            small = layer.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: 1 / scale,
                kCIInputAspectRatioKey: 1,
            ])
        } else {
            small = layer
        }
        let smallRadius = radius / scale
        let smallExtent = small.extent.integral
        guard let spread = kernel.apply(
            extent: smallExtent.insetBy(dx: -ceil(smallRadius), dy: -ceil(smallRadius)),
            roiCallback: { _, rect in rect.insetBy(dx: -ceil(smallRadius) - 1, dy: -ceil(smallRadius) - 1) },
            arguments: [
                small,
                Float(smallRadius),
                Float(shapeCode(shape)),
                CIVector(x: extent.midX / scale, y: extent.midY / scale),
                Float(hypot(extent.width, extent.height) / 2 / scale),
            ]
        ) else { return layer }
        let back = scale > 1
            ? spread.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : spread
        return back.cropped(to: extent)
    }

    static func shapeCode(_ shape: PhotoBokehShape) -> Int {
        switch shape {
        case .circle: 0
        case .bubble: 1
        case .blade: 2
        case .ring: 3
        case .catEye: 4
        }
    }

    /// An auxiliary map stretched onto the photo's frame; maps are stored at
    /// a fraction of the picture's resolution and with their own origin.
    static func stretched(_ map: CIImage, onto extent: CGRect) -> CIImage {
        let source = map.extent
        guard source.width > 0, source.height > 0, !source.isInfinite else { return map }
        return map
            .transformed(by: CGAffineTransform(translationX: -source.minX, y: -source.minY))
            .transformed(by: CGAffineTransform(
                scaleX: extent.width / source.width,
                y: extent.height / source.height
            ))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .clampedToExtent()
            .cropped(to: extent)
    }

    // MARK: Preview levels

    /// The preview's levels: the whole photo blurred 0, 1/7 … 7/7 of the
    /// radius Amount 100 gives (FS-03.15e §2).
    static let levelCount = 8

    /// The full radius at Amount 100 on a frame of `extent`.
    static func fullRadius(for extent: CGRect) -> CGFloat {
        min(extent.width, extent.height) * maximumRadiusShare
    }

    /// The whole photo spread over the bokeh by `radius`, opaque again —
    /// a disc hanging over the frame's edge is divided back out.
    static func level(_ image: CIImage, radius: CGFloat, shape: PhotoBokehShape) -> CIImage? {
        guard radius > 0.5 else { return image }
        guard let gather = gatherKernel,
              let resolve = PhotoStackRenderer.weightedAlphaResolveKernel else { return nil }
        let extent = image.extent
        let spread = blur(image, radius: radius, shape: shape, extent: extent, kernel: gather)
        return resolve.apply(extent: extent, arguments: [spread])?.cropped(to: extent)
    }

    /// The levels mixed per pixel by its depth: what the preview shows while
    /// Amount is dragged. `levels` are the eight images, each stretched onto
    /// the photo's frame already.
    static func blend(
        levels: [CIImage],
        depth: CIImage,
        recipe: PhotoLensBlurRecipe,
        extent: CGRect
    ) -> CIImage? {
        guard levels.count == levelCount, let kernel = levelsKernel else { return nil }
        let low = min(max(min(recipe.focusFar, recipe.focusNear), 0), 1)
        let high = min(max(max(recipe.focusFar, recipe.focusNear), 0), 1)
        let arguments: [Any] = levels + [
            stretched(depth, onto: extent),
            Float(min(max(recipe.amount, 0), 1)),
            CIVector(x: low, y: high),
        ]
        return kernel.apply(extent: extent, arguments: arguments)
    }

    /// Eight levels mixed by depth into the preview's picture.
    static let levelsKernel = CoreImageKernelLibrary.kit.colorKernel(named: "lensBlurLevels")

    /// The photo where the depth falls in a band, as a premultiplied layer.
    static let sliceKernel = CoreImageKernelLibrary.kit.colorKernel(named: "lensBlurSlice")

    /// A premultiplied layer averaged over the bokeh's disc.
    static let gatherKernel = CoreImageKernelLibrary.kit.kernel(named: "lensBlurGather")
}

/// The preview's Lens Blur work, kept between slider frames (FS-03.15e §2).
///
/// Eight levels of the whole picture are built once per photo, bokeh and
/// focus band; dragging Amount only mixes them again, and every other slider
/// reuses the mixed picture as it stands — Lens Blur runs on the untouched
/// photo, so nothing they do can change it. The save does not come through
/// here: it cuts the full-resolution photo into depth layers in one pass.
///
/// A blurred level carries no detail finer than its radius, so each is kept
/// at a fraction of the frame: level k at 1/max(1, min(4, radius/3)). Eight
/// full-size RGBA copies of a 2400px preview would be ~120MB.
final class LensBlurPreviewCache {

    struct LevelsKey: Equatable {
        var identity: String
        var extent: CGRect
        var bokeh: PhotoBokehShape
        var focusFar: Double
        var focusNear: Double
    }

    private var levelsKey: LevelsKey?
    private var levels: [(image: CGImage, scale: CGFloat)] = []
    private var blendedAmount: Double?
    private var blended: CGImage?

    /// How many times the eight levels were built, and the levels mixed —
    /// what AC-57 and AC-58 count.
    private(set) var levelBuilds = 0
    private(set) var blends = 0

    init() {}

    /// The re-focused picture for a preview frame, or `base` when there is
    /// nothing to do or a kernel is missing.
    func image(
        for recipe: PhotoLensBlurRecipe,
        base: CIImage,
        depth: CIImage?,
        identity: String,
        colorSpace: CGColorSpace,
        context: CIContext
    ) -> CIImage {
        guard !recipe.isIdentity, let depth else { return base }
        let extent = base.extent
        let key = LevelsKey(
            identity: identity,
            extent: extent,
            bokeh: recipe.bokeh,
            focusFar: recipe.focusFar,
            focusNear: recipe.focusNear
        )
        if key == levelsKey, blendedAmount == recipe.amount, let blended {
            return CIImage(cgImage: blended, options: [.colorSpace: colorSpace])
        }
        if key != levelsKey {
            guard buildLevels(base: base, shape: recipe.bokeh, colorSpace: colorSpace, context: context) else {
                return base
            }
            levelsKey = key
        }
        let stretchedLevels = levels.map { level -> CIImage in
            let image = CIImage(cgImage: level.image, options: [.colorSpace: colorSpace])
            guard level.scale > 1 else { return image }
            return image
                .transformed(by: CGAffineTransform(scaleX: level.scale, y: level.scale))
                .clampedToExtent()
                .cropped(to: extent)
        }
        guard let mixed = LensBlurRenderer.blend(levels: stretchedLevels, depth: depth, recipe: recipe, extent: extent),
              let image = context.createCGImage(mixed, from: extent, format: .RGBA8, colorSpace: colorSpace)
        else { return base }
        blends += 1
        blended = image
        blendedAmount = recipe.amount
        return CIImage(cgImage: image, options: [.colorSpace: colorSpace])
    }

    private func buildLevels(
        base: CIImage,
        shape: PhotoBokehShape,
        colorSpace: CGColorSpace,
        context: CIContext
    ) -> Bool {
        let extent = base.extent
        let full = LensBlurRenderer.fullRadius(for: extent)
        var built: [(image: CGImage, scale: CGFloat)] = []
        for k in 0..<LensBlurRenderer.levelCount {
            let radius = full * CGFloat(k) / CGFloat(LensBlurRenderer.levelCount - 1)
            guard let level = LensBlurRenderer.level(base, radius: radius, shape: shape) else { return false }
            let scale = k == 0 ? 1 : max(1, min(4, radius / 3))
            let stored = scale > 1
                ? level.transformed(by: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
                : level
            let rect = stored.extent.integral
            guard let image = context.createCGImage(stored, from: rect, format: .RGBA8, colorSpace: colorSpace) else {
                return false
            }
            built.append((image, scale))
        }
        levels = built
        blended = nil
        blendedAmount = nil
        levelBuilds += 1
        return true
    }
}
