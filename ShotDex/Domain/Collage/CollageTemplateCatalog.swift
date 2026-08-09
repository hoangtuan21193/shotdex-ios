import Foundation

/// A named arrangement of unit-space cells. Rects tile [0,1]² edge to edge —
/// no gutter is baked in, so one template serves every aspect and spacing;
/// `CollageGeometry.cellFrames` applies both at resolve time.
struct CollageTemplate: Identifiable, Equatable, Sendable {
    let id: String
    let cellCount: Int
    let cells: [NormalizedRect]
}

/// The fixed template catalog for 2–9 photos. Everything is generated from a
/// handful of tiling helpers rather than hand-typed rects: the helpers can't
/// produce gaps or overlaps, which is also what the unit tests pin down.
enum CollageTemplateCatalog {
    /// The photo counts a collage supports — also the Create menu's gate.
    static let supportedCounts: ClosedRange<Int> = 2...9

    static func templates(for count: Int) -> [CollageTemplate] {
        all.filter { $0.cellCount == count }
    }

    static func template(id: String) -> CollageTemplate? {
        all.first { $0.id == id }
    }

    static let all: [CollageTemplate] = [
        // 2
        columns(id: "2-cols", weights: [1, 1]),
        rows(id: "2-rows", weights: [1, 1]),
        columns(id: "2-cols-wide", weights: [2, 1]),
        rows(id: "2-rows-tall", weights: [2, 1]),
        // 3
        mainPlusStrip(id: "3-left-tall", edge: .leading, stripCount: 2),
        mainPlusStrip(id: "3-right-tall", edge: .trailing, stripCount: 2),
        mainPlusStrip(id: "3-top-wide", edge: .top, stripCount: 2),
        columns(id: "3-cols", weights: [1, 1, 1]),
        rows(id: "3-rows", weights: [1, 1, 1]),
        // 4
        grid(id: "4-grid", rows: 2, columns: 2),
        mainPlusStrip(id: "4-left-tall", edge: .leading, stripCount: 3),
        mainPlusStrip(id: "4-top-wide", edge: .top, stripCount: 3),
        rowsOfCounts(id: "4-1-3", counts: [1, 3]),
        columns(id: "4-cols", weights: [1, 1, 1, 1]),
        // 5
        rowsOfCounts(id: "5-2-3", counts: [2, 3]),
        rowsOfCounts(id: "5-3-2", counts: [3, 2]),
        rowsOfCounts(id: "5-1-4", counts: [1, 4], weights: [2, 1]),
        mainPlusStrip(id: "5-left-tall", edge: .leading, stripCount: 4),
        // 6
        grid(id: "6-grid", rows: 2, columns: 3),
        grid(id: "6-grid-tall", rows: 3, columns: 2),
        rowsOfCounts(id: "6-1-2-3", counts: [1, 2, 3], weights: [2, 1, 1]),
        rowsOfCounts(id: "6-2-4", counts: [2, 4], weights: [2, 1]),
        // 7
        rowsOfCounts(id: "7-3-4", counts: [3, 4]),
        rowsOfCounts(id: "7-2-2-3", counts: [2, 2, 3]),
        rowsOfCounts(id: "7-1-3-3", counts: [1, 3, 3], weights: [2, 1, 1]),
        mainPlusStrip(id: "7-top-wide", edge: .top, stripCount: 6),
        // 8
        grid(id: "8-grid", rows: 2, columns: 4),
        grid(id: "8-grid-tall", rows: 4, columns: 2),
        rowsOfCounts(id: "8-2-3-3", counts: [2, 3, 3]),
        rowsOfCounts(id: "8-3-2-3", counts: [3, 2, 3]),
        // 9
        grid(id: "9-grid", rows: 3, columns: 3),
        rowsOfCounts(id: "9-2-3-4", counts: [2, 3, 4]),
        rowsOfCounts(id: "9-1-4-4", counts: [1, 4, 4], weights: [2, 1, 1]),
        rowsOfCounts(id: "9-4-1-4", counts: [4, 1, 4], weights: [1, 2, 1]),
    ]

