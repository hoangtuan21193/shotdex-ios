import Foundation
import Testing

@testable import ShotDex

struct PlaceIndexingTests {
    @Test func nearbyPhotosShareOneCellAndDistantOnesDoNot() {
        let base = PlaceCellKey.key(latitude: 33.5904, longitude: 130.4017)
        #expect(base != nil)
        // Inside the same cell: one address, one request, however many photos.
        #expect(PlaceCellKey.key(latitude: 33.59044, longitude: 130.40165) == base)
        // The next cell over, and ~400 m away: each worth its own address.
        #expect(PlaceCellKey.key(latitude: 33.5914, longitude: 130.4017) != base)
        #expect(PlaceCellKey.key(latitude: 33.5940, longitude: 130.4017) != base)
    }

    @Test func theCellKeyIsStableAndBuiltFromIntegers() {
        // The key is a database primary key, so it must not drift with
        // formatting or locale.
        let first = PlaceCellKey.key(latitude: -8.6500, longitude: 115.2167)
        let second = PlaceCellKey.key(latitude: -8.6500, longitude: 115.2167)
        #expect(first == second)
        #expect(first == "-8650_115217")
    }

    @Test func theAntimeridianAndEquatorDoNotSplitAPlace() {
        // 180 and -180 are the same meridian; two keys there would geocode the
        // same spot twice.
        #expect(
            PlaceCellKey.key(latitude: 0, longitude: 180)
                == PlaceCellKey.key(latitude: 0, longitude: -180)
        )
        #expect(PlaceCellKey.key(latitude: 0, longitude: 0) == "0_0")
    }

    @Test func unusableCoordinatesHaveNoCell() {
        #expect(PlaceCellKey.key(latitude: .nan, longitude: 0) == nil)
        #expect(PlaceCellKey.key(latitude: 0, longitude: .infinity) == nil)
        #expect(PlaceCellKey.key(latitude: 91, longitude: 0) == nil)
    }

    @Test func theGeocodedPointIsTheCellCentre() {
        // Every photo in a cell has to be described by the same point, or the
        // cache would depend on which photo asked first.
        let a = PlaceCellKey.center(latitude: 33.59041, longitude: 130.40172)
        let b = PlaceCellKey.center(latitude: 33.59049, longitude: 130.40169)
        #expect(a?.latitude == b?.latitude)
        #expect(a?.longitude == b?.longitude)
    }

    @Test func searchTextFoldsDiacriticsSoUnaccentedTypingMatches() {
        let place = ResolvedPlace(
            locality: "Đà Nẵng",
            adminArea: "Đà Nẵng",
            country: "Việt Nam",
            countryCode: "VN"
        )
        let text = PlaceSearchText.build(from: place)
        #expect(text != nil)
        // Both sides normalize the same way, which is the whole contract.
        #expect(text?.contains(PlaceSearchText.normalized("da nang")) == true)
        #expect(text?.contains(PlaceSearchText.normalized("viet nam")) == true)
        // "Đà Nẵng" appeared as both city and province; it is stored once.
        #expect(text == "da nang viet nam vn")
    }

    @Test func lettersThatAreNotDiacriticsAreStillReduced() {
        // `Đ` is a letter, not a base plus a mark, so `folding` alone leaves it —
        // and "da nang" stops finding "Đà Nẵng". Same for the Nordic set.
        #expect(PlaceSearchText.normalized("Đà Nẵng") == "da nang")
        #expect(PlaceSearchText.normalized("Ørsted") == "orsted")
        #expect(PlaceSearchText.normalized("Łódź") == "lodz")
        // Scripts with no Latin form are left intact rather than mangled.
        #expect(PlaceSearchText.normalized("福岡市") == "福岡市")
    }

    @Test func punctuationBecomesWordBoundaries() {
        #expect(PlaceSearchText.normalized("Fukuoka-shi, Fukuoka") == "fukuoka shi fukuoka")
        #expect(PlaceSearchText.normalized("  St.  Mary's   ") == "st mary s")
        #expect(PlaceSearchText.normalized("") == "")
    }

    @Test func aPlaceWithNothingUsableStoresNothing() {
        #expect(PlaceSearchText.build(from: ResolvedPlace()) == nil)
        #expect(ResolvedPlace().isEmpty)
        #expect(ResolvedPlace(locality: "   ").isEmpty)
        #expect(PlaceSearchText.build(from: ResolvedPlace(name: "Ohori Park")) == "ohori park")
    }

    @Test func theDisplayTitlePrefersTheMostSpecificLabel() {
        #expect(
            ResolvedPlace(name: "Ohori Park", locality: "Fukuoka").displayTitle == "Ohori Park"
        )
        #expect(ResolvedPlace(locality: "Fukuoka", country: "Japan").displayTitle == "Fukuoka")
        #expect(ResolvedPlace(country: "Japan").displayTitle == "Japan")
        #expect(ResolvedPlace().displayTitle == nil)
    }
}
