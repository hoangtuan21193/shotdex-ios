import Photos
import UIKit

/// The pixel size a full-width photo grid asks PhotoKit for, in one place.
///
/// `PhotoLibraryService` caches finished thumbnails per asset *and* requested
/// width, so anything that wants to warm a grid ahead of time (the Collections
/// tab warming an album before it is opened) has to request the exact same size
/// the grid will — a rendition off by a pixel is a separate cache entry and
/// paints as a soft tile. Both sides go through here so they cannot drift.
enum GridThumbnailTarget {
    /// Point size of one square tile: full width minus inter-item spacing,
    /// floored to whole pixels so rows land on the pixel grid.
    static func cellSize(width: CGFloat, columns: Int) -> CGSize {
        let spacing: CGFloat = 2
        let scale = UIScreen.main.scale
        let raw = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let side = max(1, (raw * scale).rounded(.down) / scale)
        return CGSize(width: side, height: side)
    }

    /// Match the physical display scale. Capping a 3x phone at 2x saved decode
    /// memory but left one- and two-column thumbnails visibly soft compared
    /// with Photos.
    static func thumbnailSize(cellPointWidth: CGFloat) -> CGSize {
        let side = cellPointWidth * UIScreen.main.scale
        return CGSize(width: side, height: side)
    }

    /// What a grid filling the screen at `columns` will request. Used by
    /// prewarming, which has no collection view to measure.
    static func fullWidthThumbnailSize(columns: Int) -> CGSize {
        thumbnailSize(
            cellPointWidth: cellSize(
                width: UIScreen.main.bounds.width,
                columns: GridDensity.clamped(columns)
            ).width
        )
    }

    /// Tiles to warm ahead of a grid that has not been opened yet: enough to
    /// cover the first screenful, capped so a screen full of album tokens
    /// cannot queue thousands of decodes.
    static func prewarmCount(columns: Int) -> Int {
        min(30, max(6, GridDensity.clamped(columns) * 4))
    }
}
