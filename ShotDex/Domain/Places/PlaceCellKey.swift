import CoreGraphics
import Foundation

/// Groups coordinates into a grid so photos taken in the same spot share one
/// reverse-geocoding request.
///
/// This is the whole reason indexing place names is feasible. Apple's geocoders
/// are rate-limited hard — a request per photo would take a library of any size
/// well past a day and mostly earn throttling errors. Photos cluster in space
/// though: a trip is a few dozen places, not a few thousand, so one address per
/// cell collapses the work by one to two orders of magnitude and the result is
/// cached in `place_cells` for good.
///
/// The cell is 0.001° on a side — about 110 m of latitude, less longitude the
/// further from the equator. Small enough that two cells never share a street,
/// coarse enough that a burst walked around a courtyard is one request.
///
/// A place sitting on a cell boundary does pay for both cells; every fixed grid
/// has that property and the cost is a handful of extra requests, not a
/// different order of magnitude, so it buys nothing to be cleverer here.
enum PlaceCellKey {
    /// Degrees per cell. Also the rounding step, so the key is the cell index.
    static let degreesPerCell = 0.001

    /// Stable key for a coordinate, or nil when it is not a usable position.
    ///
    /// The key must stay identical across app launches and OS versions — it is a
    /// database primary key — so it is built from integers, never from formatted
    /// floating-point text.
    static func key(latitude: Double, longitude: Double) -> String? {
        guard latitude.isFinite, longitude.isFinite,
              latitude >= -90, latitude <= 90
        else { return nil }
        let normalizedLongitude = normalizedLongitude(longitude)
        let latitudeCell = cellIndex(latitude)
        let longitudeCell = cellIndex(normalizedLongitude)
        return "\(latitudeCell)_\(longitudeCell)"
    }

    /// Centre of the cell a coordinate falls in — what actually gets geocoded,
    /// so every photo in the cell is described by the same point.
    static func center(latitude: Double, longitude: Double) -> (latitude: Double, longitude: Double)? {
        guard key(latitude: latitude, longitude: longitude) != nil else { return nil }
        return (
            Double(cellIndex(latitude)) * degreesPerCell,
            Double(cellIndex(normalizedLongitude(longitude))) * degreesPerCell
        )
    }

    private static func cellIndex(_ degrees: Double) -> Int {
        Int((degrees / degreesPerCell).rounded())
    }

    /// Wraps longitude into `-180..<180`, so the antimeridian does not hand the
    /// same place two different keys.
    private static func normalizedLongitude(_ longitude: Double) -> Double {
        var wrapped = longitude.truncatingRemainder(dividingBy: 360)
        if wrapped >= 180 { wrapped -= 360 }
        if wrapped < -180 { wrapped += 360 }
        return wrapped
    }
}
