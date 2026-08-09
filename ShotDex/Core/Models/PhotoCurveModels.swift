import Foundation

/// One control point of a tone curve, in the unit square: `x` is the input level
/// and `y` the output, both 0…1 in display gamma.
struct CurvePoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// The four channels a point curve can shape: the RGB master (applied to all
/// three) and one each for Red, Green, Blue.
enum ToneCurveChannel: String, Codable, CaseIterable, Identifiable, Sendable {
    case rgb
    case red
    case green
    case blue

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rgb: "RGB"
        case .red: "Red"
        case .green: "Green"
        case .blue: "Blue"
        }
    }
}

/// A Lightroom-style point tone curve: four independent series of control points.
/// Identity is the straight line for every channel, and a channel that is still
/// the straight line adds no key to the encoded recipe — so an untouched Curve
/// leaves the JSON byte-compatible with builds that predate it, exactly like the
/// Color recipe does.
struct ToneCurveAdjustments: Codable, Equatable, Sendable {
    var rgb: [CurvePoint]
    var red: [CurvePoint]
    var green: [CurvePoint]
    var blue: [CurvePoint]

    /// The straight line: input maps to itself.
    static let linear = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]
    static let identity = ToneCurveAdjustments()

    init(
        rgb: [CurvePoint] = ToneCurveAdjustments.linear,
        red: [CurvePoint] = ToneCurveAdjustments.linear,
        green: [CurvePoint] = ToneCurveAdjustments.linear,
        blue: [CurvePoint] = ToneCurveAdjustments.linear
    ) {
        self.rgb = rgb
        self.red = red
        self.green = green
        self.blue = blue
    }

    var isIdentity: Bool {
        rgb == Self.linear
            && red == Self.linear
            && green == Self.linear
            && blue == Self.linear
    }

    subscript(_ channel: ToneCurveChannel) -> [CurvePoint] {
        get {
            switch channel {
            case .rgb: rgb
            case .red: red
            case .green: green
            case .blue: blue
            }
        }
        set {
            switch channel {
            case .rgb: rgb = newValue
            case .red: red = newValue
            case .green: green = newValue
            case .blue: blue = newValue
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case rgb, red, green, blue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rgb = try container.decodeIfPresent([CurvePoint].self, forKey: .rgb) ?? Self.linear
        red = try container.decodeIfPresent([CurvePoint].self, forKey: .red) ?? Self.linear
        green = try container.decodeIfPresent([CurvePoint].self, forKey: .green) ?? Self.linear
        blue = try container.decodeIfPresent([CurvePoint].self, forKey: .blue) ?? Self.linear
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if rgb != Self.linear { try container.encode(rgb, forKey: .rgb) }
        if red != Self.linear { try container.encode(red, forKey: .red) }
        if green != Self.linear { try container.encode(green, forKey: .green) }
        if blue != Self.linear { try container.encode(blue, forKey: .blue) }
    }
}
