import CoreGraphics

/// Fixed geometry of the collage editor (DESIGN.md tier D, Turn 5 §1). Measured
/// in points on a 393×852 Dynamic-Island iPhone; the panel is a pure function of
/// nothing (it never resizes) and the stage is whatever is left between the tray
/// and the panel. Radii/spacing themselves come from `AppTheme`; this file only
/// holds the collage-specific *lengths* the shared scale has no name for.
///
/// The command band over the Dynamic Island reuses the photo editor's band
/// tokens (`EditorLayoutMetrics.editorTopBand*`) so the two tools sit their
/// controls at the same height as the island.
enum CollageMetrics {
    // MARK: Panel

    /// Total panel height — identical on Layout, Style and Text so switching tab
    /// never makes the panel jump.
    static let panelHeight: CGFloat = 216
    /// Tab-specific content zone above the bottom bar. 152 = 216 − 54 − 10.
    static let panelContentHeight: CGFloat = 152
    /// Bottom bar: the group tabs plus the Export pill.
    static let panelBottomBarHeight: CGFloat = 54
    /// Bare home-indicator inset under the bottom bar.
    static let panelSafeAreaInset: CGFloat = 10

    // Layout tab's three tiers, summing to `panelContentHeight`.
    /// Counter row: `[ − ] N [ + ]` on the leading edge, `☆ Save preset` trailing.
    static let counterRowHeight: CGFloat = 44
    /// Aspect chip row (horizontal scroll).
    static let aspectRowHeight: CGFloat = 34
    /// Template strip (horizontal scroll).
    static let templateRowHeight: CGFloat = 74

    // MARK: Command band (leading Undo/Redo/Original, trailing status + ⋯)

    /// Circular command button on the band.
    static let commandButtonSize: CGFloat = 34
    /// Full command-band height (row + top inset) — used to position the lift
    /// drop banner just below it.
    static let commandBandHeight: CGFloat = 48

    // MARK: Unplaced tray

    /// Resting tray height; hidden entirely when there is nothing unplaced.
    static let trayHeight: CGFloat = 48
    /// Tray height while a photo is being held for set-aside (§7 guidance).
    static let trayExpandedHeight: CGFloat = 56
    /// One unplaced thumbnail.
    static let trayThumbnailSize: CGFloat = 36
    static let trayThumbnailSpacing: CGFloat = 6
    /// Beyond this many the tray scrolls horizontally rather than wrapping.
    static let trayScrollThreshold: Int = 8

    // MARK: Stage

    /// The collage frame never grows past this on its long screen axis.
    static let maxFrameWidth: CGFloat = 353

    // MARK: Counter / bottom controls

    /// `[ − ] N [ + ]` container.
    static let counterHeight: CGFloat = 32
    /// Export pill (§12): a labelled button, not a round confirm.
    static let exportPillHeight: CGFloat = 38

    // MARK: Aspect chips

    static let aspectChipHeight: CGFloat = 28
    static let aspectChipMinWidth: CGFloat = 44

    // MARK: Template cells

    static let templateCellSize: CGFloat = 52
}
