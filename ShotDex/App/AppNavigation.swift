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

    /// Set by Statistics drill-downs; consumed by the Library controller owner.
    var pendingLibraryFilter: FilterCriteria?

    /// Bumped when the user taps the Library tab while it's already selected;
    /// the Library grid jumps back to the newest photos. Monotonic so
    /// consecutive re-taps never compare equal for `.onChange`. Programmatic
    /// tab switches set `selectedTab` directly and never bump this.
    private(set) var libraryRetapToken = 0

    func retapLibrary() {
        libraryRetapToken &+= 1
    }

    func openLibrary(with criteria: FilterCriteria) {
        pendingLibraryFilter = criteria
        selectedTab = .library
    }
}
