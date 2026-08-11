import Foundation

/// A named arrangement of photo cells, held as a split tree (`CollageLayoutNode`)
/// so its seams are draggable (§9). `cells` is the tree resolved with default
/// weights — the tiling the thumbnail and a freshly opened collage show; the
/// live canvas resolves the same tree with the recipe's weight overrides.
struct CollageTemplate: Identifiable, Equatable, Sendable {
    let id: String
    let root: CollageLayoutNode

    var cellCount: Int { root.leafCount }
    var cells: [NormalizedRect] { root.resolve(in: .full) }

    /// Cells resolved with the user's divider drags folded in.
    func resolvedCells(overrides: [String: [Double]]) -> [NormalizedRect] {
        root.resolve(in: .full, overrides: overrides)
    }

    /// Draggable seams in unit space, honouring the same overrides.
    func dividers(overrides: [String: [Double]]) -> [CollageDivider] {
        root.dividers(in: .full, overrides: overrides)
    }
}

/// The fixed template catalog for 2–9 photos. Each template is a split tree; the
/// tree cannot produce gaps or overlaps (the unit tests pin that), and every
/// interior split is a place a divider can be dragged.
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
        make("2-cols", .columns([1, 1], [.leaf, .leaf])),
        make("2-rows", .rows([1, 1], [.leaf, .leaf])),
        make("2-cols-wide", .columns([2, 1], [.leaf, .leaf])),
        make("2-rows-tall", .rows([2, 1], [.leaf, .leaf])),
        make("2-cols-right", .columns([1, 2], [.leaf, .leaf])),
        make("2-rows-bottom", .rows([1, 2], [.leaf, .leaf])),
        // 3
        make("3-left-tall", .columns([2, 1], [.leaf, rowStrip(2)])),
        make("3-right-tall", .columns([1, 2], [rowStrip(2), .leaf])),
        make("3-top-wide", .rows([2, 1], [.leaf, colStrip(2)])),
        make("3-bottom-wide", .rows([1, 2], [colStrip(2), .leaf])),
        make("3-1-2", .rows([1, 1], [.leaf, colStrip(2)])),
        make("3-2-1", .rows([1, 1], [colStrip(2), .leaf])),
        make("3-cols", colStrip(3)),
        make("3-rows", rowStrip(3)),
        // 4
        make("4-grid", grid(rows: 2, columns: 2)),
        make("4-left-tall", .columns([2, 1], [.leaf, rowStrip(3)])),
        make("4-right-tall", .columns([1, 2], [rowStrip(3), .leaf])),
        make("4-top-wide", .rows([2, 1], [.leaf, colStrip(3)])),
        make("4-1-3", .rows([1, 1], [.leaf, colStrip(3)])),
        make("4-3-1", .rows([1, 1], [colStrip(3), .leaf])),
        make("4-windmill", .rows([1, 1], [
            .columns([2, 1], [.leaf, .leaf]),
            .columns([1, 2], [.leaf, .leaf]),
        ])),
        make("4-rows", rowStrip(4)),
        make("4-cols", colStrip(4)),
        // 5
        make("5-2-3", .rows([1, 1], [colStrip(2), colStrip(3)])),
        make("5-3-2", .rows([1, 1], [colStrip(3), colStrip(2)])),
        make("5-1-4", .rows([2, 1], [.leaf, colStrip(4)])),
        make("5-4-1", .rows([1, 2], [colStrip(4), .leaf])),
        make("5-2-1-2", .rows([1, 1, 1], [colStrip(2), .leaf, colStrip(2)])),
        make("5-left-tall", .columns([2, 1], [.leaf, rowStrip(4)])),
        make("5-right-tall", .columns([1, 2], [rowStrip(4), .leaf])),
        make("5-cols", colStrip(5)),
        // 6
        make("6-grid", grid(rows: 2, columns: 3)),
        make("6-grid-tall", grid(rows: 3, columns: 2)),
        make("6-1-2-3", .rows([2, 1, 1], [.leaf, colStrip(2), colStrip(3)])),
        make("6-2-4", .rows([2, 1], [colStrip(2), colStrip(4)])),
        make("6-4-2", .rows([1, 1], [colStrip(4), colStrip(2)])),
        make("6-3-2-1", .rows([1, 1, 1], [colStrip(3), colStrip(2), .leaf])),
        make("6-left-tall", .columns([2, 1], [.leaf, rowStrip(5)])),
        // 7
        make("7-3-4", .rows([1, 1], [colStrip(3), colStrip(4)])),
        make("7-4-3", .rows([1, 1], [colStrip(4), colStrip(3)])),
        make("7-2-2-3", .rows([1, 1, 1], [colStrip(2), colStrip(2), colStrip(3)])),
        make("7-2-3-2", .rows([1, 1, 1], [colStrip(2), colStrip(3), colStrip(2)])),
        make("7-1-3-3", .rows([2, 1, 1], [.leaf, colStrip(3), colStrip(3)])),
        make("7-top-wide", .rows([2, 1], [.leaf, colStrip(6)])),
        make("7-left-tall", .columns([2, 1], [.leaf, rowStrip(6)])),
        // 8
        make("8-grid", grid(rows: 2, columns: 4)),
        make("8-grid-tall", grid(rows: 4, columns: 2)),
        make("8-2-3-3", .rows([1, 1, 1], [colStrip(2), colStrip(3), colStrip(3)])),
        make("8-3-2-3", .rows([1, 1, 1], [colStrip(3), colStrip(2), colStrip(3)])),
        make("8-2-4-2", .rows([1, 1, 1], [colStrip(2), colStrip(4), colStrip(2)])),
        make("8-3-3-2", .rows([1, 1, 1], [colStrip(3), colStrip(3), colStrip(2)])),
        make("8-left-tall", .columns([2, 1], [.leaf, rowStrip(7)])),
        // 9
        make("9-grid", grid(rows: 3, columns: 3)),
        make("9-2-3-4", .rows([1, 1, 1], [colStrip(2), colStrip(3), colStrip(4)])),
        make("9-1-4-4", .rows([2, 1, 1], [.leaf, colStrip(4), colStrip(4)])),
        make("9-4-1-4", .rows([1, 2, 1], [colStrip(4), .leaf, colStrip(4)])),
        make("9-2-2-2-3", .rows([1, 1, 1, 1], [colStrip(2), colStrip(2), colStrip(2), colStrip(3)])),
        make("9-3-3-2-1", .rows([1, 1, 1, 1], [colStrip(3), colStrip(3), colStrip(2), .leaf])),
        make("9-left-tall", .columns([2, 1], [.leaf, rowStrip(8)])),
    ]

    // MARK: - Builders

    private static func make(_ id: String, _ root: CollageLayoutNode) -> CollageTemplate {
        CollageTemplate(id: id, root: root.assigningIDs())
    }

    /// A row of `n` equal columns.
    private static func colStrip(_ n: Int) -> CollageLayoutNode {
        .columns(Array(repeating: 1, count: n), Array(repeating: .leaf, count: n))
    }

    /// A column of `n` equal rows.
    private static func rowStrip(_ n: Int) -> CollageLayoutNode {
        .rows(Array(repeating: 1, count: n), Array(repeating: .leaf, count: n))
    }

    /// `rows` × `columns`, row-major leaf order (matches the geometry tests).
    private static func grid(rows: Int, columns: Int) -> CollageLayoutNode {
        .rows(
            Array(repeating: 1, count: rows),
            Array(repeating: colStrip(columns), count: rows)
        )
    }
}
