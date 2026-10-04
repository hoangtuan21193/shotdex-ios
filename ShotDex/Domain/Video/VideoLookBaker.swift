import CoreImage
import Foundation
import ShotDexKit

/// A photo look turned into what a video frame can afford (FS-12.06c §5):
/// every stage that reads one pixel at a time is baked once, when the look
/// is chosen, into a 33³ table the compositor looks up per frame.
///
/// The look's neighbourhood stages — Clarity, Texture, Sharpening, Dehaze —
/// sit between Light and Color in the photo's render order
/// (`PhotoRenderService.RenderPass`), so a look that has any of them bakes
/// into **two** tables, one either side, and the frame runs table → those
/// stages → table, in the photo's own order. A look without them bakes into
/// one. Noise Reduction, Upright, Lens Correction and the rest of the
/// geometry never reach a table: they are skipped on video.
///
/// Same lattice and same chain as the `.cube` export (`LookCubeBaker`): one
/// way of baking a look, two places that use it.
enum VideoLookBaker {
    static let dimension = LookCubeBaker.dimension

    /// Which per-pixel stages a table holds.
    enum Part: String, Sendable {
        /// Calibration and Light (Brilliance included) — before the
        /// neighbourhood stages.
        case light
        /// Color, the curve and the film look or LUT — after them.
        case colour
        /// Both, for a look with no neighbourhood stage.
        case whole
    }

    /// The Light settings a table carries. Brilliance is one of them: its
    /// highlight/shadow pass has no radius (`inputRadius` 0), so it is a
    /// per-pixel curve like the rest.
    private static let lightKeys: [WritableKeyPath<PhotoAdjustments, Double>] = [
        \.exposure, \.brilliance, \.highlights, \.shadows, \.whites, \.contrast, \.brightness, \.blackPoint,
        \.saturation, \.vibrance, \.warmth, \.tint,
    ]

    /// Whether the look reads neighbouring pixels anywhere a video frame
    /// still runs it — which is what splits its table in two.
    static func hasNeighbourStages(_ adjustments: PhotoAdjustments) -> Bool {
        adjustments.clarity != 0 || adjustments.texture != 0 || adjustments.sharpness != 0
            || adjustments.definition != 0 || adjustments.dehaze != 0
    }

    /// The parts a look's tables are cut into, in the order they run.
    static func parts(of look: PhotoEditRecipe) -> [Part] {
        hasNeighbourStages(look.adjustments) ? [.light, .colour] : [.whole]
    }

    /// The slice of `look` one table holds — everything else at identity,
    /// Lens Correction off, so `applyPreMaskStages` runs only these stages.
    static func recipe(_ part: Part, of look: PhotoEditRecipe) -> PhotoEditRecipe {
        var baked = PhotoEditRecipe.identity
        var adjustments = PhotoAdjustments()
        adjustments.lensCorrection = 0
        if part != .colour {
            for key in lightKeys { adjustments[keyPath: key] = look.adjustments[keyPath: key] }
            baked.color.calibration = look.color.calibration
        }
        if part != .light {
            let calibration = baked.color.calibration
            baked.color = look.color
            baked.color.calibration = calibration
            adjustments.blackAndWhite = look.adjustments.blackAndWhite
            baked.curve = look.curve
            baked.filter = look.filter
            baked.filterIntensity = look.filterIntensity
            baked.lutID = look.lutID
        }
        baked.adjustments = adjustments
        return baked
    }

    /// The table for one part of `look`. Nil only when Core Image cannot
    /// render the lattice at all.
    static func bake(_ part: Part, of look: PhotoEditRecipe, context: CIContext) -> CubeLUT? {
        guard let table = LookCubeBaker.renderTable(of: recipe(part, of: look), dimension: dimension, context: context)
        else { return nil }
        // A table says nothing outside 0…1, and a NaN from a degenerate
        // stage would poison every frame it touches.
        let clamped = table.map { $0.isFinite ? min(1, max(0, $0)) : 0 }
        return CubeLUT(dimension: dimension, table: clamped, title: nil)
    }
}
