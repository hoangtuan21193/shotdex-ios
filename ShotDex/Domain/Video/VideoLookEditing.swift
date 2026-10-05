import Foundation
import ShotDexKit

/// Whether a look's Clarity, Texture, Sharpening and Dehaze run on video
/// (FS-12.06c §5). They run until the device measurement of AC-15 says a
/// 4K dissolve cannot hold 30 fps with them; then this flips to `.skip`,
/// the preview and the export drop all four alike, and the caption names
/// them — never one picture in the preview and another in the file.
enum VideoLookNeighbourPolicy: Sendable {
    case run, skip

    static let current: VideoLookNeighbourPolicy = .run
}

/// Where a tile tap lands (FS-12.06c §4): the whole video's slot, the clip
/// under the playhead's, or every selected clip's.
enum VideoLookTarget: String, CaseIterable, Identifiable, Sendable {
    case thisClip, selected, allClips

    var id: String { rawValue }
}

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
    ///
    /// A My Look's tile carries the store's current recipe, so tapping the
    /// tile of the look a slot was copied from takes that look **again** —
    /// the newer version if it was saved over in the photo editor (§6) —
    /// and nothing else ever updates the copy behind the user's back.
    static func chosen(_ source: VideoLook.Source, replacing current: VideoLook?) -> VideoLook {
        guard let current, isSameChoice(current.source, source) else { return VideoLook(source) }
        return VideoLook(source, amount: current.amount)
    }

    /// A tile tap, applied to `recipe` (§4). **All Clips** sets the whole
    /// video's look and clears every clip's own — what "all clips" says, so
    /// afterwards every clip wears the tapped look.
    ///
    /// **This Clip** and **Selected** write the slot of each clip in
    /// `clipIDs` — Original included, which then means "no look on this
    /// clip" — and leave the whole video's look alone.
    static func applying(
        _ source: VideoLook.Source,
        target: VideoLookTarget,
        clipIDs: [UUID] = [],
        to recipe: VideoProjectRecipe
    ) -> VideoProjectRecipe {
        var result = recipe
        switch target {
        case .allClips:
            let look = chosen(source, replacing: recipe.look)
            result.look = look.isOriginal ? nil : look
            for index in result.clips.indices { result.clips[index].look = nil }
        case .thisClip, .selected:
            for index in result.clips.indices where clipIDs.contains(result.clips[index].id) {
                result.clips[index].look = chosen(source, replacing: result.clips[index].look)
            }
        }
        return result
    }

    /// The clips a clip target writes: the selected clip, else the one under
    /// the playhead (This Clip); every selected clip (Selected).
    static func targetClipIDs(
        _ target: VideoLookTarget,
        selectedClipIDs: [UUID],
        clipUnderPlayhead: UUID?
    ) -> [UUID] {
        switch target {
        case .allClips: []
        case .thisClip: selectedClipIDs.first.map { [$0] } ?? clipUnderPlayhead.map { [$0] } ?? []
        case .selected: selectedClipIDs
        }
    }

    /// Amount shows only while there is a look to mix (FS-03.02's rule).
    static func showsAmount(_ look: VideoLook?) -> Bool {
        guard let look else { return false }
        return !look.isOriginal
    }

    /// The parts of `look` a video frame does not run, by their panel
    /// names, in panel order (§5): Noise Reduction (spatial NR flickers;
    /// video needs temporal NR), Upright and Lens Correction (a photo's
    /// geometry), and — under `.skip` — the four neighbourhood stages.
    /// Lens Correction counts only what the look sets by hand; a lens
    /// profile switched on speaks of the photo's lens, not of the look.
    static func skippedOnVideo(
        _ look: PhotoEditRecipe,
        policy: VideoLookNeighbourPolicy = .current
    ) -> [String] {
        let a = look.adjustments
        var names: [String] = []
        if policy == .skip {
            if a.texture != 0 { names.append("Texture") }
            if a.clarity != 0 { names.append("Clarity") }
            if a.dehaze != 0 { names.append("Dehaze") }
            if a.sharpness != 0 || a.definition != 0 { names.append("Sharpening") }
        }
        if a.noiseReduction != 0 || a.colorNoiseReduction != 0 { names.append("Noise Reduction") }
        let geometry = [a.geoVertical, a.geoHorizontal, a.geoRotate, a.geoAspect, a.geoScale, a.geoOffsetX, a.geoOffsetY]
        if look.upright.mode != .off || geometry.contains(where: { $0 != 0 }) { names.append("Upright") }
        let lens = [a.lensManualDistortion, a.lensManualVignetting, a.chromaticAberration, a.defringePurpleAmount, a.defringeGreenAmount]
        if lens.contains(where: { $0 != 0 }) { names.append("Lens Correction") }
        return names
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
    /// say there (§3). A look whose LUT file is gone says so:
    /// "Kodak 2383 · Missing" (§6).
    static func pillText(
        for clip: VideoClip,
        presetName: (PhotoFilter) -> String = { $0.displayName },
        lutExists: (String) -> Bool = { _ in true }
    ) -> String? {
        guard let look = clip.look else { return nil }
        let name = name(of: look, presetName: presetName)
        return isMissingLUT(look, lutExists: lutExists) ? missingName(name) : name
    }

    /// "Kodak 2383 · Missing".
    static func missingName(_ name: String) -> String {
        "\(name) · " + String(localized: "Missing", table: "VideoStudio", comment: "Video Studio: after the name of a look whose LUT file is gone — Kodak 2383 · Missing")
    }

    /// Whether `look` reads a LUT whose file is gone — chosen directly, or
    /// inside a My Look (§6). That part then renders as if it were not
    /// there; the rest of the look stays.
    static func isMissingLUT(_ look: VideoLook, lutExists: (String) -> Bool) -> Bool {
        guard let id = look.lutID else { return false }
        return !lutExists(id)
    }

    /// How many looks in the project — the whole video's and every clip's
    /// own — are missing their LUT: the Export line counts them (§6).
    static func missingLUTLookCount(in recipe: VideoProjectRecipe, lutExists: (String) -> Bool) -> Int {
        ([recipe.look] + recipe.clips.map(\.look))
            .compactMap { $0 }
            .filter { isMissingLUT($0, lutExists: lutExists) }
            .count
    }
}
