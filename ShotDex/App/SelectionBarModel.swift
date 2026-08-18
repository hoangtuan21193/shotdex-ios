import SwiftUI

/// The data + actions the root tab view needs to render the floating selection
/// chrome (`SelectionOverlay`). Published by the screen that's currently
/// selecting via `AppNavigation.selectionBar`, so one full-screen overlay serves
/// every screen (Library, Album Detail, Smart Album Detail, On This Day) and the
/// native tab/nav bars can hide beneath it.
///
/// Not `Equatable` (it holds closures and a service): the root tab view animates
/// on `selectionBar != nil`, and screens republish it from an Equatable snapshot
/// of their own selection state — never by diffing this. Storing closures in an
/// `@Observable` is fine; observation only instruments property access. The
/// closures capture the screen's `@State` (stable heap storage), so they act on
/// the current selection even though the screen struct is a value.
///
/// Optional closures (`onCompare`, `onCollage`, …) are `nil` when the hosting
/// screen doesn't offer that action at all (the control is omitted). Presence is
/// per-screen; enablement is per-count and computed by the overlay from the
/// counts below — an offered-but-out-of-range control dims in place rather than
/// disappearing.
@MainActor
struct SelectionBarModel {
    var selectionCount: Int
    /// How many of the selected assets are images — Collage / Compress / Export
    /// EXIF gate on this (`selectionCount` also counts videos).
    var imageSelectionCount: Int = 0
    /// Selected asset ids in pick order (drives the thumbnail tray).
    var thumbnailIds: [String]
    let photoLibrary: PhotoLibraryService
    /// Reads indexed byte totals for the selection size caption.
    let libraryQueries: LibraryQueries
    var isDeleting: Bool = false
    /// While gathering originals for the share sheet — the Share glyph swaps to
    /// a spinner.
    var isPreparingShare: Bool = false

    // Top row (always present).
    /// Gathers the selection and raises the system share sheet.
    var onShare: () -> Void
    /// Leaves selection mode.
    var onClose: () -> Void
    /// Tapping a tray thumbnail's × removes that id from the selection.
    var onDeselect: (String) -> Void

    // Bottom clusters (`nil` = screen doesn't offer it).
    /// Create cluster — combine the picked images into a collage.
    var onCollage: (() -> Void)? = nil
    /// Create cluster — build a video from the picked photos/videos.
    var onVideo: (() -> Void)? = nil
    /// Middle cluster — side-by-side compare (valid 2…`CompareScreen.maxPhotoCount`).
    var onCompare: (() -> Void)? = nil
    /// Middle cluster — resize / compress the picked images.
    var onCompress: (() -> Void)? = nil
    /// Trailing standalone button — delete the selection (confirmed by PhotoKit).
    var onDelete: () -> Void

    // ⋯ More menu (each `nil` omits its row; all `nil` hides the ⋯ button).
    var onAddToCollection: (() -> Void)? = nil
    var onExportEXIF: (() -> Void)? = nil
    var onDuplicate: (() -> Void)? = nil
}
