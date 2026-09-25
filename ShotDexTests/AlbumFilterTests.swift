import Foundation
import Photos
import Testing
@testable import ShotDex

/// FS-06.09 — the album Filter menu's state and the Photos predicate it
/// becomes.
struct AlbumFilterTests {

    // MARK: Predicate

    @Test func noQuickFilterAsksPhotosForNothing() {
        #expect(AlbumFilterPredicate.predicate(for: FilterCriteria()) == nil)
    }

    /// AC-1: Favorites narrows to favorites.
    @Test func favorites() {
        var criteria = FilterCriteria()
        criteria.favoritesOnly = true
        let predicate = AlbumFilterPredicate.predicate(for: criteria)
        #expect(predicate?.predicateFormat == "favorite == 1")
    }

    /// AC-2: one kind narrows, both kinds or none do not.
    @Test func mediaKinds() {
        var criteria = FilterCriteria()
        criteria.mediaKinds = [.video]
        #expect(
            AlbumFilterPredicate.predicate(for: criteria)?.predicateFormat
                == "mediaType == \(PHAssetMediaType.video.rawValue)"
        )
        criteria.mediaKinds = [.photo]
        #expect(
            AlbumFilterPredicate.predicate(for: criteria)?.predicateFormat
                == "mediaType == \(PHAssetMediaType.image.rawValue)"
        )
        criteria.mediaKinds = Set(MediaKind.allCases)
        #expect(AlbumFilterPredicate.predicate(for: criteria) == nil)
    }

    /// AC-3: capture kinds are "any of these"; a stitched panorama is matched
    /// by identifier because it has no system flag.
    @Test func captureKinds() {
        var criteria = FilterCriteria()
        criteria.mediaSubtypes = [.livePhoto]
        let live = PHAssetMediaSubtype.photoLive.rawValue
        #expect(
            AlbumFilterPredicate.predicate(for: criteria)?.predicateFormat
                == "mediaSubtypes & \(live) != 0"
        )

        criteria.mediaSubtypes = [.panorama, .screenshot]
        let format = AlbumFilterPredicate.predicate(
            for: criteria,
            stitchedPanoramaIds: ["stitched-1"]
        )?.predicateFormat ?? ""
        #expect(format.contains("mediaSubtypes & \(PhotoMediaSubtype.panorama.bit) != 0"))
        #expect(format.contains("mediaSubtypes & \(PhotoMediaSubtype.screenshot.bit) != 0"))
        #expect(format.contains("localIdentifier IN {\"stitched-1\"}"))
        #expect(format.contains(" OR "))
    }

    @Test func rowsCombineWithAnd() {
        var criteria = FilterCriteria()
        criteria.favoritesOnly = true
        criteria.mediaKinds = [.photo]
        let format = AlbumFilterPredicate.predicate(for: criteria)?.predicateFormat ?? ""
        #expect(format.contains("favorite == 1 AND mediaType == 1"))
    }

    @Test func onlyMenuRowsStayWithPhotos() {
        var criteria = FilterCriteria()
        criteria.favoritesOnly = true
        criteria.mediaSubtypes = [.hdr]
        #expect(!AlbumFilterPredicate.needsIndex(criteria))
        criteria.cameraBodies = ["EOS R6"]
        #expect(AlbumFilterPredicate.needsIndex(criteria))
    }

    // MARK: State

    /// AC-12: a quick filter and an advanced query never apply together.
    @Test func quickAndAdvancedAreExclusive() {
        var filter = AlbumFilter()
        let iso = SmartAlbumQuery(matchMode: .all, rules: [
            SmartAlbumRule(field: .iso, op: .greaterThan, number: 3200),
        ])
        filter.setAdvancedQuery(iso)
        #expect(filter.advancedQuery == iso)

        var favorites = FilterCriteria()
        favorites.favoritesOnly = true
        filter.setCriteria(favorites)
        #expect(filter.advancedQuery == nil)
        #expect(filter.criteria.favoritesOnly)

        filter.setAdvancedQuery(iso)
        #expect(filter.criteria.isEmpty)
        #expect(filter.isActive)

        filter.clear()
        #expect(!filter.isActive)
    }

    @Test func emptyAdvancedQueryIsNoQuery() {
        var filter = AlbumFilter()
        filter.setAdvancedQuery(.empty)
        #expect(filter.advancedQuery == nil)
        #expect(!filter.isActive)
    }
}
