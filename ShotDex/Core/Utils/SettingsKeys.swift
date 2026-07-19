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
}
