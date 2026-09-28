import ShotDexKit

/// The seven Calibration sliders, in the order Lightroom lists them
/// (FS-03.15a §3). Each writes one field of `PhotoCalibration`, −1…1 (UI ±100).
enum EditorCalibrationControl: String, CaseIterable, Identifiable, Sendable {
    case shadowTint
    case redHue, redSaturation
    case greenHue, greenSaturation
    case blueHue, blueSaturation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shadowTint: "Shadow Tint"
        case .redHue: "Red Hue"
        case .redSaturation: "Red Saturation"
        case .greenHue: "Green Hue"
        case .greenSaturation: "Green Saturation"
        case .blueHue: "Blue Hue"
        case .blueSaturation: "Blue Saturation"
        }
    }

    /// The row's own word under its section header — the full title does
    /// not fit a phone row ("Green Saturation" truncates at 390pt).
    var rowTitle: String {
        switch self {
        case .shadowTint: "Tint"
        case .redHue, .greenHue, .blueHue: "Hue"
        case .redSaturation, .greenSaturation, .blueSaturation: "Saturation"
        }
    }

    /// The four headers Lightroom groups these under.
    enum Section: String, CaseIterable, Identifiable {
        case shadows = "Shadows"
        case red = "Red Primary"
        case green = "Green Primary"
        case blue = "Blue Primary"
        var id: String { rawValue }
        var controls: [EditorCalibrationControl] {
            EditorCalibrationControl.allCases.filter { $0.section == self }
        }
    }

    var section: Section {
        switch self {
        case .shadowTint: .shadows
        case .redHue, .redSaturation: .red
        case .greenHue, .greenSaturation: .green
        case .blueHue, .blueSaturation: .blue
        }
    }

    var keyPath: WritableKeyPath<PhotoCalibration, Double> {
        switch self {
        case .shadowTint: \.shadowTint
        case .redHue: \.redHue
        case .redSaturation: \.redSaturation
        case .greenHue: \.greenHue
        case .greenSaturation: \.greenSaturation
        case .blueHue: \.blueHue
        case .blueSaturation: \.blueSaturation
        }
    }

    /// The primary this row moves, in degrees — for its track's colours.
    var primaryDegrees: Double? {
        switch self {
        case .shadowTint: nil
        case .redHue, .redSaturation: 0
        case .greenHue, .greenSaturation: 120
        case .blueHue, .blueSaturation: 240
        }
    }

    var isHue: Bool { self == .redHue || self == .greenHue || self == .blueHue }
}
