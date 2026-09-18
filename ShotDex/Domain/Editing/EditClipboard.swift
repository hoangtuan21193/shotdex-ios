import Foundation
import ShotDexKit

/// The "copy edits / paste edits" clipboard: one recipe, kept between photos
/// and across launches.
///
/// What travels is deliberately **not** the whole recipe. Tone, colour, the
/// curve, the filter and its strength describe a *look*, and a look is the
/// thing worth carrying from one photo to the next. Crop, masks, the drawing
/// and the overlay layers are about one particular frame: pasting a crop would
/// reframe a photo the user never framed, and pasting a mask would brighten a
/// region that on this photo is somebody's face.
///
/// That split is also what Photos and Lightroom settled on, for the same
/// reason.
@MainActor
@Observable
final class EditClipboard {
    private enum Key {
        static let recipe = "edits.clipboard"
    }

    private let defaults: UserDefaults
    private(set) var recipe: PhotoEditRecipe?

    /// Something worth pasting. A copied identity recipe is not offered: the
    /// paste would do nothing and the row would look broken.
    var hasContent: Bool {
        guard let recipe else { return false }
        return !recipe.isIdentity
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.recipe) {
            recipe = try? JSONDecoder().decode(PhotoEditRecipe.self, from: data)
        }
    }

    /// Keeps the look out of `source`, and nothing else.
    func copy(from recipe: PhotoEditRecipe) {
        let look = Self.look(of: recipe)
        self.recipe = look
        defaults.set(try? JSONEncoder().encode(look), forKey: Key.recipe)
    }

    /// Lays the copied look over `recipe`, leaving its framing and its layers
    /// alone.
    func paste(onto recipe: PhotoEditRecipe) -> PhotoEditRecipe {
        guard let copied = self.recipe else { return recipe }
        var result = recipe
        result.adjustments = copied.adjustments
        result.color = copied.color
        result.curve = copied.curve
        result.filter = copied.filter
        result.filterIntensity = copied.filterIntensity
        return result
    }

    func clear() {
        recipe = nil
        defaults.removeObject(forKey: Key.recipe)
    }

    /// Everything about how the photo looks, with nothing about which photo it
    /// is or how it is framed.
    static func look(of recipe: PhotoEditRecipe) -> PhotoEditRecipe {
        var look = PhotoEditRecipe.identity
        look.adjustments = recipe.adjustments
        look.color = recipe.color
        look.curve = recipe.curve
        look.filter = recipe.filter
        look.filterIntensity = recipe.filterIntensity
        return look
    }
}
