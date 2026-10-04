import CoreImage
import Foundation
import ShotDexKit

/// One look, ready for the compositor: the recipe its tables bake from, and
/// the keys of those tables — worked out once per video composition on the
/// main actor, never per frame.
struct VideoLookPlan: Sendable {
    /// The look as it renders: a LUT whose file is gone is taken out
    /// (§6 — that part renders as if it were not there; the rest stays).
    let recipe: PhotoEditRecipe
    let parts: [VideoLookBaker.Part]
    let keys: [VideoLookTableCache.Key]
    let amount: Double

    /// Nil for Original, or for a look with nothing left to render.
    init?(_ look: VideoLook, lutExists: (String) -> Bool) {
        guard !look.isOriginal else { return nil }
        var recipe = look.recipe
        if let id = recipe.lutID, !lutExists(id) {
            recipe.lutID = nil
        }
        guard !recipe.isIdentity else { return nil }
        self.recipe = recipe
        parts = VideoLookBaker.parts(of: recipe)
        keys = parts.map { VideoLookTableCache.Key($0, of: recipe) }
        amount = min(1, max(0, look.amount))
    }

    /// Whether a LUT file is on disk, from its id alone — what the
    /// compositor's recipe asks when it is built.
    static func lutFileExists(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: ImportedLUTFiles.fileURL(for: id).path)
    }
}

/// Runs a look on one clip's frame (FS-12.06c §5): a lookup per baked table.
enum VideoLookRenderer {
    static func apply(
        _ plan: VideoLookPlan,
        to input: CIImage,
        cache: VideoLookTableCache = .shared
    ) -> CIImage {
        // Amount 0 is no look at all — not a look mixed in at nothing.
        guard plan.amount > 0.001 else { return input }
        var image = input
        for (part, key) in zip(plan.parts, plan.keys) {
            guard let table = cache.table(part, of: plan.recipe, key: key) else { continue }
            image = lookUp(table, image)
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
