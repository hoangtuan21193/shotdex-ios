import CoreGraphics

/// The Media grid's shape on each window (FS-12.09 §3): square cells, no
/// corner radius, a fixed number of columns per layout. The cell follows the
/// width the grid is given, so a narrower phone keeps four columns of smaller
/// cells rather than three of the same size.
struct VideoMediaGridMetrics: Equatable {
    let columns: Int
    let gap: CGFloat
    /// Space at the leading and trailing edge.
    let inset: CGFloat

    /// Phone: four columns of 99 with 2pt gaps, edge to edge.
    static let phone = VideoMediaGridMetrics(columns: 4, gap: 2, inset: 0)
    /// The iPad's 320pt pool: three of 96, gaps of 4, 12 at the edges.
    static let pool = VideoMediaGridMetrics(columns: 3, gap: 4, inset: 12)
    /// The iPad portrait dock: eight of 121.5, gaps of 4, 16 at the edges.
    static let dock = VideoMediaGridMetrics(columns: 8, gap: 4, inset: 16)
    /// The Duo's 264pt inner column: three of 80, gaps of 4.
    static let duoColumn = VideoMediaGridMetrics(columns: 3, gap: 4, inset: 8)
    /// The Duo cover's 382pt panel: four of 94, 2pt gaps, edge to edge.
    static let cover = VideoMediaGridMetrics(columns: 4, gap: 2, inset: 0)

    static func `for`(_ windowClass: VideoStudioWindowClass) -> VideoMediaGridMetrics {
        switch windowClass {
        case .phone: .phone
        case .iPadLandscape: .pool
        case .iPadPortrait: .dock
        case .duoInner: .duoColumn
        case .duoCover: .cover
        }
    }

    /// The side of one square cell in a grid `width` wide, to the half
    /// point below — a 2× pixel grid, and eight dock cells of 121.5 that
    /// would lose 4pt across the row in whole points.
    func cellSide(width: CGFloat) -> CGFloat {
        let usable = width - inset * 2 - gap * CGFloat(max(0, columns - 1))
        return max(1, (usable / CGFloat(max(1, columns)) * 2).rounded(.down) / 2)
    }
}
