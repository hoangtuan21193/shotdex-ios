import Foundation
import ShotDexKit

/// The rules of the Look slots (FS-12.06c §4, §6), apart from any view or
/// model so each one is tested on its own.
enum VideoLookEditing {
    /// The look `clip` renders with: its own when it has one — Original
    /// included, which then means "no look on this clip" — else the whole
    /// video's. Nil when nothing is to be rendered.
    ///
    /// The clip's look **replaces** the video's; the two never stack, the
    /// way two film looks are never stacked in the photo editor.
    static func effectiveLook(for clip: VideoClip, in recipe: VideoProjectRecipe) -> VideoLook? {
        let look = clip.look ?? recipe.look
        guard let look, !look.isOriginal else { return nil }
        return look
    }

    /// Whether two looks are the same choice — the same preset, the same
    /// LUT, or copies of the same My Look (whatever version).
    static func isSameChoice(_ a: VideoLook.Source, _ b: VideoLook.Source) -> Bool {
        switch (a, b) {
        case let (.preset(x), .preset(y)): x == y
        case let (.lut(x, _), .lut(y, _)): x == y
        case let (.myLook(x, _, _, _), .myLook(y, _, _, _)): x == y
        default: false
        }
    }

    /// The look a tile tap puts in a slot (§3, FS-03.02): a new look starts
    /// at Amount 100; the tile already chosen keeps the Amount it had.
    static func chosen(_ source: VideoLook.Source, replacing current: VideoLook?) -> VideoLook {
        guard let current, isSameChoice(current.source, source) else { return VideoLook(source) }
        return VideoLook(source, amount: current.amount)
    }

    /// Amount shows only while there is a look to mix (FS-03.02's rule).
    static func showsAmount(_ look: VideoLook?) -> Bool {
        guard let look else { return false }
        return !look.isOriginal
    }

    /// What a look is called on screen: a preset by the name the editor
    /// shows for it (the user may have renamed it), a My Look or LUT by the
    /// name it had when it was chosen.
    static func name(of look: VideoLook, presetName: (PhotoFilter) -> String = { $0.displayName }) -> String {
        switch look.source {
        case let .preset(filter): presetName(filter)
        case let .myLook(_, name, _, _): name
        case let .lut(_, name): name
        }
    }

    /// The pill on a clip's band in the V1 lane: only a clip with a look of
    /// its own wears one — a clip following the whole video has nothing to
    /// say there (§3).
    static func pillText(
        for clip: VideoClip,
        presetName: (PhotoFilter) -> String = { $0.displayName }
    ) -> String? {
        guard let look = clip.look else { return nil }
        return name(of: look, presetName: presetName)
    }
}
