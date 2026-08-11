import CoreGraphics
import Foundation

/// A collage template as a binary(-ish) space partition (§9). Every template is
/// a tree of splits: a `split` divides its rect among its children along one
/// axis by `weights`; a `leaf` is a photo cell. Dividers — the draggable seams —
/// are exactly the boundaries between a split's children, so resizing is a pure
/// function of the tree plus a per-node weight override.
///
/// Leaves, read left-to-right / top-to-bottom, are the collage's cells in order;
/// `CollageCell` index *i* is the *i*-th leaf.
enum CollageSplitAxis: Sendable, Equatable {
    /// Children stacked in rows — the split divides the rect's *height*.
    case horizontal
    /// Children placed in columns — the split divides the rect's *width*.
    case vertical
}

indirect enum CollageLayoutNode: Sendable, Equatable {
    case leaf
    case split(id: String, axis: CollageSplitAxis, weights: [Double], children: [CollageLayoutNode])

    /// Number of photo cells under this node.
    var leafCount: Int {
        switch self {
        case .leaf: 1
        case let .split(_, _, _, children): children.reduce(0) { $0 + $1.leafCount }
        }
    }

    // MARK: Building

    /// A split whose children are laid out in columns (widths ∝ weights).
    static func columns(_ weights: [Double], _ children: [CollageLayoutNode]) -> CollageLayoutNode {
        .split(id: "", axis: .vertical, weights: weights, children: children)
    }

    /// A split whose children are stacked in rows (heights ∝ weights).
    static func rows(_ weights: [Double], _ children: [CollageLayoutNode]) -> CollageLayoutNode {
        .split(id: "", axis: .horizontal, weights: weights, children: children)
    }

    /// Assigns each split a stable id from its path (`0`, `0.1`, `0.1.2`, …) so
    /// weight overrides key onto the same node across resolves. Called once, when
    /// the catalog builds a template.
    func assigningIDs(path: String = "0") -> CollageLayoutNode {
        switch self {
        case .leaf:
            return .leaf
        case let .split(_, axis, weights, children):
            let kids = children.enumerated().map { $1.assigningIDs(path: "\(path).\($0)") }
            return .split(id: path, axis: axis, weights: weights, children: kids)
        }
    }

    // MARK: Resolving

    /// Resolves this node to its leaf rects, in leaf order, honouring any weight
    /// overrides. `rect` is the region this node fills (unit space at the root).
    func resolve(in rect: NormalizedRect, overrides: [String: [Double]] = [:]) -> [NormalizedRect] {
        switch self {
        case .leaf:
            return [rect]
        case let .split(id, axis, defaultWeights, children):
            let weights = normalizedWeights(overrides[id], fallback: defaultWeights, count: children.count)
            let total = weights.reduce(0, +)
            var result: [NormalizedRect] = []
            var cursor = (axis == .horizontal) ? rect.y : rect.x
            for (index, child) in children.enumerated() {
                let fraction = total > 0 ? weights[index] / total : 1.0 / Double(children.count)
                let childRect: NormalizedRect
                switch axis {
                case .horizontal:
                    let h = rect.height * fraction
                    childRect = NormalizedRect(x: rect.x, y: cursor, width: rect.width, height: h)
                    cursor += h
                case .vertical:
                    let w = rect.width * fraction
                    childRect = NormalizedRect(x: cursor, y: rect.y, width: w, height: rect.height)
                    cursor += w
                }
                result.append(contentsOf: child.resolve(in: childRect, overrides: overrides))
            }
            return result
        }
    }

    /// The draggable seams under this node, in unit space, honouring overrides.
    func dividers(in rect: NormalizedRect, overrides: [String: [Double]] = [:]) -> [CollageDivider] {
        guard case let .split(id, axis, defaultWeights, children) = self else { return [] }
        let weights = normalizedWeights(overrides[id], fallback: defaultWeights, count: children.count)
        let total = weights.reduce(0, +)
        var dividers: [CollageDivider] = []
        var cursor = (axis == .horizontal) ? rect.y : rect.x
        var childRects: [NormalizedRect] = []
        for (index, child) in children.enumerated() {
            let fraction = total > 0 ? weights[index] / total : 1.0 / Double(children.count)
            let childRect: NormalizedRect
            switch axis {
            case .horizontal:
                let h = rect.height * fraction
                childRect = NormalizedRect(x: rect.x, y: cursor, width: rect.width, height: h)
                cursor += h
            case .vertical:
                let w = rect.width * fraction
                childRect = NormalizedRect(x: cursor, y: rect.y, width: w, height: rect.height)
                cursor += w
            }
            childRects.append(childRect)
            // Recurse for nested seams.
            dividers.append(contentsOf: child.dividers(in: childRect, overrides: overrides))
        }
        // One seam between each adjacent pair of this node's children.
        for index in 0..<(children.count - 1) {
            let a = childRects[index]
            switch axis {
            case .horizontal:
                let seamY = a.y + a.height
                dividers.append(CollageDivider(
                    nodeID: id, index: index, axis: .horizontal,
                    position: seamY, crossStart: rect.x, crossEnd: rect.x + rect.width,
                    nodeStart: rect.y, nodeSpan: rect.height, weights: weights
                ))
            case .vertical:
                let seamX = a.x + a.width
                dividers.append(CollageDivider(
                    nodeID: id, index: index, axis: .vertical,
                    position: seamX, crossStart: rect.y, crossEnd: rect.y + rect.height,
                    nodeStart: rect.x, nodeSpan: rect.width, weights: weights
                ))
            }
        }
        return dividers
    }

    private func normalizedWeights(_ override: [Double]?, fallback: [Double], count: Int) -> [Double] {
        // An override from a stale template (wrong arity) is ignored, so a
        // template change that forgets to clear cannot desync the layout.
        if let override, override.count == count, override.allSatisfy({ $0 > 0 }) {
            return override
        }
        return fallback
    }
}

