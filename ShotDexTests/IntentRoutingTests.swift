import Foundation
import SwiftUI
import Testing
@testable import ShotDex

@MainActor
struct IntentRoutingTests {

    @Test func libraryRequestSelectsTheLibraryTab() {
        let navigation = AppNavigation()
        navigation.selectedTab = .statistics
        var path = NavigationPath()

        navigation.handle(.library, albumsPath: &path)

        #expect(navigation.selectedTab == .library)
    }

    @Test func searchRequestHandsTheQueryToTheLibrary() {
        let navigation = AppNavigation()
        var path = NavigationPath()

        navigation.handle(.search("Canon 85mm"), albumsPath: &path)

        #expect(navigation.selectedTab == .library)
        #expect(navigation.pendingSearchQuery == "Canon 85mm")
    }

    @Test func favoritesRequestFiltersTheLibrary() {
        let navigation = AppNavigation()
        var path = NavigationPath()

        navigation.handle(.favorites, albumsPath: &path)

        #expect(navigation.selectedTab == .library)
        #expect(navigation.pendingLibraryFilter?.favoritesOnly == true)
    }

    /// A spoken or typed camera name rarely matches the indexed body verbatim,
    /// so it has to arrive as a contains-term, not an exact-set member.
    @Test func cameraRequestUsesAContainsTerm() {
        let navigation = AppNavigation()
        var path = NavigationPath()

        navigation.handle(.camera("R6"), albumsPath: &path)

        #expect(navigation.pendingLibraryFilter?.cameraBodyTerms == ["R6"])
        #expect(navigation.pendingLibraryFilter?.cameraBodies.isEmpty == true)
    }

    @Test func placesAndTripsPushOntoTheCollectionsTab() {
        let navigation = AppNavigation()
        var path = NavigationPath()

        navigation.handle(.places, albumsPath: &path)
        #expect(navigation.selectedTab == .albums)
        #expect(path.count == 1)

        navigation.handle(.trips, albumsPath: &path)
        #expect(navigation.selectedTab == .albums)
        #expect(path.count == 1)
    }

    @Test func spotlightIdentifiersMapBackToRequests() {
        #expect(
            SpotlightIndexer.request(forSpotlightIdentifier: "shotdex://camera/Canon EOS R6")
                == .camera("Canon EOS R6")
        )
        #expect(
            SpotlightIndexer.request(forSpotlightIdentifier: "shotdex://lens/RF 85mm F1.2")
                == .search("RF 85mm F1.2")
        )
        #expect(SpotlightIndexer.request(forSpotlightIdentifier: "something-else") == nil)
    }
}
