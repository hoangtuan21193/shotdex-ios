import Foundation
import ShotDexKit

/// UserDefaults keys shared between the Settings UI and the feature models.
enum SettingsKeys {
    /// Read and Write .xmp Sidecars (FS-19.02 §5). Unwritten means on.
    static let readsAndWritesSidecars = "sources.sidecars"

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
    /// Settings › AI (FS-08.07 §3): `AIChoice.stored`; unset = the default.
    static let aiSearch = "ai.search"

    /// How much metadata a photo takes with it when it leaves the app — a
    /// `MetadataLevel` raw value (FS-08.06 §4). The default for every way out:
    /// Share, Save Copy, Paste Edits, Resize, drag. Unwritten means All
    /// Metadata, like Photos: a photographer sharing with a client usually
    /// wants the camera, the lens and the place to go with the picture.
    static let shareMetadataLevel = "share.metadataLevel"
    /// The on/off Include Location switch the level replaced. Read once at
    /// launch — off becomes No Location — and then removed.
    static let legacyShareIncludesLocation = "share.includeLocation"

    /// Set once the Statistics dashboard has seeded its default charts, so a
    /// board a user deliberately cleared isn't re-seeded on next launch.
    static let hasSeededStatCharts = "stats.didSeedCharts"
    /// Set once the six-chart seed of FS-07.01 §3 has run — on a fresh install
    /// with the whole set, on an install seeded with the old two by appending
    /// the other four. Never cleared, so a deleted chart does not grow back.
    static let hasSeededStatChartsV2 = "stats.didSeedCharts.v2"
    /// The Insights card on Statistics. Unwritten means shown; Hide Insights
    /// in the card's menu writes false, Settings → Display → Show Insights
    /// writes it back.
    static let showsInsights = "stats.showsInsights"

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

    /// JSON-encoded `FileExportSettings`: what Export… remembers (FS-03.07b §3).
    static let fileExportSettings = "export.files.settings"

    /// JSON-encoded folders Export… wrote to: bookmarks and the recents list
    /// (FS-03.07b §4).
    static let fileExportFolders = "export.files.folders"
    /// Memory cards shown once, by bookmark (FS-20 §4).
    static let ingestCards = "ingest.cards"
    /// Card import choices: destination, folders, names, metadata, Eject (FS-20 §6).
    static let ingestSettings = "ingest.settings"
    /// The Sync sheet's ticks, as `EditorSyncGroups` JSON (FS-03.09b §2).
    static let editorSyncGroups = "editor.sync.groups"

    /// Per-source counters used by `_SHOTDEX_EDITED_N` and
    /// `_SHOTDEX_COMPRESSED_N` output filenames.
    static let outputFilenameIndexes = "export.outputFilenameIndexes"

    /// JSON-encoded saved overlay layer sets — the editor's reusable signatures.
    /// The images they reference live as files under `Application Support`.
    static let overlaySignatures = "editor.overlaySignatures"

    /// JSON-encoded watermark choice of the export forms (FS-05.04 §5): the
    /// preset, Position, Margin, Size, Opacity and whether it is on — one
    /// configuration shared by Resize, Export and the server export sheet.
    static let watermarkExport = "watermark.export"

    /// Watermark When Sharing (FS-05.04 §4): the preset id, or unwritten for
    /// Off.
    static let watermarkSharing = "watermark.sharing"

    /// JSON-encoded most-recently-used typefaces, so the full installed-font list
    /// has to be searched once rather than once per photo.
    static let overlayRecentFonts = "editor.overlayRecentFonts"

    /// JSON-encoded user collage presets (frame + style, no text).
    static let collagePresets = "collage.presets"

    /// `DuplicatesFilter` of the Duplicates list. Unwritten (or empty) means All.
    static let duplicateKindFilter = "duplicates.kindFilter"

    /// `DuplicateSort` raw value of the group list. Unwritten means `.easiestFirst`.
    static let duplicateSort = "duplicates.sort"

    /// Copies per row on a Duplicates card, as the user pinched it — one per
    /// width class, like the Library grid's density. Unwritten means 2 compact,
    /// 3 regular.
    static let duplicateCopyColumnsCompact = "duplicates.copyColumns.compact"
    static let duplicateCopyColumnsRegular = "duplicates.copyColumns.regular"

    /// Group count of the last duplicate grouping, so the Collections tab token
    /// can show it without loading every hash. Unwritten means never scanned.
    static let duplicateGroupCount = "duplicates.lastGroupCount"
    /// Bytes keeping one per group would free, as of the last load — the
    /// "~X GB to free" under Duplicates in Collections (FS-06.06 §7.1).
    static let duplicateFreeBytes = "duplicates.lastFreeBytes"
    /// `["day": "2026-10-17", "bytes": Int]` — what Duplicates deleted today.
    static let duplicateFreedToday = "duplicates.freedToday"

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

extension MetadataLevel {
    /// The Settings default for every way a photo leaves the app.
    static func sharingDefault(in defaults: UserDefaults = .standard) -> MetadataLevel {
        defaults.string(forKey: SettingsKeys.shareMetadataLevel).flatMap(MetadataLevel.init(rawValue:)) ?? .all
    }

    /// Carries the old Include Location switch over once: off becomes No
    /// Location, on (or never touched) leaves the default. The old key is
    /// removed either way, so this does nothing the second time.
    static func migrateLegacySharingSwitch(in defaults: UserDefaults = .standard) {
        guard let includesLocation = defaults.object(forKey: SettingsKeys.legacyShareIncludesLocation) as? Bool
        else { return }
        if !includesLocation, defaults.string(forKey: SettingsKeys.shareMetadataLevel) == nil {
            defaults.set(MetadataLevel.noLocation.rawValue, forKey: SettingsKeys.shareMetadataLevel)
        }
        defaults.removeObject(forKey: SettingsKeys.legacyShareIncludesLocation)
    }
}
