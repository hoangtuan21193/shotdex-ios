import UIKit

/// One section as the layout sees it: how many cells, and whether a header
/// row sits above them.
struct PhotoGridLayoutSection: Equatable {
    let itemCount: Int
    let hasHeader: Bool
}

/// The photo grid's layout: a uniform square grid whose frames are arithmetic
/// (row and column from the item index), so content size and any item's
/// frame are O(1) no matter how many photos there are — and whose column
/// count can be a *fraction* while the user pinches.
///
/// **Why not `UICollectionViewFlowLayout` + `UICollectionViewTransitionLayout`.**
/// The transition layout interpolates between exactly two layouts, one step
/// at a time, and nothing may start until UIKit's completion callback for the
/// previous step has fired. A long pinch from 3 to 6 columns was three
/// separate transitions with a dead window between each — the hitch the user
/// felt. It also interpolates the content offset on its own, so the photo
/// under the fingers drifted.
///
/// **What this does instead (the Photos mechanic).** A zoom is a real number
/// of columns `r`. For `r` between two integers the layout blends every
/// frame between the layout at `floor(r)` and the one at `ceil(r)`; when `r`
/// crosses an integer the pair just shifts, with no gap and no gate. The
/// owner keeps one photo — the one under the pinch centroid — pinned to the
/// fingers by setting the content offset from that photo's blended frame each
/// frame. On release the owner eases `r` onto the nearest committed count.
///
/// The blend is exact for the pinned photo and its neighbours and is only
/// ever *seen* within a screen of them, which is why the visible-rect query
/// can take the union of what is visible in each end layout (see
/// `layoutAttributesForElements`) rather than walking the list.
final class PhotoGridLayout: UICollectionViewLayout {

    static let spacing: CGFloat = 2
    static let headerHeight: CGFloat = 32

    // MARK: Inputs

    /// Set by the owner alongside its data source, before `reloadData` or
    /// inside the batch update that changes them.
    var sections: [PhotoGridLayoutSection] = [] {
        didSet {
            guard sections != oldValue else { return }
            dropLevels()
            invalidateLayout()
        }
    }

    /// Footer under the last section; 0 for none.
    var footerHeight: CGFloat = 0 {
        didSet {
            guard footerHeight != oldValue else { return }
            dropLevels()
            invalidateLayout()
        }
    }

    /// Forgets every cached level. The owner calls it when the photo list is
    /// replaced by one of the same shape, since one-column heights come from
    /// the photos themselves and a same-count swap would otherwise keep the
    /// old ones.
    func invalidateGeometry() {
        dropLevels()
        invalidateLayout()
    }

    /// Headers stick to the top of the visible bounds while their section
    /// scrolls under them.
    var pinsHeaders = false

    /// Height of the cell for a flat photo index at *one* column, where each
    /// cell takes the photo's own aspect ratio. Nil keeps 1 column square.
    /// Called once per photo per width change, never per frame.
    var oneColumnHeight: ((_ flatIndex: Int, _ width: CGFloat) -> CGFloat)?

    /// Width ÷ height of a photo, for the aspect-ratio grid. Same contract as
    /// `oneColumnHeight`: read once per photo per level, never per frame.
    var aspectRatio: ((_ flatIndex: Int) -> CGFloat)?

    /// Photos' aspect-ratio grid: rows of frames at their own shape, each row
    /// filling the width. Off is the square grid.
    ///
    /// Only above one column — one column is already the photo's own shape,
    /// full width, and justifying it would put two portraits side by side in
    /// what the user asked to be a one-up view.
    var showsAspectTiles = false {
        didSet {
            guard showsAspectTiles != oldValue else { return }
            dropLevels()
            invalidateLayout()
        }
    }

    // MARK: Zoom state

    /// The committed column count. Equal to both ends of the blend when no
    /// zoom is in flight.
    private(set) var columns = 3
    private(set) var zoomFrom = 3
    private(set) var zoomTo = 3
    /// 0 = `zoomFrom`'s layout, 1 = `zoomTo`'s.
    private(set) var zoomProgress: CGFloat = 0
    /// Flat index of the photo pinned under the fingers, which is where the
    /// blend is exact and around which the visible-rect query is built.
    private(set) var zoomAnchorFlatIndex: Int?

    var isZooming: Bool { zoomFrom != zoomTo }

    /// The live column count as a real number.
    var fractionalColumns: CGFloat {
        CGFloat(zoomFrom) + (CGFloat(zoomTo) - CGFloat(zoomFrom)) * zoomProgress
    }

