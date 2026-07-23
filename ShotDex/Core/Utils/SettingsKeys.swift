import Foundation

/// UserDefaults keys shared between Settings UI and controllers.
enum SettingsKeys {
    /// Allow streaming EXIF from iCloud over cellular/expensive paths during
    /// automatic index runs. Wi-Fi is always allowed. Defaults to false.
    static let allowCellularIndexing = "index.allowCellular"

    /// Persisted grid density (column count in `GridDensity.columnRange`),
    /// shared by the Library and Album Detail grids. Sanitized via
    /// `GridDensity.clamped`.
    static let gridColumns = "grid.columns"

    /// Keep the display awake — and auto-dim via a black overlay after an idle
    /// period — while indexing runs. Defaults to false.
    static let keepScreenAwake = "index.keepScreenAwake"

    /// Set once the Statistics dashboard has seeded its default charts, so a
    /// board a user deliberately cleared isn't re-seeded on next launch.
    static let didSeedStatCharts = "stats.didSeedCharts"
}
