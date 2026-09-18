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
        let scale = ActiveDisplay.scale
        let raw = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let side = max(1, (raw * scale).rounded(.down) / scale)
        return CGSize(width: side, height: side)
    }

    /// Match the physical display scale. Capping a 3x phone at 2x saved decode
    /// memory but left one- and two-column thumbnails visibly soft compared
    /// with Photos.
    static func thumbnailSize(cellPointWidth: CGFloat) -> CGSize {
        let side = cellPointWidth * ActiveDisplay.scale
        return CGSize(width: side, height: side)
    }

    /// What a grid filling the window at `columns` will request. Used by
    /// prewarming, which has no collection view to measure — so it resolves
    /// the density against the window width the same way the grid resolves it
    /// against its own (see `GridDensity.columns(forDensity:width:)`),
    /// otherwise a regular-width display would warm renditions at a cell size
    /// the grid never draws and every warmed tile would miss the cache.
    static func fullWidthThumbnailSize(columns: Int) -> CGSize {
        let width = ActiveDisplay.size.width
        let isRegularWidth = ActiveDisplay.windowScene?
            .traitCollection.horizontalSizeClass == .regular
        return thumbnailSize(
            cellPointWidth: cellSize(
                width: width,
                columns: GridDensity.columns(
                    forDensity: columns, width: width, isRegularWidth: isRegularWidth
                )
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
