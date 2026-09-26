import CoreLocation
import Foundation
import WidgetKit

/// Fetches the weather for the widgets, when a weather widget is placed.
///
/// **Why not WeatherKit**: WeatherKit needs a capability on the App ID and a
/// paid-account entitlement, and it is unavailable in a build that does not
/// carry it — the widget would ship dark for anyone building this app
/// themselves. Open-Meteo needs no key and no account, answers in one request,
/// and is given a coordinate rounded to two decimals (about a kilometre), so
/// the request says roughly which town, never which building.
///
/// It is also the only network call in the app besides place-name lookup, and
/// it happens only because the user placed a weather widget.
@MainActor
struct WeatherSnapshotWriter {
    let location: WidgetLocationProvider

    /// A reading is refetched when it is older than this.
    private static let refreshAfter: TimeInterval = 30 * 60

    /// Fetches and writes when a weather widget is placed and the last reading
    /// is old. Returns false when nothing was written, which is the normal
    /// case on most launches.
    @discardableResult
    func write(now: Date = .now, force: Bool = false) async -> Bool {
        guard let container = WidgetSharedContainer.url else { return false }
        let isNeeded = await InstalledWidgets.needsWeather(
            settings: PhotoWidgetSettingsFile.read()
        )
        guard force || isNeeded else { return false }
        if !force, let existing = WeatherSnapshot.read(),
           now.timeIntervalSince(existing.updatedAt) < Self.refreshAfter {
            return false
        }
        guard let fix = await location.currentLocation() else { return false }
        guard let reading = await Self.fetch(
            latitude: fix.coordinate.latitude,
            longitude: fix.coordinate.longitude
        ) else { return false }

        let place = await Self.placeName(for: fix)
        let snapshot = WeatherSnapshot(
            temperatureCelsius: reading.temperature,
            highCelsius: reading.high,
            lowCelsius: reading.low,
            conditionCode: reading.code,
            placeName: place,
            isNight: reading.isNight,
            updatedAt: now
        )
        try? WidgetSharedContainer.encode(
            snapshot,
            to: container.appendingPathComponent(WeatherSnapshot.fileName)
        )
        WidgetCenter.shared.reloadTimelines(ofKind: PhotoWidgetIdentity.widgetKind)
        return true
    }

    // MARK: Fetch

    struct Reading: Sendable {
        var temperature: Double
        var high: Double?
        var low: Double?
        var code: Int
        var isNight: Bool
    }

    /// The API's shape, kept private and minimal: four numbers out of one
    /// request, decoded by name so a field appearing upstream changes nothing.
    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
        }
        let current: Current
        let daily: Daily?
    }

    nonisolated static func requestURL(latitude: Double, longitude: Double) -> URL? {
        // Two decimals, so the request carries a town rather than an address.
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        return components?.url
    }

    private nonisolated static func fetch(latitude: Double, longitude: Double) async -> Reading? {
        guard let url = requestURL(latitude: latitude, longitude: longitude) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data)
        else { return nil }
        return Reading(
            temperature: decoded.current.temperature_2m,
            high: decoded.daily?.temperature_2m_max.first,
            low: decoded.daily?.temperature_2m_min.first,
            code: decoded.current.weather_code,
            isNight: decoded.current.is_day == 0
        )
    }

    /// The town the reading is for. Best-effort: a failed lookup just means
    /// the widget shows the temperature without a place under it.
    private nonisolated static func placeName(for location: CLLocation) async -> String? {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let placemark = placemarks?.first else { return nil }
        return placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea
    }
}
