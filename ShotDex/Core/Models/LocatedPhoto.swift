import CoreLocation
import Foundation
import GRDB

/// One indexed photo reduced to what a map needs: where it was taken, when,
/// and the coarse place name the geocoding pass resolved.
struct LocatedPhoto: Codable, Equatable, Identifiable, Sendable, FetchableRecord {
    var assetId: String
    var creationDate: Int?
    var latitude: Double
    var longitude: Double
    var placeLocality: String?
    var placeAdminArea: String?
    var placeCountry: String?

    var id: String { assetId }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var creationDateValue: Date? {
        creationDate.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    /// Coarsest-to-finest name for a cluster label: the town if the geocoder
    /// found one, else the region, else the country.
    var placeLabel: String? {
        placeLocality ?? placeAdminArea ?? placeCountry
    }
}
