import Foundation
import SwiftUI

/// Cross-tab navigation state: which tab is selected, plus programmatic
/// jumps like "open Library filtered by this camera" from Statistics.
@MainActor
@Observable
final class AppNavigation {
    var selectedTab: AppTab = .library

    /// Whether the left slide-in settings drawer is showing.
    var isSettingsDrawerOpen = false

    /// Set while a screen is in photo multi-select mode: hides the tab bar so
    /// the full-width selection bar can take its place. The iOS 26 native tab
    /// bar is hidden per-screen via `.toolbar(.hidden, for: .tabBar)`; this flag
    /// drives the pre-26 custom `LiquidGlassTabBar`.
    var hidesTabBar = false

    /// Set by Statistics drill-downs; consumed by the Library controller owner.
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
