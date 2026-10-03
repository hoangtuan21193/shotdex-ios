import Foundation
import ShotDexKit

/// What of the library is already in a video (FS-12.09 §4): how many times
/// each library item is used, and the mark its Media cell wears.
///
/// One rule (chốt 2026-10-03): **count = rows = uses**. Every clip and every
/// sticker made from a library item is one use and one row of In Video, even
/// when two of them are the same photo; a clip split in two is two uses. The
/// "In Video · n" tab counts the same rows, so the tab and the list never
/// disagree. A sticker with no library id (made before stickers kept one) is
/// not a use: there is nothing in the grid to mark.
enum MediaUsage {
    /// The mark on a Media cell.
    enum Badge: Equatable {
        case none
        /// Used once: a white 19pt disc with a black ✓.
        case check
        /// Used more than once: a white capsule "×2", "×3"…
        case times(Int)
    }

    static func badge(forUses uses: Int) -> Badge {
        switch uses {
        case ..<1: .none
        case 1: .check
        default: .times(uses)
        }
    }

    /// Uses by library id: one per clip, one per sticker that carries an id.
    static func uses(in recipe: VideoProjectRecipe) -> [String: Int] {
        var uses: [String: Int] = [:]
        for clip in recipe.clips {
            uses[clip.assetID, default: 0] += 1
        }
        for timed in recipe.overlays where timed.overlay.kind == .image {
            guard let id = timed.overlay.imageAssetIdentifier else { continue }
            uses[id, default: 0] += 1
        }
        return uses
    }

    /// The number on the In Video tab: every use.
    static func useCount(in recipe: VideoProjectRecipe) -> Int {
        uses(in: recipe).values.reduce(0, +)
    }
}
