import Foundation

/// Sensor formats recognized by the app, ordered roughly by sensor size.
enum SensorFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case mediumFormat = "Medium Format"
    case fullFrame = "Full Frame"
    case apsH = "APS-H"
    case apsC = "APS-C"
    case microFourThirds = "Micro Four Thirds"
    case oneInch = "1-inch"
    case compact = "Compact"
    case smartphone = "Smartphone"
    case unknown = "Unknown"

    var id: String { rawValue }

    var displayName: String { rawValue }

    /// Typical crop factor for the format, used as a fallback when the
    /// sensor database does not provide a per-camera value.
    var typicalCropFactor: Double? {
        switch self {
        case .mediumFormat: 0.79
        case .fullFrame: 1.0
        case .apsH: 1.3
        case .apsC: 1.5
        case .microFourThirds: 2.0
        case .oneInch: 2.7
        case .compact: 4.5
        case .smartphone: 6.0
        case .unknown: nil
        }
    }
}
