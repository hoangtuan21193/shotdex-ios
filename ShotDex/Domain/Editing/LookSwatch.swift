import Foundation
import ShotDexKit

/// The two-tone stand-in a look's tile shows until its real thumbnail has
/// rendered — or for good, when there is no picture to render it from (the
/// clip is an iCloud original and the device is offline). The look applied to
/// a lit warm tone and a shadowed cool one: made of the same maths as the real
/// thing, so the placeholder already leans the way the look does.
///
/// One rule for the photo editor's Presets and the Video Studio's Look panel.
enum LookSwatch {
    struct RGB: Equatable, Sendable {
        var red: Double, green: Double, blue: Double
    }

    static let highlight = RGB(red: 0.82, green: 0.76, blue: 0.66)
    static let shadow = RGB(red: 0.22, green: 0.25, blue: 0.32)

    /// Highlight, then shadow, for a built-in film look.
    static func colors(for filter: PhotoFilter) -> [RGB] {
        guard let look = FilmLookLibrary.look(for: filter) else { return legacyColors(for: filter) }
        let lit = look.apply(to: SIMD3(highlight.red, highlight.green, highlight.blue))
        let dark = look.apply(to: SIMD3(shadow.red, shadow.green, shadow.blue))
        return [RGB(red: lit.x, green: lit.y, blue: lit.z), RGB(red: dark.x, green: dark.y, blue: dark.z)]
    }

    /// A recipe's stand-in: its film look's when it has one, else the two
    /// tones nudged by its white balance — the one thing every look has.
    static func colors(for recipe: PhotoEditRecipe) -> [RGB] {
        if recipe.filter != .original, recipe.lutID == nil { return colors(for: recipe.filter) }
        let warmth = recipe.adjustments.warmth * 0.12
        let tint = recipe.adjustments.tint * 0.06
        func nudged(_ tone: RGB) -> RGB {
            RGB(
                red: min(1, max(0, tone.red + warmth)),
                green: min(1, max(0, tone.green - tint)),
                blue: min(1, max(0, tone.blue - warmth))
            )
        }
        return [nudged(highlight), nudged(shadow)]
    }

    /// The ten original presets are Core Image chains rather than film
    /// looks, so their stand-ins stay hand-picked.
    private static func legacyColors(for filter: PhotoFilter) -> [RGB] {
        func rgb(_ r: Double, _ g: Double, _ b: Double) -> RGB { RGB(red: r, green: g, blue: b) }
        let pink = rgb(1, 0.18, 0.33), blue = rgb(0, 0.48, 1), orange = rgb(1, 0.58, 0)
        let cyan = rgb(0.2, 0.68, 0.9), indigo = rgb(0.35, 0.34, 0.84), brown = rgb(0.64, 0.52, 0.37)
        let white = rgb(1, 1, 1), gray = rgb(0.56, 0.56, 0.58), black = rgb(0, 0, 0)
        return switch filter {
        case .vivid: [pink, blue]
        case .vividWarm: [orange, pink]
        case .vividCool: [cyan, indigo]
        case .dramatic: [black, orange]
        case .dramaticWarm: [brown, orange]
        case .dramaticCool: [black, blue]
        case .mono: [white, gray]
        case .silvertone: [rgb(0.78, 0.78, 0.79), white]
        case .noir: [black, white]
        default: [gray, rgb(0.6, 0.6, 0.6)]
        }
    }
}