    /// Commits an integer column count, ending any blend.
    func setColumns(_ count: Int) {
        let count = max(1, count)
        guard count != columns || isZooming else { return }
        columns = count
        zoomFrom = count
        zoomTo = count
        zoomProgress = 0
        zoomAnchorFlatIndex = nil
        invalidateLayout()
    }

    /// Positions every frame at the blend of the `floor(r)` and `ceil(r)`
    /// layouts, exact at `anchorFlatIndex`.
    func setZoom(columns r: CGFloat, anchorFlatIndex: Int?) {
        let r = max(1, r)
        let from = Int(r.rounded(.down))
        let to = Int(r.rounded(.up))
        zoomFrom = from
        zoomTo = to
        zoomProgress = to == from ? 0 : r - CGFloat(from)
        zoomAnchorFlatIndex = anchorFlatIndex
        invalidateLayout()
    }

    // MARK: Level geometry

    /// Everything about the grid at one integer column count.
    private struct Level {
        let columns: Int
        let side: CGFloat
        /// Horizontal stride between cell origins. Leftover width from the
        /// pixel-floored side is spread across the gaps, like flow layout.
        let stride: CGFloat
        /// Per section: y of the section's first row (below its header).
        let itemTops: [CGFloat]
        /// Per section: y where the section starts (its header, if any).
        let sectionTops: [CGFloat]
        let sectionHeights: [CGFloat]
        /// Per section at one column: cumulative row offsets, `count + 1`
        /// entries, `nil` at every other count (rows are uniform there).
        let rowOffsets: [[CGFloat]]?
        /// Per section, the justified rows of the aspect grid. Nil for the
        /// square grid, which needs no per-item storage at all.
        let aspect: [AspectSection]?
        let contentHeight: CGFloat

        var rowStride: CGFloat { side + PhotoGridLayout.spacing }
    }

    /// One section's justified rows, flattened into arrays the frame lookup
    /// can index directly.
    ///
    /// Three small arrays rather than one `[CGRect]` per item: a library of
    /// 55k photos costs about 1 MB this way and three times that as rects,
    /// and the layout caches a level per column count.
    private struct AspectSection {
        /// `rows.count + 1` cumulative tops, so a row's height is the
        /// difference and the last entry is the section's item height.
        var rowTops: [CGFloat]
        var rowHeights: [CGFloat]
        /// First item of each row, `rows.count + 1` entries, so a row's items
        /// are a range and the visible query never walks the section.
        var rowStart: [Int]
        /// Which row each item is in, and where it sits across that row.
        var itemRow: [Int32]
        var itemX: [CGFloat]
        var itemWidth: [CGFloat]
    }

    private var levels: [Int: Level] = [:]
    private var preparedWidth: CGFloat = 0
    private var preparedScale: CGFloat = 0

    private func dropLevels() {
        levels.removeAll()
    }

    private var contentWidth: CGFloat {
        guard let collectionView else { return 0 }
        return collectionView.bounds.width
            - collectionView.adjustedContentInset.left
            - collectionView.adjustedContentInset.right
    }

    private var displayScale: CGFloat {
        collectionView?.traitCollection.displayScale ?? 1
    }

    private func level(_ columns: Int) -> Level {
        if let cached = levels[columns] { return cached }
        let built = buildLevel(columns: columns)
        levels[columns] = built
        return built
    }