/// One draggable seam, in unit space. `position` is the seam's coordinate along
/// the split axis (x for a vertical seam, y for a horizontal one); `crossStart`
/// / `crossEnd` bound its length on the other axis. `nodeStart`/`nodeSpan` are
/// the owning split's extent along the axis, which the drag maps a finger
/// position into a boundary fraction with.
struct CollageDivider: Equatable, Sendable {
    let nodeID: String
    let index: Int
    let axis: CollageSplitAxis
    let position: Double
    let crossStart: Double
    let crossEnd: Double
    let nodeStart: Double
    let nodeSpan: Double
    let weights: [Double]
}

/// Pure math for resizing a split by dragging one of its seams (§9). Kept off
/// any view so it can be unit-tested: the soft snap, the 15% floor and the
/// "other children stay put" invariant all live here.
enum CollageDividerMath {
    /// Smallest share of a split any single child may be squeezed to.
    static let minFraction: Double = 0.15
    /// Even marks a dragged seam softly snaps onto.
    static let snapMarks: [Double] = [1.0 / 3.0, 0.5, 2.0 / 3.0]
    /// How close (in fraction of the split's span) the seam must come to a mark
    /// to snap onto it.
    static let snapTolerance: Double = 0.03

    /// New weights after dragging seam `index` so the boundary sits at
    /// `fraction` of the split's span (0 at the split's start, 1 at its end).
    /// Only the two children the seam divides change; every other weight is
    /// preserved. `snap` folds in the soft snap to the even marks.
    static func adjustedWeights(
        _ weights: [Double],
        boundary index: Int,
        toFraction fraction: Double,
        snap: Bool
    ) -> [Double] {
        guard weights.indices.contains(index), weights.indices.contains(index + 1) else { return weights }
        let total = weights.reduce(0, +)
        guard total > 0 else { return weights }

        var f = min(max(fraction, 0), 1)
        if snap {
            for mark in snapMarks where abs(f - mark) <= snapTolerance {
                f = mark
                break
            }
        }

        let before = weights[0..<index].reduce(0, +) / total          // fixed left share
        let pair = (weights[index] + weights[index + 1]) / total       // the two children's combined share
        guard pair > 0 else { return weights }

        // Where the seam may sit inside the pair, keeping both children ≥ floor.
        let lowerBound = before + minFraction
        let upperBound = before + pair - minFraction
        let clampedF: Double
        if lowerBound > upperBound {
            clampedF = before + pair / 2   // pair too small to honour the floor
        } else {
            clampedF = min(max(f, lowerBound), upperBound)
        }

        let leftShare = clampedF - before
        let rightShare = pair - leftShare

        var result = weights
        result[index] = leftShare * total
        result[index + 1] = rightShare * total
        return result
    }
}
