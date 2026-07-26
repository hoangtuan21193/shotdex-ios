import Foundation
import SwiftUI

/// Cross-tab navigation state: which tab is selected, plus programmatic
/// jumps like "open Library filtered by this camera" from Statistics.
@MainActor
@Observable
final class AppNavigation {
    var selectedTab: AppTab = .library

    /// Whether the Settings sheet is showing.
    var isSettingsSheetPresented = false

    /// Set while a screen is in photo multi-select mode. The iOS 26 native tab
    /// bar is hidden per-screen via `.toolbar(.hidden, for: .tabBar)`.
    /// Legacy: the pre-26 tab chrome used to gate its custom tab bar on this, but
    /// it now swaps to the selection bar on `selectionBar != nil` instead. Kept
    /// as a harmless signal; screens still set it.
    var hidesTabBar = false

    /// Published by the screen currently in multi-select so the root tab view
    /// can host the selection bar in the tab bar's own slot — the tab bar and
    /// the selection bar crossfade in place (one animation) instead of living in
    /// two different containers. `nil` when nothing is selecting.
    var selectionBar: SelectionBarModel?

    /// Extra bottom padding a grid adds to its content while selecting. The
    /// selection chrome is system-managed safe area on both tiers (iOS 26 tab-bar
    /// bottom accessory; pre-26 root `.safeAreaInset`), which the collection view
    /// already clears via automatic content-inset adjustment — so this is only a
    /// small breathing pad on top, not the full bar height.
    var selectionBarHeight: CGFloat = 12

    /// Bottom inset a grid adds to its content while selecting. On iOS 26 the
    /// count caption floats *over* the grid, above the tab-bar accessory and
    /// outside the safe area the collection view auto-clears — so the last row
    /// scrolls up under it. Extra clearance keeps that row visible and tappable.
    /// Pre-26 the caption lives inside the `.safeAreaInset` bar (already
    /// auto-cleared), so only the breathing pad is needed.
    var selectionGridInset: CGFloat {
        if #available(iOS 26.0, *) {
            selectionBarHeight + 46
        } else {
            selectionBarHeight
        }
    }

    /// Set by Statistics drill-downs; consumed by the Library model owner.
    var pendingLibraryFilter: FilterCriteria?

    /// Bumped when the user taps the Library tab while it's already selected;
    /// the Library grid jumps back to the newest photos. Monotonic so
    /// consecutive re-taps never compare equal for `.onChange`. Programmatic
    /// tab switches set `selectedTab` directly and never bump this.
    private(set) var libraryRetapToken = 0

    /// Bumped when the user chooses Advanced Search; the Library screen opens
    /// the advanced-search sheet. Monotonic for reliable `.onChange`. Routed
    /// through the Library tab because a sheet cannot be presented over the
    /// iOS 26 `.search`-role tab (SwiftUI suppresses it).
    private(set) var advancedSearchToken = 0

    func retapLibrary() {
        libraryRetapToken &+= 1
    }

    /// Switch to Library and open advanced search there.
    func openAdvancedSearch() {
        advancedSearchToken &+= 1
        selectedTab = .library
    }

    func openLibrary(with criteria: FilterCriteria) {
        pendingLibraryFilter = criteria
        selectedTab = .library
    }
}
