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

    /// The Library grid's sort order (`SortOption.rawValue`). A preference,
    /// not scene state: the order a photographer picked is still the order
    /// they want tomorrow.
    static let librarySort = "grid.sort"

    /// Photos' aspect-ratio grid: tiles keep each photo's shape and rows are
    /// justified to the width. Defaults to false — the square grid is what
    /// every photo app opens on, and the shape grid is a deliberate choice.
    static let aspectRatioGrid = "grid.aspectTiles"

    /// Points the Video Studio's timeline has been dragged taller than the
    /// height its lanes need, on a regular-width window. Zero by default: the
    /// app's own answer is that the surplus belongs around the frame, and
    /// this is how the user says otherwise. Final Cut for iPad publishes the
    /// same handle.
    static let videoTimelineExtraHeight = "video.timelineExtraHeight"

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
    /// Seconds each photo is held during a slideshow.
    static let slideshowSeconds = "slideshow.seconds"
    /// Whether a video starts playing on its own when its page opens.
    static let autoplayVideos = "playback.autoplayVideos"
    /// Whether the viewer renders HDR photos at their full brightness.
    static let viewFullHDR = "display.viewFullHDR"

    /// Whether a shared photo carries the place it was taken. On by default,
    /// like Photos: the location is part of the picture's record, and a
    /// photographer sharing with a client usually wants it. Off is for the
    /// times the recipient should not learn where you were.
    static let shareIncludesLocation = "share.includeLocation"

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

    /// Per-source counters used by `_SHOTDEX_EDITED_N` and
    /// `_SHOTDEX_COMPRESSED_N` output filenames.
    static let outputFilenameIndexes = "export.outputFilenameIndexes"

    /// JSON-encoded saved overlay layer sets — the editor's reusable signatures.
    /// The images they reference live as files under `Application Support`.
    static let overlaySignatures = "editor.overlaySignatures"

    /// JSON-encoded most-recently-used typefaces, so the full installed-font list
    /// has to be searched once rather than once per photo.
    static let overlayRecentFonts = "editor.overlayRecentFonts"

    /// JSON-encoded user collage presets (frame + style, no text).
    static let collagePresets = "collage.presets"

    /// `DuplicateStrictness` raw value the Duplicates screen groups with.
    /// Unwritten means `.similar`.
    static let duplicateStrictness = "duplicates.strictness"

    /// Group count of the last duplicate grouping, so the Collections tab token
    /// can show it without loading every hash. Unwritten means never scanned.
    static let duplicateGroupCount = "duplicates.lastGroupCount"

    /// JSON-encoded user looks — the presets saved from an edit and applied to
    /// other photos. Look-only recipes, so they are small.
    static let lookPresets = "editor.lookPresets"

    /// Which side the editor's wide-screen tool sidebar sits on
    /// (`EditorSidebarEdge` raw value). Unwritten means trailing, the side
    /// Lightroom puts its develop panels on.
    static let editorSidebarEdge = "editor.sidebarEdge"
    /// Width of that sidebar in points, clamped to
    /// `EditorLayoutMetrics.sidebarWidthRange`. Unwritten means the default width.
    static let editorSidebarWidth = "editor.sidebarWidth"
    /// Whether the sidebar is collapsed so the photo has the whole window.
    static let editorSidebarHidden = "editor.sidebarHidden"
}