    private func buildLevel(columns: Int) -> Level {
        let width = preparedWidth
        let scale = max(1, preparedScale)
        let side = GridThumbnailTarget.cellSize(width: width, columns: columns).width
        let stride: CGFloat
        if columns > 1 {
            stride = (width - side) / CGFloat(columns - 1)
        } else {
            stride = width
        }
        let usesAspect = columns == 1 && oneColumnHeight != nil
        // The aspect grid is the justified layout; one column keeps its own
        // full-width path above.
        let usesJustified = showsAspectTiles && columns > 1 && aspectRatio != nil

        var sectionTops: [CGFloat] = []
        var itemTops: [CGFloat] = []
        var sectionHeights: [CGFloat] = []
        var rowOffsets: [[CGFloat]]? = usesAspect ? [] : nil
        var aspectSections: [AspectSection]? = usesJustified ? [] : nil
        var y: CGFloat = 0
        var flat = 0
        for (index, section) in sections.enumerated() {
            sectionTops.append(y)
            let header = section.hasHeader ? Self.headerHeight : 0
            let itemsTop = y + header
            itemTops.append(itemsTop)
            var itemsHeight: CGFloat = 0
            if usesJustified, let ratioFor = aspectRatio {
                let built = buildAspectSection(
                    itemCount: section.itemCount,
                    flatStart: flat,
                    width: width,
                    targetHeight: side,
                    ratioFor: ratioFor
                )
                itemsHeight = built.rowTops.last ?? 0
                aspectSections?.append(built)
            } else if usesAspect, let heightFor = oneColumnHeight {
                var offsets: [CGFloat] = [0]
                offsets.reserveCapacity(section.itemCount + 1)
                var running: CGFloat = 0
                for item in 0..<section.itemCount {
                    let h = max(1, (heightFor(flat + item, width) * scale).rounded(.down) / scale)
                    running += h + Self.spacing
                    offsets.append(running)
                }
                rowOffsets?.append(offsets)
                itemsHeight = section.itemCount > 0 ? running - Self.spacing : 0
            } else if section.itemCount > 0 {
                let rows = (section.itemCount + columns - 1) / columns
                itemsHeight = CGFloat(rows) * (side + Self.spacing) - Self.spacing
            }
            var height = header + itemsHeight
            if index == sections.count - 1 { height += footerHeight }
            sectionHeights.append(height)
            y += height
            flat += section.itemCount
        }
        return Level(
            columns: columns,
            side: side,
            stride: stride,
            itemTops: itemTops,
            sectionTops: sectionTops,
            sectionHeights: sectionHeights,
            rowOffsets: rowOffsets,
            aspect: aspectSections,
            contentHeight: y
        )
    }

    /// Justified rows for one section, pre-flattened for O(1) frame lookup.
    private func buildAspectSection(
        itemCount: Int,
        flatStart: Int,
        width: CGFloat,
        targetHeight: CGFloat,
        ratioFor: (Int) -> CGFloat
    ) -> AspectSection {
        guard itemCount > 0 else {
            return AspectSection(
                rowTops: [0], rowHeights: [], rowStart: [0],
                itemRow: [], itemX: [], itemWidth: []
            )
        }
        var ratios: [CGFloat] = []
        ratios.reserveCapacity(itemCount)
        for item in 0..<itemCount {
            ratios.append(ratioFor(flatStart + item))
        }
        let rows = JustifiedGridRows.rows(
            aspectRatios: ratios,
            width: width,
            targetHeight: targetHeight,
            spacing: Self.spacing
        )

        var rowTops: [CGFloat] = [0]
        var rowHeights: [CGFloat] = []
        var rowStart: [Int] = []
        var itemRow = [Int32](repeating: 0, count: itemCount)
        var itemX = [CGFloat](repeating: 0, count: itemCount)
        var itemWidth = [CGFloat](repeating: 0, count: itemCount)
        var y: CGFloat = 0
        for (rowIndex, row) in rows.enumerated() {
            rowHeights.append(row.height)
            rowStart.append(row.range.lowerBound)
            var x: CGFloat = 0
            for item in row.range {
                let itemW = JustifiedGridRows.itemWidth(
                    aspectRatio: ratios[item],
                    rowHeight: row.height
                )
                itemRow[item] = Int32(rowIndex)
                itemX[item] = x
                itemWidth[item] = itemW
                x += itemW + Self.spacing
            }
            y += row.height + Self.spacing
            rowTops.append(y)
        }
        // The trailing gap is not part of the section's height.
        if let last = rowTops.last, !rows.isEmpty {
            rowTops[rowTops.count - 1] = last - Self.spacing
        }
        rowStart.append(itemCount)
        return AspectSection(
            rowTops: rowTops,
            rowHeights: rowHeights,
            rowStart: rowStart,
            itemRow: itemRow,
            itemX: itemX,
            itemWidth: itemWidth
        )
    }

    private func frame(section: Int, item: Int, in level: Level) -> CGRect {
        let top = level.itemTops[section]
        if let aspect = level.aspect?[section], item < aspect.itemRow.count {
            let row = Int(aspect.itemRow[item])
            return CGRect(
                x: aspect.itemX[item],
                y: top + aspect.rowTops[row],
                width: aspect.itemWidth[item],
                height: aspect.rowHeights[row]
            )
        }
        if let offsets = level.rowOffsets?[section] {
            let y = top + offsets[item]
            let height = offsets[item + 1] - offsets[item] - Self.spacing
            return CGRect(x: 0, y: y, width: preparedWidth, height: height)
        }
        let row = item / level.columns
        let column = item % level.columns
        let scale = max(1, preparedScale)
        let x = (CGFloat(column) * level.stride * scale).rounded() / scale
        return CGRect(
            x: x,
            y: top + CGFloat(row) * level.rowStride,
            width: level.side,
            height: level.side
        )
    }

