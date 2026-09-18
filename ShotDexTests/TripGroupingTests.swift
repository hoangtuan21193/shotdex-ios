import Foundation
import Testing
@testable import ShotDex

struct TripGroupingTests {

    /// Builds a located photo `daysAgo` before a fixed reference instant.
    private func photo(
        _ id: String,
        daysAgo: Double,
        latitude: Double,
        longitude: Double,
        locality: String? = nil
    ) -> LocatedPhoto {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        return LocatedPhoto(
            assetId: id,
            creationDate: Int(reference.addingTimeInterval(-daysAgo * 86_400).timeIntervalSince1970),
            latitude: latitude,
            longitude: longitude,
            placeLocality: locality,
            placeAdminArea: nil,
            placeCountry: nil
        )
    }

    /// Hanoi, used as the library's centre of gravity in these fixtures.
    private let home = (21.0278, 105.8342)
    /// Paris — far enough from Hanoi to count as away under any threshold.
    private let away = (48.8566, 2.3522)

    private func homePhotos(count: Int, startingDaysAgo: Double) -> [LocatedPhoto] {
        (0..<count).map {
            photo(
                "home-\($0)",
                daysAgo: startingDaysAgo + Double($0) * 5,
                latitude: home.0,
                longitude: home.1,
                locality: "Hanoi"
            )
        }
    }

    @Test func findsARunOfDaysSpentAwayFromHome() {
        var photos = homePhotos(count: 40, startingDaysAgo: 100)
        // Four days in Paris, six photos a day.
        for day in 0..<4 {
            for shot in 0..<6 {
                photos.append(
                    photo(
                        "paris-\(day)-\(shot)",
                        daysAgo: 30 - Double(day) - Double(shot) * 0.1,
                        latitude: away.0,
                        longitude: away.1,
                        locality: "Paris"
                    )
                )
            }
        }

        let trips = TripGrouping.trips(from: photos)

        #expect(trips.count == 1)
        #expect(trips.first?.title == "Paris")
        #expect(trips.first?.assetIds.count == 24)
    }

    @Test func ignoresPhotosTakenNearHome() {
        let trips = TripGrouping.trips(from: homePhotos(count: 60, startingDaysAgo: 1))
        #expect(trips.isEmpty)
    }

    @Test func ignoresARunTooShortToBeAJourney() {
        var photos = homePhotos(count: 40, startingDaysAgo: 100)
        // Six photos in one afternoon: away, but not a trip.
        for shot in 0..<6 {
            photos.append(
                photo(
                    "day-\(shot)",
                    daysAgo: 20 - Double(shot) * 0.05,
                    latitude: away.0,
                    longitude: away.1,
                    locality: "Paris"
                )
            )
        }

        #expect(TripGrouping.trips(from: photos).isEmpty)
    }

    @Test func joinsARunCutByASingleStrayPhotoAtHome() {
        var photos = homePhotos(count: 40, startingDaysAgo: 200)
        // Four days in Paris…
        for day in 0..<4 {
            for shot in 0..<6 {
                photos.append(
                    photo(
                        "paris-\(day)-\(shot)",
                        daysAgo: 30 - Double(day) - Double(shot) * 0.1,
                        latitude: away.0,
                        longitude: away.1,
                        locality: "Paris"
                    )
                )
            }
        }
        // …with one photo timestamped back home in the middle of them.
        photos.append(
            photo("stray", daysAgo: 28.5, latitude: home.0, longitude: home.1, locality: "Hanoi")
        )

        let trips = TripGrouping.trips(from: photos)

        #expect(trips.count == 1)
        #expect(trips.first?.assetIds.count == 24)
    }

    @Test func splitsTwoJourneysSeparatedByTimeAtHome() {
        var photos = homePhotos(count: 40, startingDaysAgo: 200)
        for (index, base) in [120.0, 40.0].enumerated() {
            for day in 0..<3 {
                for shot in 0..<6 {
                    photos.append(
                        photo(
                            "trip\(index)-\(day)-\(shot)",
                            daysAgo: base - Double(day) - Double(shot) * 0.1,
                            latitude: away.0,
                            longitude: away.1,
                            locality: "Paris"
                        )
                    )
                }
            }
        }

        let trips = TripGrouping.trips(from: photos)

        #expect(trips.count == 2)
        // Newest first, as the screen lists them.
        let starts = trips.compactMap(\.start)
        #expect(starts == starts.sorted(by: >))
    }
}
