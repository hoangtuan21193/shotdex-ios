import CoreImage
import Foundation
import ShotDexKit

/// One look, ready for the compositor: the recipe its tables bake from,
/// the keys of those tables, and what runs per frame — worked out once per
/// video composition on the main actor, never per frame.
struct VideoLookPlan: Sendable {
    /// The look as it renders: a LUT whose file is gone is taken out
    /// (§6 — that part renders as if it were not there; the rest stays).
    let recipe: PhotoEditRecipe
    let parts: [VideoLookBaker.Part]
    let keys: [VideoLookTableCache.Key]
    /// Clarity, Texture, Sharpening and Dehaze, run on every frame between
    /// the two tables (no Noise Reduction: skipped on video). Nil when the
    /// look has none, or when `VideoLookNeighbourPolicy` turns them off.
    let neighbours: PhotoAdjustments?
    /// The post-crop vignette, on the clip's own frame.
    let vignette: (adjustments: PhotoAdjustments, style: PhotoVignetteStyle)?
    /// Grain: amount, size, roughness.
    let grain: (amount: Double, size: Double, roughness: Double)?
    let amount: Double

    /// Nil for Original, or for a look with nothing left to render.
    init?(
        _ look: VideoLook,
        lutExists: (String) -> Bool,
        policy: VideoLookNeighbourPolicy = .current
    ) {
        guard !look.isOriginal else { return nil }
        var recipe = look.recipe
        if let id = recipe.lutID, !lutExists(id) {
            recipe.lutID = nil
        }
        guard !recipe.isIdentity else { return nil }
        let adjustments = recipe.adjustments
        if policy == .run, VideoLookBaker.hasNeighbourStages(adjustments) {
            var neighbours = PhotoAdjustments()
            neighbours.lensCorrection = 0
            for key: WritableKeyPath<PhotoAdjustments, Double> in [
                \.sharpness, \.sharpenRadius, \.sharpenDetail, \.sharpenMasking,
                \.definition, \.texture, \.clarity, \.dehaze,
            ] {
                neighbours[keyPath: key] = adjustments[keyPath: key]
            }
            self.neighbours = neighbours
            parts = [.light, .colour]
        } else {
            neighbours = nil
            parts = [.whole]
        }
        vignette = abs(adjustments.vignette) > 0.0001 ? (adjustments, recipe.vignetteStyle) : nil
        grain = adjustments.grain > 0 ? (adjustments.grain, adjustments.grainSize, adjustments.grainRoughness) : nil
        self.recipe = recipe
        keys = parts.map { VideoLookTableCache.Key($0, of: recipe) }
        amount = min(1, max(0, look.amount))
    }

    /// Whether a LUT file is on disk, from its id alone — what the
    /// compositor's recipe asks when it is built.
    static func lutFileExists(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: ImportedLUTFiles.fileURL(for: id).path)
    }
}

/// Where a frame is, for the parts of a look that change from frame to
/// frame or with the frame's size.
struct VideoLookFrame: Sendable {
    /// Neighbourhood radii are set for a 1920-long frame and scale with it,
    /// so the 1280 preview and a 3840 export are one picture (§5).
    var radiusScale: Double = 1
    /// Which frame on a 1/30 s clock: the grain pattern moves with it.
    var index: Int = 0

    static let referenceLongEdge: Double = 1920

    init(radiusScale: Double = 1, index: Int = 0) {
        self.radiusScale = radiusScale
        self.index = index
    }

    /// The frame at `seconds` on a canvas of `canvas` size.
    init(canvas: CGSize, seconds: Double) {
        radiusScale = max(canvas.width, canvas.height) / Self.referenceLongEdge
        index = Int((seconds * 30).rounded(.down))
    }

    /// Where the grain's noise is read from, a long way apart from one frame
    /// to the next so neighbouring frames never share a pattern.
    var grainOffset: CGPoint {
        guard index != 0 else { return .zero }
        return CGPoint(x: Double((index &* 7_919) % 4_093), y: Double((index &* 104_729) % 4_091))
    }
}

/// Runs a look on one clip's frame (FS-12.06c §5): a lookup per baked table.
enum VideoLookRenderer {
    /// The look on `input`, one clip's frame, in the photo's order: Light
    /// table → Clarity…Dehaze → Color table → vignette → grain, then mixed
    /// over the frame at Amount.
    static func apply(
        _ plan: VideoLookPlan,
        to input: CIImage,
        frame: VideoLookFrame = VideoLookFrame(),
        cache: VideoLookTableCache = .shared
    ) -> CIImage {
        // Amount 0 is no look at all — not a look mixed in at nothing.
        guard plan.amount > 0.001 else { return input }
        var image = input
        for (part, key) in zip(plan.parts, plan.keys) {
            if part == .colour, let neighbours = plan.neighbours {
                image = PhotoRenderService.applyDetail(neighbours, to: image, radiusScale: frame.radiusScale)
                image = PhotoRenderService.applyDehazePass(neighbours, to: image, radiusScale: frame.radiusScale)
                    .cropped(to: input.extent)
            }
            guard let table = cache.table(part, of: plan.recipe, key: key) else { continue }
            image = lookUp(table, image)
        }
        if let vignette = plan.vignette {
            // The clip's own frame, not the canvas with its bars (§5).
            image = PhotoRenderService.applyVignette(vignette.adjustments, style: vignette.style, to: image)
        }
        if let grain = plan.grain {
            image = PhotoRenderService.applyGrain(
                grain.amount, size: grain.size, roughness: grain.roughness,
                offset: frame.grainOffset, to: image
            )
        }
        image = image.cropped(to: input.extent)
        return mixed(image, over: input, amount: plan.amount)
    }

    /// Amount (§4): the **whole** look — tables, neighbourhood stages,
    /// vignette, grain — laid over the frame as it was before the look, at
    /// that strength. Unlike the photo editor's, which mixes only the film
    /// look or LUT: on video a look is one closed block with no slider for
    /// the rest of it.
    static func mixed(_ look: CIImage, over before: CIImage, amount: Double) -> CIImage {
        guard amount < 0.999 else { return look }
        return PhotoRenderService.filtered(
            "CIMix",
            image: look,
            values: [kCIInputBackgroundImageKey: before, "inputAmount": amount]
        ).cropped(to: before.extent)
    }

    /// One `CIColorCubeWithColorSpace` pass in sRGB — the space the table
    /// was baked in — over a frame clamped to the table's 0…1.
    static func lookUp(_ table: VideoLookTableCache.Table, _ image: CIImage) -> CIImage {
        guard let space = sRGB else { return image }
        return PhotoRenderService.filtered("CIColorClamp", image: image)
            .applyingFilter("CIColorCubeWithColorSpace", parameters: [
                "inputCubeDimension": table.dimension,
                "inputCubeData": table.data,
                "inputColorSpace": space,
            ])
            .cropped(to: image.extent)
    }

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)
}
