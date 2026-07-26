import SwiftUI

/// The data + actions the root tab view needs to render the multi-select bar in
/// the tab bar's slot. Published by the screen that's currently selecting via
/// `AppNavigation.selectionBar`, so the bar lives in one container with the tab
/// bar and the two can crossfade in place.
///
/// Not `Equatable` (it holds closures and a service): the root tab view animates on
/// `selectionBar != nil`, and screens republish it from an Equatable snapshot of
/// their own selection state — never by diffing this. Storing closures in an
/// `@Observable` is fine; observation only instruments property access. The
/// closures capture the screen's `@State` (stable heap storage), so they act on
/// the current selection even though the screen struct is a value.
@MainActor
struct SelectionBarModel {
    var selectionCount: Int
    /// Selected asset ids in pick order (drives the thumbnail preview).
    var thumbnailIds: [String]
    let photoLibrary: PhotoLibraryService
    /// `nil` hides Compare entirely (e.g. On This Day is delete-only).
    var onCompare: (() -> Void)?
    var onDelete: () -> Void
    /// Tapping a thumbnail slot removes that id from the selection.
    var onDeselect: (String) -> Void
    var isDeleting: Bool
}
