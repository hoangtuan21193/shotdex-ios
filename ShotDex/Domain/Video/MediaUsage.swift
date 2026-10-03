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

    // MARK: In Video (FS-12.09 §4)

    /// One row of In Video: one use, where it sits.
    struct Row: Equatable, Identifiable {
        enum Kind: Equatable {
            /// A clip, by its 1-based place on the track.
            case clip(VideoClipKind, number: Int)
            case sticker
        }

        /// The clip's or the overlay's id — what a tap selects.
        let id: UUID
        let assetID: String
        let kind: Kind
        let start: Double
        let end: Double

        /// "0:03–0:09", whole seconds.
        var span: String { "\(MediaUsage.clock(start))–\(MediaUsage.clock(end))" }

        func contains(_ time: Double) -> Bool { time >= start && time < end }
    }

    /// Every use in timeline order — by where it starts; a clip before a
    /// sticker that starts with it.
    static func rows(in recipe: VideoProjectRecipe, totalDuration: Double) -> [Row] {
        let placements = MediaInsertMath.placements(of: recipe)
        var rows: [Row] = []
        for (index, clip) in recipe.clips.enumerated() where placements.indices.contains(index) {
            rows.append(Row(
                id: clip.id, assetID: clip.assetID, kind: .clip(clip.kind, number: index + 1),
                start: placements[index].start, end: placements[index].end
            ))
        }
        let total = max(totalDuration, placements.last?.end ?? 0)
        for timed in recipe.overlays where timed.overlay.kind == .image {
            guard let id = timed.overlay.imageAssetIdentifier else { continue }
            let end = timed.duration.map { timed.start + $0 } ?? total
            rows.append(Row(id: timed.id, assetID: id, kind: .sticker, start: timed.start, end: end))
        }
        return rows.enumerated().sorted { lhs, rhs in
            if lhs.element.start != rhs.element.start { return lhs.element.start < rhs.element.start }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// "m:ss" of whole seconds, rounded.
    static func clock(_ seconds: Double) -> String {
        let whole = Int(max(0, seconds).rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
