import CoreLocation
import Foundation

/// A run of photos that reads as one journey: taken over consecutive days, far
/// enough from where the library's photos usually come from.
struct Trip: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let assetIds: [String]
    let coverAssetId: String
    let coordinate: CLLocationCoordinate2D

    var dateRangeLabel: String {
        Calendar.current.isDate(start, inSameDayAs: end)
            ? MetadataFormatter.dayHeader(start)
            : MetadataFormatter.dateRange(start, end)
    }

    static func == (lhs: Trip, rhs: Trip) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Finds trips in a located, date-sorted library.
///
/// The rule is deliberately mechanical, not clever: a trip is a run of photos
/// with no gap longer than `maximumGapDays`, taken more than `homeRadiusKm`
/// from home, lasting at least `minimumDays` and holding at least
/// `minimumPhotos`. "Home" is simply the densest place in the library — where
/// most photos were taken — because a trip is defined by being away from the
/// ordinary, and no other signal for that is available offline.
enum TripGrouping {
    static let maximumGapDays = 2.0
    static let minimumDays = 1.0
    static let minimumPhotos = 8
    static let homeRadiusKm = 80.0

    static func trips(from photos: [LocatedPhoto]) -> [Trip] {
        let dated = photos
            .filter { $0.creationDateValue != nil }
            .sorted { ($0.creationDateValue ?? .distantPast) < ($1.creationDateValue ?? .distantPast) }
        guard dated.count >= minimumPhotos else { return [] }

        let home = homeCoordinate(of: dated)
        var runs: [[LocatedPhoto]] = []
        var current: [LocatedPhoto] = []

        for photo in dated {
            guard let date = photo.creationDateValue else { continue }
            let isAway = home.map { distanceKm(photo.coordinate, $0) > homeRadiusKm } ?? true
            guard isAway else {
                // A photo taken back home ends the journey, whatever the dates
                // either side of it say.
                if !current.isEmpty { runs.append(current) }
                current = []
                continue
            }
            // The gap is measured against the last photo *of this run*, not the
            // last photo seen: an unrelated shot in between must not reset the
            // clock the run is judged by.
            let continuesRun = current.last?.creationDateValue.map {
                date.timeIntervalSince($0) <= maximumGapDays * 86_400
            } ?? true
            if continuesRun {
                current.append(photo)
            } else {
                runs.append(current)
                current = [photo]
            }
        }
        if !current.isEmpty { runs.append(current) }

        return merged(runs).compactMap(trip(from:)).reversed()
    }

    /// Joins consecutive runs that are plainly the same journey: same dominant
    /// place, and no more than `maximumGapDays` between them.
    ///
    /// Runs get cut by a single photo timestamped back home — a shot with a
    /// wrong clock, one imported from another device, or a night spent at home
    /// mid-journey. Without this, one holiday reads as three.
    private static func merged(_ runs: [[LocatedPhoto]]) -> [[LocatedPhoto]] {
        var result: [[LocatedPhoto]] = []
        for run in runs {
            guard let previous = result.last,
                  let previousEnd = previous.last?.creationDateValue,
                  let start = run.first?.creationDateValue,
                  start.timeIntervalSince(previousEnd) <= maximumGapDays * 86_400,
                  dominantLabel(in: previous) == dominantLabel(in: run)
            else {
                result.append(run)
                continue
            }
            result[result.count - 1] = previous + run
        }
        return result
    }

    private static func dominantLabel(in run: [LocatedPhoto]) -> String? {
        var counts: [String: Int] = [:]
        for label in run.compactMap(\.placeLabel) { counts[label, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key
    }

    private static func trip(from run: [LocatedPhoto]) -> Trip? {
        guard run.count >= minimumPhotos,
              let start = run.first?.creationDateValue,
              let end = run.last?.creationDateValue,
              end.timeIntervalSince(start) >= minimumDays * 86_400
        else { return nil }

        let title = dominantLabel(in: run) ?? String(localized: "Trip")
        let latitude = run.reduce(0) { $0 + $1.latitude } / Double(run.count)
        let longitude = run.reduce(0) { $0 + $1.longitude } / Double(run.count)

        return Trip(
            id: "\(Int(start.timeIntervalSince1970))-\(run.count)",
            title: title,
            start: start,
            end: end,
            assetIds: run.map(\.assetId),
            // Middle of the run rather than the first frame: the arrival shot
            // is rarely the one worth showing.
            coverAssetId: run[run.count / 2].assetId,
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        )
    }

    /// Where most photos were taken, rounded to roughly a city, or `nil` when
    /// the library has no clear centre of gravity.
    private static func homeCoordinate(of photos: [LocatedPhoto]) -> CLLocationCoordinate2D? {
        let cell = 0.5
        var counts: [String: (count: Int, latitude: Double, longitude: Double)] = [:]
        for photo in photos {
            let key = "\(Int((photo.latitude / cell).rounded())):\(Int((photo.longitude / cell).rounded()))"
            var entry = counts[key] ?? (0, 0, 0)
            entry.count += 1
            entry.latitude += photo.latitude
            entry.longitude += photo.longitude
            counts[key] = entry
        }
        guard let best = counts.values.max(by: { $0.count < $1.count }),
              // A "home" that holds a fifth of the library is a home; anything
              // less and the user simply photographs everywhere.
              Double(best.count) >= Double(photos.count) * 0.2
        else { return nil }
        return CLLocationCoordinate2D(
            latitude: best.latitude / Double(best.count),
            longitude: best.longitude / Double(best.count)
        )
    }

    private static func distanceKm(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D
    ) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 1000
    }
}
