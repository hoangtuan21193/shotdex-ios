import CoreLocation
import Foundation

/// One group of photos the map draws as a single pin.
struct PlaceCluster: Identifiable, Hashable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let assetIds: [String]
    /// The place name shared by most photos in the group, or a coordinate when
    /// none of them has been reverse-geocoded yet.
    let title: String
    let subtitle: String?
    /// Newest photo in the group — what the pin shows.
    let coverAssetId: String

    static func == (lhs: PlaceCluster, rhs: PlaceCluster) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Groups located photos into map pins.
///
/// A fixed grid in degrees rather than distance-based clustering: the cell size
/// follows the visible span, so a pin at world zoom covers a country and a pin
/// at street zoom covers a block, and the same photo always lands in the same
/// cell at the same zoom. Distance clustering would reorder pins as the user
/// pans, which reads as pins jumping around.
enum PlaceClustering {
    /// How many cells fit across the visible span. More cells means finer
    /// pins; this is tuned so a screenful holds a readable number of them.
    private static let cellsAcrossSpan: Double = 7
    /// Never go finer than roughly a city block, or a burst taken in one spot
    /// scatters into a dozen identical pins.
    private static let minimumCellDegrees: Double = 0.0004

    static func clusters(
        for photos: [LocatedPhoto],
        spanDegrees: Double
    ) -> [PlaceCluster] {
        guard !photos.isEmpty else { return [] }
        let cell = max(minimumCellDegrees, spanDegrees / cellsAcrossSpan)

        var groups: [String: [LocatedPhoto]] = [:]
        var order: [String] = []
        for photo in photos {
            let key = cellKey(latitude: photo.latitude, longitude: photo.longitude, cell: cell)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(photo)
        }

        return order.compactMap { key in
            guard let members = groups[key], let cover = members.first else { return nil }
            // Centroid rather than cell centre: a pin should sit on the photos,
            // not on the corner of an invisible grid.
            let latitude = members.reduce(0) { $0 + $1.latitude } / Double(members.count)
            let longitude = members.reduce(0) { $0 + $1.longitude } / Double(members.count)
            let label = dominantLabel(in: members)
            return PlaceCluster(
                id: key,
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                assetIds: members.map(\.assetId),
                title: label ?? coordinateLabel(latitude: latitude, longitude: longitude),
                subtitle: dateRangeLabel(for: members),
                coverAssetId: cover.assetId
            )
        }
    }

    private static func cellKey(latitude: Double, longitude: Double, cell: Double) -> String {
        let row = (latitude / cell).rounded(.down)
        let column = (longitude / cell).rounded(.down)
        return "\(Int(row)):\(Int(column))"
    }

    /// The most common resolved place name in the group. Photos in one cell can
    /// straddle a boundary, and the majority name is the honest label.
    private static func dominantLabel(in photos: [LocatedPhoto]) -> String? {
        var counts: [String: Int] = [:]
        for label in photos.compactMap(\.placeLabel) {
            counts[label, default: 0] += 1
        }
        return counts.max { $0.value < $1.value }?.key
    }

    private static func coordinateLabel(latitude: Double, longitude: Double) -> String {
        String(format: "%.3f, %.3f", latitude, longitude)
    }

    private static func dateRangeLabel(for photos: [LocatedPhoto]) -> String? {
        let dates = photos.compactMap(\.creationDateValue)
        guard let earliest = dates.min(), let latest = dates.max() else { return nil }
        if Calendar.current.isDate(earliest, inSameDayAs: latest) {
            return MetadataFormatter.dayHeader(earliest)
        }
        return MetadataFormatter.dateRange(earliest, latest)
    }
}