    private func headerFrame(section: Int, in level: Level) -> CGRect {
        CGRect(x: 0, y: level.sectionTops[section], width: preparedWidth, height: Self.headerHeight)
    }

    private func footerFrame(in level: Level) -> CGRect {
        let last = sections.count - 1
        let y = level.sectionTops[last] + level.sectionHeights[last] - footerHeight
        return CGRect(x: 0, y: y, width: preparedWidth, height: footerHeight)
    }

    // MARK: Blending

    private func blend(_ a: CGRect, _ b: CGRect) -> CGRect {
        guard isZooming else { return a }
        let t = zoomProgress
        return CGRect(
            x: a.minX + (b.minX - a.minX) * t,
            y: a.minY + (b.minY - a.minY) * t,
            width: a.width + (b.width - a.width) * t,
            height: a.height + (b.height - a.height) * t
        )
    }

    private func blendedFrame(section: Int, item: Int) -> CGRect {
        let a = frame(section: section, item: item, in: level(zoomFrom))
        guard isZooming else { return a }
        return blend(a, frame(section: section, item: item, in: level(zoomTo)))
    }

    private func blendedSectionTop(_ section: Int) -> CGFloat {
        let a = level(zoomFrom).sectionTops[section]
        guard isZooming else { return a }
        return a + (level(zoomTo).sectionTops[section] - a) * zoomProgress
    }

    private func blendedSectionHeight(_ section: Int) -> CGFloat {
        let a = level(zoomFrom).sectionHeights[section]
        guard isZooming else { return a }
        return a + (level(zoomTo).sectionHeights[section] - a) * zoomProgress
    }

    /// The flat index of the pinned photo, resolved to a section and item.
    private func anchorIndexPath() -> IndexPath? {
        guard let flat = zoomAnchorFlatIndex else { return nil }
        var start = 0
        for (section, entry) in sections.enumerated() {
            if flat < start + entry.itemCount {
                return IndexPath(item: flat - start, section: section)
            }
            start += entry.itemCount
        }
        return nil
    }

    // MARK: UICollectionViewLayout

    override func prepare() {
        super.prepare()
        let width = contentWidth
        let scale = displayScale
        if width != preparedWidth || scale != preparedScale {
            preparedWidth = width
            preparedScale = scale
            dropLevels()
        }
    }

    override var collectionViewContentSize: CGSize {
        guard preparedWidth > 0, !sections.isEmpty else { return .zero }
        let a = level(zoomFrom).contentHeight
        let height = isZooming ? a + (level(zoomTo).contentHeight - a) * zoomProgress : a
        return CGSize(width: preparedWidth, height: height)
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView else { return false }
        if newBounds.width != collectionView.bounds.width { return true }
        // Pinned headers move with every scroll frame.
        return pinsHeaders && sections.contains { $0.hasHeader }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard preparedWidth > 0, sections.indices.contains(indexPath.section),
              indexPath.item < sections[indexPath.section].itemCount
        else { return nil }
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = blendedFrame(section: indexPath.section, item: indexPath.item)
        return attributes
    }

    override func layoutAttributesForSupplementaryView(
        ofKind elementKind: String, at indexPath: IndexPath
    ) -> UICollectionViewLayoutAttributes? {
        guard preparedWidth > 0, sections.indices.contains(indexPath.section) else { return nil }
        switch elementKind {
        case UICollectionView.elementKindSectionHeader:
            guard sections[indexPath.section].hasHeader else { return nil }
            let attributes = UICollectionViewLayoutAttributes(
                forSupplementaryViewOfKind: elementKind, with: indexPath
            )
            attributes.frame = pinnedHeaderFrame(section: indexPath.section)
            attributes.zIndex = 10
            return attributes
        case UICollectionView.elementKindSectionFooter:
            guard footerHeight > 0, indexPath.section == sections.count - 1 else { return nil }
            let attributes = UICollectionViewLayoutAttributes(
                forSupplementaryViewOfKind: elementKind, with: indexPath
            )
            let a = footerFrame(in: level(zoomFrom))
            attributes.frame = isZooming ? blend(a, footerFrame(in: level(zoomTo))) : a
            return attributes
        default:
            return nil
        }
    }

