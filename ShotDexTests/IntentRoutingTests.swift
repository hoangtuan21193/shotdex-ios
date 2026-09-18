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

    // MARK: Handoff

    @Test func handedOverPhotoOpensOnTheLibraryTab() {
        let navigation = AppNavigation()
        navigation.selectedTab = .statistics
        var path = NavigationPath()

        navigation.handle(.photo(assetId: "ABC/L0/001"), albumsPath: &path)

        #expect(navigation.selectedTab == .library)
        #expect(navigation.pendingPhotoAssetId == "ABC/L0/001")
    }

    /// Handing the same photo over twice has to open it twice. The identifier
    /// alone cannot say so — it is unchanged — which is what the token is for.
    @Test func handingTheSamePhotoTwiceFiresTwice() {
        let navigation = AppNavigation()
        var path = NavigationPath()

        navigation.handle(.photo(assetId: "same"), albumsPath: &path)
        let first = navigation.pendingPhotoToken
        navigation.handle(.photo(assetId: "same"), albumsPath: &path)

        #expect(navigation.pendingPhotoToken != first)
    }

    /// A Handoff payload is a cloud identifier, so an activity of any other
    /// type, or one without that key, resolves to nothing rather than being
    /// guessed at.
    @Test func foreignActivityResolvesToNothing() async {
        let wrongType = NSUserActivity(activityType: "com.example.other")
        wrongType.userInfo = ["cloudIdentifier": "whatever"]
        #expect(await HandoffActivity.localIdentifier(from: wrongType) == nil)

        let noPayload = NSUserActivity(activityType: HandoffActivity.viewPhoto)
        #expect(await HandoffActivity.localIdentifier(from: noPayload) == nil)
    }
}