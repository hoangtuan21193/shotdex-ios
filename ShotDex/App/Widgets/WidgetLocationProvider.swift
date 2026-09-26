import CoreLocation
import Foundation

/// One coarse fix, for the weather widget and nothing else.
///
/// Deliberately the weakest request the framework offers: when-in-use only,
/// `reduced` accuracy (a few kilometres — the weather is the same across a
/// city), and asked for only when the user taps Allow Location Access in the
/// weather widget's settings. Nothing here prompts on its own. The coordinate
/// never leaves this device except as the rounded pair in the weather
/// request, and is never stored.
@MainActor
final class WidgetLocationProvider: NSObject {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var authorizationContinuation: CheckedContinuation<Bool, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    /// Authorization as the app talks about it, so views never import
    /// CoreLocation. Same three cases as the calendar's, so the two settings
    /// rows read the same way.
    enum Access {
        case notDetermined
        case granted
        case denied
    }

    var access: Access {
        switch authorizationStatus {
        case .notDetermined: .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: .granted
        default: .denied
        }
    }

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: true
        default: false
        }
    }

    /// Asks the system for permission. Only ever called from the weather
    /// widget's own settings section, when the user taps the button that
    /// explains what the location is for — nothing in the app prompts on its
    /// own, least of all on launch. Returns once the user has answered, so
    /// the settings row can show the outcome rather than guess at it.
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard authorizationStatus == .notDetermined else { return isAuthorized }
        return await withCheckedContinuation { continuation in
            self.authorizationContinuation?.resume(returning: self.isAuthorized)
            self.authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Returns one fix, or nil when permission was never granted. It never
    /// asks: a user who has not opted in through Settings gets a weather
    /// widget that says it is not set up, not a prompt.
    func currentLocation() async -> CLLocation? {
        guard isAuthorized else { return nil }
        // A cached fix is fine for the weather and costs no radio.
        if let last = manager.location, last.timestamp.timeIntervalSinceNow > -1800 {
            return last
        }
        return await withCheckedContinuation { continuation in
            self.continuation?.resume(returning: nil)
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    private func finish(with location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }

    private func finishAuthorization() {
        guard authorizationStatus != .notDetermined else { return }
        authorizationContinuation?.resume(returning: isAuthorized)
        authorizationContinuation = nil
    }
}

extension WidgetLocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let last = locations.last
        Task { @MainActor in self.finish(with: last) }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in self.finish(with: nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.finishAuthorization() }
    }
}