    private func pinnedHeaderFrame(section: Int) -> CGRect {
        let top = blendedSectionTop(section)
        var frame = CGRect(x: 0, y: top, width: preparedWidth, height: Self.headerHeight)
        guard pinsHeaders, let collectionView else { return frame }
        let visibleTop = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
        let sectionBottom = top + blendedSectionHeight(section)
        frame.origin.y = min(max(top, visibleTop), sectionBottom - Self.headerHeight)
        return frame
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard preparedWidth > 0, !sections.isEmpty else { return nil }
        var result: [UICollectionViewLayoutAttributes] = []

        // Items. In a blend, the rect is in blended space; move it into each
        // end layout's space by the pinned photo's displacement, collect the
        // items visible there, and filter by the blended frame. Every photo
        // is above the rect in both spaces, below it in both, or in one of
        // the two candidate sets — so the union is complete (positions are
        // monotonic in index in every layout).
        var candidates = Set<IndexPath>()
        let from = level(zoomFrom)
        candidates.formUnion(visibleItems(in: rect.offsetBy(dx: 0, dy: anchorShift(in: from)), level: from))
        if isZooming {
            let to = level(zoomTo)
            candidates.formUnion(visibleItems(in: rect.offsetBy(dx: 0, dy: anchorShift(in: to)), level: to))
        }
        for indexPath in candidates {
            let frame = blendedFrame(section: indexPath.section, item: indexPath.item)
            guard frame.intersects(rect) else { continue }
            let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
            attributes.frame = frame
            result.append(attributes)
        }

        // Headers and footer.
        for section in sections.indices {
            if sections[section].hasHeader {
                let indexPath = IndexPath(item: 0, section: section)
                if let header = layoutAttributesForSupplementaryView(
                    ofKind: UICollectionView.elementKindSectionHeader, at: indexPath
                ), header.frame.intersects(rect) {
                    result.append(header)
                }
            }
        }
        if footerHeight > 0,
           let footer = layoutAttributesForSupplementaryView(
               ofKind: UICollectionView.elementKindSectionFooter,
               at: IndexPath(item: 0, section: sections.count - 1)
           ), footer.frame.intersects(rect) {
            result.append(footer)
        }
        return result
    }

    /// How far the pinned photo sits in `level`'s space from where the blend
    /// puts it. Zero when not zooming.
    private func anchorShift(in level: Level) -> CGFloat {
        guard isZooming, let anchor = anchorIndexPath() else { return 0 }
        let own = frame(section: anchor.section, item: anchor.item, in: level).minY
        return own - blendedFrame(section: anchor.section, item: anchor.item).minY
    }

    /// Items whose frame in `level` intersects `rect`, by row arithmetic.
    private func visibleItems(in rect: CGRect, level: Level) -> [IndexPath] {
        var found: [IndexPath] = []
        for (section, entry) in sections.enumerated() where entry.itemCount > 0 {
            let top = level.itemTops[section]
            if let aspect = level.aspect?[section], !aspect.rowHeights.isEmpty {
                // Rows differ in height, so the visible band is a binary
                // search over their tops rather than a division.
                let firstRow = max(0, lowerBound(aspect.rowTops, value: rect.minY - top) - 1)
                var row = firstRow
                while row < aspect.rowHeights.count, top + aspect.rowTops[row] <= rect.maxY {
                    for item in aspect.rowStart[row]..<aspect.rowStart[row + 1] {
                        found.append(IndexPath(item: item, section: section))
                    }
                    row += 1
                }
                continue
            }
            if let offsets = level.rowOffsets?[section] {
                // One column, per-photo heights: binary search the offsets.
                let first = lowerBound(offsets, value: rect.minY - top)
                var item = max(0, first - 1)
                while item < entry.itemCount, top + offsets[item] <= rect.maxY {
                    found.append(IndexPath(item: item, section: section))
                    item += 1
                }
                continue
            }
            let rows = (entry.itemCount + level.columns - 1) / level.columns
            let firstRow = max(0, Int(((rect.minY - top) / level.rowStride).rounded(.down)))
            let lastRow = min(rows - 1, Int(((rect.maxY - top) / level.rowStride).rounded(.down)))
            guard firstRow <= lastRow else { continue }
            let firstItem = firstRow * level.columns
            let lastItem = min(entry.itemCount - 1, (lastRow + 1) * level.columns - 1)
            for item in firstItem...lastItem {
                found.append(IndexPath(item: item, section: section))
            }
        }
        return found
    }

    /// First index whose value is >= `value`.
    private func lowerBound(_ values: [CGFloat], value: CGFloat) -> Int {
        var low = 0
        var high = values.count
        while low < high {
            let mid = (low + high) / 2
            if values[mid] < value { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
