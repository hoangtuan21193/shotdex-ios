import Foundation

/// The weather the app fetched, for the widgets to read.
///
/// The widget never asks for the weather itself. A widget extension has no
/// location authorization of its own, its network calls happen on WidgetKit's
/// schedule rather than the user's, and this app's rule is already that the
/// extensions read files the app wrote. So the app fetches — only when a
/// weather widget is actually configured — and leaves the result here.
struct WeatherSnapshot: Codable, Equatable {
    /// Degrees Celsius, always. The unit the user reads is applied at the last
    /// moment (`WeatherFormat`), so changing it needs no new fetch.
    var temperatureCelsius: Double
    var highCelsius: Double?
    var lowCelsius: Double?
    /// WMO weather code, the vocabulary the fetch speaks.
    var conditionCode: Int
    /// Where this is the weather for, in words, or nil when the place could
    /// not be named.
    var placeName: String?
    /// True when the sun was down at the place the reading is for, so the
    /// symbol can be the night one.
    var isNight: Bool
    var updatedAt: Date

    static let fileName = "weather.json"

    /// A reading older than this is not shown as if it were now.
    static let staleAfter: TimeInterval = 3 * 3600

    static func read() -> WeatherSnapshot? {
        guard let url = WidgetSharedContainer.url?.appendingPathComponent(fileName)
        else { return nil }
        return WidgetSharedContainer.decode(WeatherSnapshot.self, at: url)
    }

    func isStale(at date: Date = .now) -> Bool {
        date.timeIntervalSince(updatedAt) > Self.staleAfter
    }
}

/// Turning a weather reading into the words and the symbol on the widget.
/// Pure, and unit-tested: a wrong unit conversion is not something to discover
/// on a Home Screen.
enum WeatherFormat {
    static func celsiusToFahrenheit(_ celsius: Double) -> Double {
        celsius * 9 / 5 + 32
    }

    /// Whether this region reads temperatures in Celsius, when the user asked
    /// for "System".
    static func prefersCelsius(locale: Locale = .current) -> Bool {
        locale.measurementSystem != .us
    }

    static func usesCelsius(
        _ unit: PhotoWidgetSettings.TemperatureUnit,
        locale: Locale = .current
    ) -> Bool {
        switch unit {
        case .system: prefersCelsius(locale: locale)
        case .celsius: true
        case .fahrenheit: false
        }
    }

    /// `21°` — rounded, no decimal and no unit letter. A widget has room for
    /// the number, and the degree sign already says what it is.
    static func temperatureString(
        celsius: Double,
        unit: PhotoWidgetSettings.TemperatureUnit,
        locale: Locale = .current
    ) -> String {
        let value = usesCelsius(unit, locale: locale) ? celsius : celsiusToFahrenheit(celsius)
        return "\(Int(value.rounded()))°"
    }

    static func highLowString(
        highCelsius: Double?,
        lowCelsius: Double?,
        unit: PhotoWidgetSettings.TemperatureUnit,
        locale: Locale = .current
    ) -> String? {
        guard let highCelsius, let lowCelsius else { return nil }
        let high = temperatureString(celsius: highCelsius, unit: unit, locale: locale)
        let low = temperatureString(celsius: lowCelsius, unit: unit, locale: locale)
        return "H \(high)  L \(low)"
    }

    /// WMO code to the words a person would use. The codes come in bands, so
    /// this is a switch over ranges rather than a table of ninety-nine.
    static func conditionName(code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly Clear"
        case 2: "Partly Cloudy"
        case 3: "Cloudy"
        case 45, 48: "Fog"
        case 51, 53, 55: "Drizzle"
        case 56, 57: "Freezing Drizzle"
        case 61, 63, 65: "Rain"
        case 66, 67: "Freezing Rain"
        case 71, 73, 75, 77: "Snow"
        case 80, 81, 82: "Showers"
        case 85, 86: "Snow Showers"
        case 95: "Thunderstorms"
        case 96, 99: "Thunderstorms and Hail"
        default: "—"
        }
    }

    /// SF Symbol for the same code, switching to the night variants after dark
    /// where Apple ships one.
    static func symbolName(code: Int, isNight: Bool) -> String {
        switch code {
        case 0: isNight ? "moon.stars.fill" : "sun.max.fill"
        case 1: isNight ? "cloud.moon.fill" : "sun.min.fill"
        case 2: isNight ? "cloud.moon.fill" : "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55: "cloud.drizzle.fill"
        case 56, 57, 66, 67: "cloud.sleet.fill"
        case 61, 63, 65: "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 80, 81, 82: isNight ? "cloud.moon.rain.fill" : "cloud.sun.rain.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "thermometer.medium"
        }
    }
}
