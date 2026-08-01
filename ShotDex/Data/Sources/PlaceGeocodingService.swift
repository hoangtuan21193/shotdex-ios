import CoreLocation
import Foundation
import MapKit

/// Turns coordinates into addresses, once per place, and remembers the answer.
///
/// Every reverse geocode in the app goes through here: the indexing pass that
/// fills `photo_metadata.place*` and the metadata panel that shows one photo's
/// location. Both want the same thing, and Apple's geocoders are the scarcest
/// resource in the app — rate-limited per app, network-backed, and unforgiving
/// when hammered — so there is exactly one gate in front of them.
///
/// Three things make bulk geocoding a library survivable:
/// - **One request per cell.** Callers pass a `PlaceCellKey`, so a hundred photos
///   from one afternoon in one park cost one request.
/// - **A cache that outlives the process.** `place_cells` is on disk, so
///   re-indexing, relaunching, or adding photos to a place already visited needs
///   no network at all.
/// - **A pace, and a backoff.** Requests are spaced out, and a throttle or a
///   dropped connection widens the gap instead of retrying into the wall.
actor PlaceGeocodingService {
    /// What one lookup produced.
    enum Outcome: Equatable, Sendable {
        case resolved(ResolvedPlace)
        /// The geocoder answered, and there is genuinely nothing here (mid-ocean,
        /// unmapped desert). Counts against the cell's retry budget.
        case empty
        /// No answer: offline, throttled, or the service failed. Costs the cell
        /// nothing — it will be asked again on a later run.
        case unavailable
    }

    /// Minimum spacing between requests. Apple does not publish the limit; this
    /// is deliberately conservative, because being throttled costs far more than
    /// going slowly — a throttled app gets errors for a while, not just one.
    private static let requestInterval = Duration.milliseconds(1_200)
    private static let initialBackoff = Duration.seconds(4)
    private static let maximumBackoff = Duration.seconds(60)

    private let store: PlaceStore
    private var nextRequestAt = Date.distantPast
    private var backoff: Duration?

    init(store: PlaceStore) {
        self.store = store
    }

    /// Resolves one cell and writes it to every photo waiting on it.
    ///
    /// Checks the on-disk cache first, so a cell the library has seen before
    /// returns without touching the network.
    func resolveCell(
        key: String,
        latitude: Double,
        longitude: Double,
        locale: Locale = .current
    ) async -> Outcome {
        let localeIdentifier = locale.identifier
        if let cached = try? store.cachedCell(key: key, localeIdentifier: localeIdentifier) {
            if cached.resolvedAt != nil {
                try? store.applyCached(cached)
                return .resolved(cached.place)
            }
            if cached.isExhausted {
                try? store.applyCached(cached)
                return .empty
            }
        }

        // Geocode the cell centre rather than one photo's coordinates, so the
        // cache entry does not depend on which photo asked first.
        let center = PlaceCellKey.center(latitude: latitude, longitude: longitude)
            ?? (latitude: latitude, longitude: longitude)
        let outcome = await lookup(
            latitude: center.latitude,
            longitude: center.longitude,
            locale: locale
        )
        switch outcome {
        case .resolved(let place):
            try? store.save(
                place,
                cellKey: key,
                latitude: center.latitude,
                longitude: center.longitude,
                localeIdentifier: localeIdentifier
            )
        case .empty:
            try? store.recordFailure(
                cellKey: key,
                latitude: center.latitude,
                longitude: center.longitude,
                localeIdentifier: localeIdentifier
            )
        case .unavailable:
            break
        }
        return outcome
    }

    /// One-off lookup for a single coordinate, for the metadata panel. Shares the
    /// pacing and the cell cache with the indexing pass, so opening photo after
    /// photo from the same trip is free.
    func place(
        latitude: Double,
        longitude: Double,
        locale: Locale = .current
    ) async -> ResolvedPlace? {
        guard let key = PlaceCellKey.key(latitude: latitude, longitude: longitude) else {
            return nil
        }
        if let cached = try? store.cachedCell(key: key, localeIdentifier: locale.identifier),
           cached.resolvedAt != nil {
            return cached.place
        }
        if case .resolved(let place) = await resolveCell(
            key: key,
            latitude: latitude,
            longitude: longitude,
            locale: locale
        ) {
            return place
        }
        return nil
    }

    /// True while the service is backing off — the indexing pass stops for this
    /// run rather than queueing requests it knows will fail.
    var isBackingOff: Bool { backoff != nil }

    // MARK: Network

    private func lookup(
        latitude: Double,
        longitude: Double,
        locale: Locale
    ) async -> Outcome {
        await waitForTurn()
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let outcome: Outcome
        if #available(iOS 26.0, *) {
            outcome = await modernLookup(location: location, locale: locale)
        } else {
            outcome = await legacyLookup(location: location, locale: locale)
        }
        switch outcome {
        case .resolved, .empty:
            // A real answer of either kind means the service is talking to us.
            backoff = nil
        case .unavailable:
            let next = backoff.map { min($0 * 2, Self.maximumBackoff) } ?? Self.initialBackoff
            backoff = next
            nextRequestAt = Date().addingTimeInterval(next.seconds)
        }
        return outcome
    }

    private func waitForTurn() async {
        let wait = nextRequestAt.timeIntervalSinceNow
        if wait > 0 {
            try? await Task.sleep(for: .seconds(wait))
        }
        nextRequestAt = Date().addingTimeInterval(Self.requestInterval.seconds)
    }

    @available(iOS 26.0, *)
    private func modernLookup(location: CLLocation, locale: Locale) async -> Outcome {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return .empty
        }
        request.preferredLocale = locale
        do {
            guard let item = try await request.mapItems.first else { return .empty }
            let representations = item.addressRepresentations
            let place = ResolvedPlace(
                name: item.name,
                locality: representations?.cityWithContext,
                adminArea: representations?.regionName,
                address: representations?.fullAddress(includingRegion: true, singleLine: true)
                    ?? item.address?.fullAddress.replacingOccurrences(of: "\n", with: ", ")
            )
            return place.isEmpty ? .empty : .resolved(place)
        } catch {
            return Self.classify(error)
        }
    }

    private func legacyLookup(location: CLLocation, locale: Locale) async -> Outcome {
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(
                location,
                preferredLocale: locale
            )
            guard let placemark = placemarks.first else { return .empty }
            let place = ResolvedPlace(
                name: placemark.name,
                subLocality: placemark.subLocality,
                locality: placemark.locality ?? placemark.subAdministrativeArea,
                adminArea: placemark.administrativeArea,
                country: placemark.country,
                countryCode: placemark.isoCountryCode,
                address: Self.singleLineAddress(placemark)
            )
            return place.isEmpty ? .empty : .resolved(place)
        } catch {
            return Self.classify(error)
        }
    }

    /// Separates "there is nothing here" from "we could not ask".
    ///
    /// Only the first should count against a cell's retry budget: treating a
    /// flight-mode failure as a real answer would permanently label a whole trip
    /// as having no location.
    private static func classify(_ error: Error) -> Outcome {
        if let clError = error as? CLError {
            switch clError.code {
            case .geocodeFoundNoResult, .geocodeFoundPartialResult:
                return .empty
            default:
                return .unavailable
            }
        }
        if let mkError = error as? MKError, mkError.code == .placemarkNotFound {
            return .empty
        }
        return .unavailable
    }

    private static func singleLineAddress(_ placemark: CLPlacemark) -> String? {
        var seen = Set<String>()
        let parts = [
            placemark.subLocality,
            placemark.locality,
            placemark.administrativeArea,
            placemark.postalCode,
            placemark.country,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && seen.insert($0).inserted }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

private extension Duration {
    /// Seconds as a `TimeInterval`, for the `Date`-based pacing above.
    var seconds: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
