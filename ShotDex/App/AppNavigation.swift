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

    /// Bottom inset a grid adds to its content while selecting. The selection
    /// chrome is now a floating `SelectionOverlay` on both tiers (not system safe
    /// area), so the grid gets no automatic clearance — this reserves room for the
    /// bottom action clusters (≈48pt bar + its padding + the home-indicator strip)
    /// so the last photo row stays visible and tappable beneath them.
    var selectionGridInset: CGFloat { 100 }

    /// Set by Statistics drill-downs; consumed by the Library model owner.
    var pendingLibraryFilter: FilterCriteria?

    /// Free text a Shortcut or Spotlight asked the Library to search for.
    var pendingSearchQuery: String?

    /// A photo another device handed over, to open in the viewer.
    private(set) var pendingPhotoAssetId: String?
    /// Bumped with it, so handing over the same photo twice still opens it.
    private(set) var pendingPhotoToken = 0

    /// True when the handover asked for the editor rather than the viewer — the
    /// share sheet's **Edit in ShotDex**. Read once by the detail screen as it
    /// appears, then cleared, so a later visit to the same photo is a plain view.
    private(set) var pendingPhotoOpensEditor = false

    /// Switch to Library and open this photo's viewer.
    func openPhoto(assetId: String, opensEditor: Bool = false) {
        pendingPhotoAssetId = assetId
        pendingPhotoOpensEditor = opensEditor
        pendingPhotoToken &+= 1
        selectedTab = .library
    }

    /// The detail screen taking the request: it opens the editor once and the
    /// flag does not survive to the next photo.
    func consumePendingEditorRequest() -> Bool {
        defer { pendingPhotoOpensEditor = false }
        return pendingPhotoOpensEditor
    }

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

    /// Bumped when a tapped "On This Day" reminder should open that day.
    /// Monotonic for reliable `.onChange`. Routed through the Albums tab's
    /// navigation path (that is where the screen lives) rather than presented,
    /// for the same reason `openAdvancedSearch` is routed through Library.
    private(set) var onThisDayToken = 0

    /// The day the pending On This Day push should land on; consumed by the
    /// root tab view when it sets the Albums path.
    var pendingOnThisDayDate: Date?

    func resetLibraryToRoot() {
        libraryRetapToken &+= 1
    }

    /// Switch to Library and open advanced search there.
    func openAdvancedSearch() {
        advancedSearchToken &+= 1
        selectedTab = .library
    }

    /// Switch to Albums and push On This Day for `date`.
    func openOnThisDay(date: Date) {
        pendingOnThisDayDate = date
        onThisDayToken &+= 1
        selectedTab = .albums
    }

    func openLibrary(with criteria: FilterCriteria) {
        pendingLibraryFilter = criteria
        selectedTab = .library
    }

    /// A Shortcut, a Siri phrase or a Spotlight result asked for something.
    /// Routed here rather than performed by the intent itself, which runs
    /// without the app's dependency graph.
    func handle(_ request: IntentRouter.Request, albumsPath: inout NavigationPath) {
        switch request {
        case .library:
            selectedTab = .library
        case .search(let query):
            pendingSearchQuery = query
            selectedTab = .library
        case .favorites:
            var criteria = FilterCriteria()
            criteria.favoritesOnly = true
            openLibrary(with: criteria)
        case .camera(let body):
            var criteria = FilterCriteria()
            // A contains-term rather than an exact set: a spoken or typed
            // camera name ("R6") rarely matches the indexed body verbatim.
            criteria.cameraBodyTerms = [body]
            openLibrary(with: criteria)
        case .statistics:
            selectedTab = .statistics
        case .places:
            albumsPath = NavigationPath([PlacesDestination()])
            selectedTab = .albums
        case .trips:
            albumsPath = NavigationPath([TripsDestination()])
            selectedTab = .albums
        case .photo(let assetId, let opensEditor):
            openPhoto(assetId: assetId, opensEditor: opensEditor)
        case .onThisDay(let date):
            openOnThisDay(date: date)
        }
    }
}
