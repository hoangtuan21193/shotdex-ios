import CoreGraphics

/// The Markup layer list's order (FS-03.13c §5): front-most first, the way a
/// layer list reads — the reverse of the recipe, which draws back to front.
enum EditorLayerOrder {
    /// Where a row dragged from `start` by `offset` points lands, in display
    /// indices: whole rows of `rowHeight`, kept inside the list.
    static func destination(from start: Int, offset: CGFloat, rowHeight: CGFloat, count: Int) -> Int {
        guard count > 0, rowHeight > 0 else { return start }
        let moved = Int((offset / rowHeight).rounded())
        return min(count - 1, max(0, start + moved))
    }

    /// `moveOverlays(fromDisplay:toDisplay:)`'s `toDisplay` for a row that ends
    /// at `destination`: `Array.move` counts the slot before which it drops.
    static func moveOffset(from start: Int, to destination: Int) -> Int {
        destination > start ? destination + 1 : destination
    }
}