    // MARK: - Tiling helpers

    private enum StripEdge { case leading, trailing, top, bottom }

    private static func grid(id: String, rows: Int, columns: Int) -> CollageTemplate {
        var cells: [NormalizedRect] = []
        let width = 1.0 / Double(columns)
        let height = 1.0 / Double(rows)
        for row in 0..<rows {
            for column in 0..<columns {
                cells.append(NormalizedRect(
                    x: Double(column) * width,
                    y: Double(row) * height,
                    width: width,
                    height: height
                ))
            }
        }
        return CollageTemplate(id: id, cellCount: rows * columns, cells: cells)
    }

    /// Full-width horizontal bands, heights proportional to `weights`.
    private static func rows(id: String, weights: [Double]) -> CollageTemplate {
        let total = weights.reduce(0, +)
        var y = 0.0
        var cells: [NormalizedRect] = []
        for weight in weights {
            let height = weight / total
            cells.append(NormalizedRect(x: 0, y: y, width: 1, height: height))
            y += height
        }
        return CollageTemplate(id: id, cellCount: weights.count, cells: cells)
    }

    /// Full-height vertical bands, widths proportional to `weights`.
    private static func columns(id: String, weights: [Double]) -> CollageTemplate {
        let total = weights.reduce(0, +)
        var x = 0.0
        var cells: [NormalizedRect] = []
        for weight in weights {
            let width = weight / total
            cells.append(NormalizedRect(x: x, y: 0, width: width, height: 1))
            x += width
        }
        return CollageTemplate(id: id, cellCount: weights.count, cells: cells)
    }

    /// Rows of equal-width cells; `counts[i]` cells in row i, row heights
    /// proportional to `weights` (equal when nil).
    private static func rowsOfCounts(
        id: String,
        counts: [Int],
        weights: [Double]? = nil
    ) -> CollageTemplate {
        let rowWeights = weights ?? Array(repeating: 1, count: counts.count)
        let total = rowWeights.reduce(0, +)
        var y = 0.0
        var cells: [NormalizedRect] = []
        for (row, count) in counts.enumerated() {
            let height = rowWeights[row] / total
            let width = 1.0 / Double(count)
            for column in 0..<count {
                cells.append(NormalizedRect(
                    x: Double(column) * width,
                    y: y,
                    width: width,
                    height: height
                ))
            }
            y += height
        }
        return CollageTemplate(id: id, cellCount: counts.reduce(0, +), cells: cells)
    }

    /// One dominant cell (2/3 of the canvas) plus a strip of `stripCount`
    /// equal cells along the given edge.
    private static func mainPlusStrip(
        id: String,
        edge: StripEdge,
        stripCount: Int
    ) -> CollageTemplate {
        let major = 2.0 / 3.0
        let minor = 1.0 - major
        var cells: [NormalizedRect] = []
        switch edge {
        case .leading, .trailing:
            let mainX = edge == .leading ? 0 : minor
            let stripX = edge == .leading ? major : 0
            cells.append(NormalizedRect(x: mainX, y: 0, width: major, height: 1))
            let height = 1.0 / Double(stripCount)
            for index in 0..<stripCount {
                cells.append(NormalizedRect(
                    x: stripX,
                    y: Double(index) * height,
                    width: minor,
                    height: height
                ))
            }
        case .top, .bottom:
            let mainY = edge == .top ? 0 : minor
            let stripY = edge == .top ? major : 0
            cells.append(NormalizedRect(x: 0, y: mainY, width: 1, height: major))
            let width = 1.0 / Double(stripCount)
            for index in 0..<stripCount {
                cells.append(NormalizedRect(
                    x: Double(index) * width,
                    y: stripY,
                    width: width,
                    height: minor
                ))
            }
        }
        return CollageTemplate(id: id, cellCount: stripCount + 1, cells: cells)
    }
}
