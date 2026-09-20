import CoreLocation
import Foundation

/// One coarse fix, for the weather widget and nothing else.
///
/// Deliberately the weakest request the framework offers: when-in-use only,
/// `reduced` accuracy (a few kilometres — the weather is the same across a
/// city), and asked for only when a weather widget is actually placed. The
/// coordinate never leaves this device except as the rounded pair in the
/// weather request, and is never stored.
@MainActor
final class WidgetLocationProvider: NSObject {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: true
        default: false
        }
    }

    /// Asks for permission if it has never been asked, then returns one fix.
    /// Nil when the user said no, or when no fix arrived — the widget then
    /// says the weather is not set up rather than showing someone else's.
    func currentLocation() async -> CLLocation? {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            // The prompt is answered on another turn of the run loop; the
            // caller retries on the next foreground rather than blocking here.
            return nil
        }
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
}
