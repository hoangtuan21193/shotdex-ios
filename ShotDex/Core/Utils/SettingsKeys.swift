import Foundation

/// UserDefaults keys shared between the Settings UI and the feature models.
enum SettingsKeys {
    /// Allow streaming EXIF from iCloud over cellular/expensive paths during
    /// automatic index runs. Wi-Fi is always allowed. Defaults to false.
    static let allowCellularIndexing = "index.allowCellular"

    /// Persisted grid density (column count in `GridDensity.columnRange`),
    /// shared by the Library and Album Detail grids. Sanitized via
    /// `GridDensity.clamped`.
    static let gridColumns = "grid.columns"

    /// Show the compact RAW/JPG/HEIC/MOV-style badge at the top-leading corner
    /// of every grid thumbnail. Defaults to true.
    static let showFileTypeBadge = "display.showFileType"

    /// Keep the display awake — and auto-dim via a black overlay after an idle
    /// period — while indexing runs. Defaults to false.
    static let keepScreenAwake = "index.keepScreenAwake"

    /// Reverse-geocode photo coordinates into place names after an index run, so
    /// searching for a city works. Defaults to **true** (read through an
    /// `object(forKey:)` nil check, never plain `bool(forKey:)`, which answers
    /// false for an unwritten key). Uses the network, hence a switch: it is the
    /// only part of indexing that talks to a server about where the user has been.
    static let lookUpPlaces = "index.lookUpPlaces"

    /// Set once the Statistics dashboard has seeded its default charts, so a
    /// board a user deliberately cleared isn't re-seeded on next launch.
    static let hasSeededStatCharts = "stats.didSeedCharts"

    /// Daily "On This Day" reminder on/off. Defaults to false — notification
    /// permission is only asked for once the user turns it on.
    static let onThisDayNotificationsEnabled = "notifications.onThisDay"

    /// Reminder time as minutes since local midnight, default 540 (09:00). Read
    /// through an `object(forKey:)` nil check, never plain `integer(forKey:)`:
    /// that answers 0 for an unwritten key, which would schedule at midnight
    /// while the picker shows 09:00.
    static let onThisDayNotifyMinutes = "notifications.onThisDayMinutes"

    /// JSON-encoded user-created resize/compression presets. Built-in Original,
    /// 4K, 2048 px and 1080 px presets are code-defined and never stored here.
    static let compressionPresets = "export.compressionPresets"

    /// `AppAccentTheme` raw value for the app-wide accent colour. An unwritten
    /// or unrecognised value means the system accent — see
    /// `AppAccentTheme.resolved`.
    static let accentTheme = "display.accentTheme"

    /// Per-source counters used by `_SHOTDEX_EDITED_N` and
    /// `_SHOTDEX_COMPRESSED_N` output filenames.
    static let outputFilenameIndexes = "export.outputFilenameIndexes"

    /// JSON-encoded saved overlay layer sets — the editor's reusable signatures.
    /// The images they reference live as files under `Application Support`.
    static let overlaySignatures = "editor.overlaySignatures"

    /// JSON-encoded most-recently-used typefaces, so the full installed-font list
    /// has to be searched once rather than once per photo.
    static let overlayRecentFonts = "editor.overlayRecentFonts"
}
