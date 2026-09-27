import Foundation

/// One control point of a tone curve, in the unit square: `x` is the input level
/// and `y` the output, both 0…1 in display gamma.
public struct CurvePoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// The four channels a point curve can shape: the RGB master (applied to all
/// three) and one each for Red, Green, Blue.
public enum ToneCurveChannel: String, Codable, CaseIterable, Identifiable, Sendable {
    case rgb
    case red
    case green
    case blue

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .rgb: "RGB"
        case .red: "Red"
        case .green: "Green"
        case .blue: "Blue"
        }
    }
}

/// A named starting shape for the point curve — one tap in the Curve panel.
public struct ToneCurvePreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let points: [CurvePoint]
}

/// A Lightroom-style point tone curve: four independent series of control points.
/// Identity is the straight line for every channel, and a channel that is still
/// the straight line adds no key to the encoded recipe — so an untouched Curve
/// leaves the JSON byte-compatible with builds that predate it, exactly like the
/// Color recipe does.
public struct ToneCurveAdjustments: Codable, Equatable, Sendable {
    public var rgb: [CurvePoint]
    public var red: [CurvePoint]
    public var green: [CurvePoint]
    public var blue: [CurvePoint]

    /// The straight line: input maps to itself.
    public static let linear = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]
    public static let identity = ToneCurveAdjustments()

    /// The Curve panel's one-tap shapes, applied to whichever channel is showing.
    /// All monotone, all through sensible anchors, so each is a starting point the
    /// user then drags — not a look.
    public static let presets: [ToneCurvePreset] = [
        ToneCurvePreset(id: "linear", name: String(localized: "Linear"), points: linear),
        ToneCurvePreset(id: "softS", name: String(localized: "Soft S"), points: [
            CurvePoint(x: 0, y: 0), CurvePoint(x: 0.25, y: 0.22),
            CurvePoint(x: 0.75, y: 0.78), CurvePoint(x: 1, y: 1),
        ]),
        ToneCurvePreset(id: "strongS", name: String(localized: "Strong S"), points: [
            CurvePoint(x: 0, y: 0), CurvePoint(x: 0.25, y: 0.16),
            CurvePoint(x: 0.75, y: 0.84), CurvePoint(x: 1, y: 1),
        ]),
        ToneCurvePreset(id: "brighten", name: String(localized: "Brighten"), points: [
            CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.58), CurvePoint(x: 1, y: 1),
        ]),
        ToneCurvePreset(id: "darken", name: String(localized: "Darken"), points: [
            CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.42), CurvePoint(x: 1, y: 1),
        ]),
        ToneCurvePreset(id: "fade", name: String(localized: "Fade"), points: [
            CurvePoint(x: 0, y: 0.1), CurvePoint(x: 1, y: 1),
        ]),
        ToneCurvePreset(id: "matte", name: String(localized: "Matte"), points: [
            CurvePoint(x: 0, y: 0.12), CurvePoint(x: 0.5, y: 0.52), CurvePoint(x: 1, y: 0.92),
        ]),
    ]

    /// The region curve, baked in before the point curves (FS-03.15 D51).
    public var region = ParametricCurve.identity

    public init(
        rgb: [CurvePoint] = ToneCurveAdjustments.linear,
        red: [CurvePoint] = ToneCurveAdjustments.linear,
        green: [CurvePoint] = ToneCurveAdjustments.linear,
        blue: [CurvePoint] = ToneCurveAdjustments.linear,
        region: ParametricCurve = .identity
    ) {
        self.rgb = rgb
        self.red = red
        self.green = green
        self.blue = blue
        self.region = region
    }

    public var isIdentity: Bool {
        rgb == Self.linear
            && red == Self.linear
            && green == Self.linear
            && blue == Self.linear
            && region.isIdentity
    }

    public subscript(_ channel: ToneCurveChannel) -> [CurvePoint] {
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
        case rgb, red, green, blue, region
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rgb = try container.decodeIfPresent([CurvePoint].self, forKey: .rgb) ?? Self.linear
        red = try container.decodeIfPresent([CurvePoint].self, forKey: .red) ?? Self.linear
        green = try container.decodeIfPresent([CurvePoint].self, forKey: .green) ?? Self.linear
        blue = try container.decodeIfPresent([CurvePoint].self, forKey: .blue) ?? Self.linear
        region = (try? container.decodeIfPresent(ParametricCurve.self, forKey: .region)) ?? .identity
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if rgb != Self.linear { try container.encode(rgb, forKey: .rgb) }
        if red != Self.linear { try container.encode(red, forKey: .red) }
        if green != Self.linear { try container.encode(green, forKey: .green) }
        if blue != Self.linear { try container.encode(blue, forKey: .blue) }
        if !region.isIdentity { try container.encode(region, forKey: .region) }
    }
}

/// Lightroom's region curve: four tonal regions pushed up or down, with the
/// three splits between them movable. Values −1…1 (UI ±100); splits 0…1.
/// Baked into the same 256-step table as the point curve, region first.
public struct ParametricCurve: Codable, Equatable, Sendable {
    public var shadows = 0.0
    public var darks = 0.0
    public var lights = 0.0
    public var highlights = 0.0
    public var shadowSplit = 0.25
    public var midtoneSplit = 0.5
    public var highlightSplit = 0.75

    public static let identity = ParametricCurve()

    public init() {}

    /// The splits only shape the curve once a region moves, so a curve with
    /// every region at 0 is untouched wherever its splits sit.
    public var isIdentity: Bool {
        shadows == 0 && darks == 0 && lights == 0 && highlights == 0
    }

    private enum CodingKeys: String, CodingKey {
        case shadows, darks, lights, highlights, shadowSplit, midtoneSplit, highlightSplit
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shadows = try container.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        darks = try container.decodeIfPresent(Double.self, forKey: .darks) ?? 0
        lights = try container.decodeIfPresent(Double.self, forKey: .lights) ?? 0
        highlights = try container.decodeIfPresent(Double.self, forKey: .highlights) ?? 0
        shadowSplit = try container.decodeIfPresent(Double.self, forKey: .shadowSplit) ?? 0.25
        midtoneSplit = try container.decodeIfPresent(Double.self, forKey: .midtoneSplit) ?? 0.5
        highlightSplit = try container.decodeIfPresent(Double.self, forKey: .highlightSplit) ?? 0.75
    }
}
