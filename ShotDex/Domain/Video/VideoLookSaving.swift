import Foundation
import ShotDexKit

/// What Save as Look… puts in My Looks (FS-12.06c §6b): the whole video's
/// look and grade, cut down to what a photo look can hold — one set of
/// settings and one film look or LUT — plus, by their panel names, the parts
/// of the video's grade it could not hold.
struct VideoPhotoLookCut: Equatable {
    /// Look-only (`EditorSyncScope.look`), ready for `LookPresetStore.save`.
    var recipe: PhotoEditRecipe
    /// What stays in the video, in this order: Input Transform, Amount,
    /// settings the look already sets ("Exposure in Node 1"), the nodes
    /// left out, clips' own looks.
    var notSaved: [String]

    /// Nothing a photo would show: Save as Look… is dimmed (the store
    /// refuses an identity look too — a tile that does nothing reads as broken).
    var isEmpty: Bool { recipe.isIdentity }
}

enum VideoLookSaving {
    /// The photo look of `recipe` (§6b).
    ///
    /// - The whole video's look: a film look or a LUT goes in at its
    ///   Amount (on a photo, Amount is the film look's or LUT's strength —
    ///   the same mix). A My Look goes in as its settings; an Amount under
    ///   100 cannot be held, because a photo's Amount fades only the film
    ///   look or LUT, not a whole look.
    /// - The grade: the first node that changes pixels and has no window
    ///   gives its Light, Color and Curve. A setting the My Look already
    ///   sets keeps the look's value; the node's is named as not saved.
    ///   Every other node that changes pixels — after the first, or limited
    ///   to a window (a photo look holds no masks) — is named.
    /// - Never: the Input Transform (it undoes the camera's encoding: the
    ///   footage's, not the look's), clips' own looks (they are not the
    ///   whole video's), anything outside the look cut.
    static func photoLook(of recipe: VideoProjectRecipe) -> VideoPhotoLookCut {
        var photo = PhotoEditRecipe.identity
        var notSaved: [String] = []
        if recipe.inputTransform != .none { notSaved.append(Copy.inputTransform) }

        var look = PhotoEditRecipe.identity
        if let slot = recipe.look, !slot.isOriginal {
            switch slot.source {
            case let .preset(filter):
                look.filter = filter
                look.filterIntensity = slot.amount
            case let .lut(id, _):
                look.lutID = id
                look.filterIntensity = slot.amount
            case let .myLook(_, _, _, saved):
                look = EditorSyncScope.look.apply(saved, onto: .identity)
                if slot.amount < 0.995 { notSaved.append(Copy.amount) }
            }
        }
        photo = look

        let changing = recipe.nodes.enumerated().filter { $0.element.isEnabled && !$0.element.isIdentity }
        let carried = changing.first { $0.element.masks.isEmpty }
        if let carried {
            let node = carried.element
            let nodeName = node.displayName(at: carried.offset)
            var collisions: [String] = []
            if look.adjustments.isIdentity {
                photo.adjustments = node.adjustments
            } else {
                for kind in PhotoAdjustmentKind.allCases {
                    let neutral = PhotoAdjustments.zero[kind]
                    guard node.adjustments[kind] != neutral else { continue }
                    if look.adjustments[kind] == neutral {
                        photo.adjustments[kind] = node.adjustments[kind]
                    } else if look.adjustments[kind] != node.adjustments[kind] {
                        collisions.append(Copy.setting(kind.displayName, inNode: nodeName))
                    }
                }
            }
            if !node.color.isIdentity {
                if look.color.isIdentity { photo.color = node.color } else if look.color != node.color { collisions.append(Copy.color(inNode: nodeName)) }
            }
            if !node.curve.isIdentity {
                if look.curve.isIdentity { photo.curve = node.curve } else if look.curve != node.curve { collisions.append(Copy.curve(inNode: nodeName)) }
            }
            notSaved += collisions
        }
        for (index, node) in changing where index != carried?.offset {
            notSaved.append(node.displayName(at: index))
        }
        if recipe.clips.contains(where: { $0.look != nil }) { notSaved.append(Copy.clipLooks) }

        return VideoPhotoLookCut(recipe: EditorSyncScope.look.apply(photo, onto: .identity), notSaved: notSaved)
    }

    private enum Copy {
        static let table = "VideoStudio"
        static var inputTransform: String {
            String(localized: "Input Transform", table: table, comment: "Video Studio Save as Look: the de-log step, which a photo look does not keep")
        }
        static var amount: String {
            String(localized: "Amount", table: table, comment: "Video Studio Look panel: how much of the chosen look is mixed in, 0–100")
        }
        static func color(inNode node: String) -> String {
            String(localized: "Color in \(node)", table: table, comment: "Video Studio Save as Look: a node's colour settings, which the look already sets — e.g. Color in Node 1")
        }
        static func curve(inNode node: String) -> String {
            String(localized: "Curve in \(node)", table: table, comment: "Video Studio Save as Look: a node's tone curve, which the look already sets — e.g. Curve in Node 1")
        }
        static var clipLooks: String {
            String(localized: "clips' own looks", table: table, comment: "Video Studio Save as Look: the looks single clips have, which stay in the video")
        }
        static func setting(_ setting: String, inNode node: String) -> String {
            String(localized: "\(setting) in \(node)", table: table, comment: "Video Studio Save as Look: a node's setting the look already sets — e.g. Exposure in Node 1")
        }
    }
}
