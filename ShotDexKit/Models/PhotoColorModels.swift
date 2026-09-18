import Foundation

// MARK: - Color Mixer

/// The eight Lightroom-style hue bands the mixer can target. The band centers
/// are the single source of truth shared by the render kernels (interpolated
/// into the kernel source) and the slider-track gradients in the UI.
public enum ColorMixerBand: String, Codable, CaseIterable, Identifiable, Sendable {
    case red, orange, yellow, green, aqua, blue, purple, magenta

    public var id: String { rawValue }

    public var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    /// Band center hue in degrees on the 0–360 wheel.
    public var centerDegrees: Double {
        switch self {
        case .red: 0
        case .orange: 30
        case .yellow: 60
        case .green: 120
        case .aqua: 180
        case .blue: 240
        case .purple: 280
        case .magenta: 320
        }
    }
}

/// Which of a band's three sliders is being addressed. Presentation-level —
/// stored values live on `ColorMixerAdjustments.Channel`.
public enum ColorMixerProperty: String, CaseIterable, Identifiable, Sendable {
    case hue, saturation, luminance

    public var id: String { rawValue }

    public var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

/// Per-band HSL shifts. All values -1…1 (UI shows ±100); a full hue shift is
/// ±30° toward the neighboring bands.
public struct ColorMixerAdjustments: Codable, Equatable, Sendable {
    public struct Channel: Codable, Equatable, Sendable {
        public var hue = 0.0
        public var saturation = 0.0
        public var luminance = 0.0

        public static let identity = Channel()

        public var isIdentity: Bool { self == .identity }

        private enum CodingKeys: String, CodingKey {
            case hue, saturation, luminance
        }

        public init() {}

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            hue = try container.decodeIfPresent(Double.self, forKey: .hue) ?? 0
            saturation = try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 0
            luminance = try container.decodeIfPresent(Double.self, forKey: .luminance) ?? 0
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if hue != 0 { try container.encode(hue, forKey: .hue) }
            if saturation != 0 { try container.encode(saturation, forKey: .saturation) }
            if luminance != 0 { try container.encode(luminance, forKey: .luminance) }
        }

        public subscript(property: ColorMixerProperty) -> Double {
            get {
                switch property {
                case .hue: hue
                case .saturation: saturation
                case .luminance: luminance
                }
            }
            set {
                switch property {
                case .hue: hue = newValue
                case .saturation: saturation = newValue
                case .luminance: luminance = newValue
                }
            }
        }
    }

    public var red = Channel()
    public var orange = Channel()
    public var yellow = Channel()
    public var green = Channel()
    public var aqua = Channel()
    public var blue = Channel()
    public var purple = Channel()
    public var magenta = Channel()

    public static let identity = ColorMixerAdjustments()

    public var isIdentity: Bool { self == .identity }

    public subscript(band: ColorMixerBand) -> Channel {
        get {
            switch band {
            case .red: red
            case .orange: orange
            case .yellow: yellow
            case .green: green
            case .aqua: aqua
            case .blue: blue
            case .purple: purple
            case .magenta: magenta
            }
        }
        set {
            switch band {
            case .red: red = newValue
            case .orange: orange = newValue
            case .yellow: yellow = newValue
            case .green: green = newValue
            case .aqua: aqua = newValue
            case .blue: blue = newValue
            case .purple: purple = newValue
            case .magenta: magenta = newValue
            }
        }
    }

    private struct BandKey: CodingKey {
        public var stringValue: String
        public var intValue: Int? { nil }

        public init(stringValue: String) { self.stringValue = stringValue }
        public init?(intValue _: Int) { nil }
        public init(_ band: ColorMixerBand) { stringValue = band.rawValue }
    }

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: BandKey.self)
        for band in ColorMixerBand.allCases {
            guard let channel = try container.decodeIfPresent(Channel.self, forKey: BandKey(band))
            else { continue }
            self[band] = channel
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: BandKey.self)
        for band in ColorMixerBand.allCases where !self[band].isIdentity {
            try container.encode(self[band], forKey: BandKey(band))
        }
    }
}

// MARK: - Point Color

/// One eyedropper-sampled color plus the shifts applied around it. The
/// reference is captured in HSV at sample time (from the edited preview, like
/// Lightroom) and never resampled when upstream edits change.
public struct PointColorAdjustment: Codable, Identifiable, Equatable, Sendable {
    public init(
        id: UUID = UUID(),
        referenceHue: Double,
        referenceSaturation: Double,
        referenceValue: Double,
        hueShift: Double = 0,
        saturationShift: Double = 0,
        luminanceShift: Double = 0,
        range: Double = 0.5
    ) {
        self.id = id
        self.referenceHue = referenceHue
        self.referenceSaturation = referenceSaturation
        self.referenceValue = referenceValue
        self.hueShift = hueShift
        self.saturationShift = saturationShift
        self.luminanceShift = luminanceShift
        self.range = range
    }

    public var id = UUID()
    /// Reference hue in degrees 0…360.
    public var referenceHue: Double
    /// Reference saturation 0…1.
    public var referenceSaturation: Double
    /// Reference value (brightness) 0…1.
    public var referenceValue: Double
    public var hueShift = 0.0
    public var saturationShift = 0.0
    public var luminanceShift = 0.0
    /// Falloff radius of the match around the reference, 0…1.
    public var range = 0.5

    public static let maximumCount = 8

    public var hasVisibleEffect: Bool {
        hueShift != 0 || saturationShift != 0 || luminanceShift != 0
    }
}

// MARK: - Color Grading

public enum ColorGradingRegion: String, Codable, CaseIterable, Identifiable, Sendable {
    case shadows, midtones, highlights, global

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .shadows: "Shadows"
        case .midtones: "Midtones"
        case .highlights: "Highlights"
        case .global: "Global"
        }
    }
}

/// Lightroom-style split toning: a tint wheel plus luminance lift per
/// luminance region, with Blending controlling region overlap and Balance
/// shifting the shadow/highlight pivots.
public struct ColorGradingAdjustments: Codable, Equatable, Sendable {
    public struct Wheel: Codable, Equatable, Sendable {
        /// Tint hue in degrees 0…360. Invisible while saturation is 0.
        public var hue = 0.0
        /// Tint strength 0…1.
        public var saturation = 0.0
        /// Region luminance lift -1…1.
        public var luminance = 0.0

        public static let identity = Wheel()

        public var isIdentity: Bool { self == .identity }

        public var hasVisibleEffect: Bool { saturation != 0 || luminance != 0 }

        private enum CodingKeys: String, CodingKey {
            case hue, saturation, luminance
        }

        public init() {}

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            hue = try container.decodeIfPresent(Double.self, forKey: .hue) ?? 0
            saturation = try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 0
            luminance = try container.decodeIfPresent(Double.self, forKey: .luminance) ?? 0
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if hue != 0 { try container.encode(hue, forKey: .hue) }
            if saturation != 0 { try container.encode(saturation, forKey: .saturation) }
            if luminance != 0 { try container.encode(luminance, forKey: .luminance) }
        }
    }

    public var shadows = Wheel()
    public var midtones = Wheel()
    public var highlights = Wheel()
    public var global = Wheel()
    /// Region overlap width, 0…1. Default 0.5 matches Lightroom's 50.
    public var blending = 0.5
    /// Shifts the shadow/highlight pivots, -1…1.
    public var balance = 0.0

    public static let identity = ColorGradingAdjustments()

    public var isIdentity: Bool { self == .identity }

    public subscript(region: ColorGradingRegion) -> Wheel {
        get {
            switch region {
            case .shadows: shadows
            case .midtones: midtones
            case .highlights: highlights
            case .global: global
            }
        }
        set {
            switch region {
            case .shadows: shadows = newValue
            case .midtones: midtones = newValue
            case .highlights: highlights = newValue
            case .global: global = newValue
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case shadows, midtones, highlights, global, blending, balance
    }

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shadows = try container.decodeIfPresent(Wheel.self, forKey: .shadows) ?? .identity
        midtones = try container.decodeIfPresent(Wheel.self, forKey: .midtones) ?? .identity
        highlights = try container.decodeIfPresent(Wheel.self, forKey: .highlights) ?? .identity
        global = try container.decodeIfPresent(Wheel.self, forKey: .global) ?? .identity
        blending = try container.decodeIfPresent(Double.self, forKey: .blending) ?? 0.5
        balance = try container.decodeIfPresent(Double.self, forKey: .balance) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !shadows.isIdentity { try container.encode(shadows, forKey: .shadows) }
        if !midtones.isIdentity { try container.encode(midtones, forKey: .midtones) }
        if !highlights.isIdentity { try container.encode(highlights, forKey: .highlights) }
        if !global.isIdentity { try container.encode(global, forKey: .global) }
        if blending != 0.5 { try container.encode(blending, forKey: .blending) }
        if balance != 0 { try container.encode(balance, forKey: .balance) }
    }
}

// MARK: - Container

/// The whole Color tab under a single recipe key, so `PhotoEditRecipe` grows
/// exactly one field and untouched recipes encode no color data at all.
public struct PhotoColorRecipe: Codable, Equatable, Sendable {
    public var mixer = ColorMixerAdjustments.identity
    public var points: [PointColorAdjustment] = []
    public var grading = ColorGradingAdjustments.identity

    public static let identity = PhotoColorRecipe()

    public var isIdentity: Bool {
        mixer.isIdentity && points.isEmpty && grading.isIdentity
    }

    private enum CodingKeys: String, CodingKey {
        case mixer, points, grading
    }

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mixer = try container.decodeIfPresent(ColorMixerAdjustments.self, forKey: .mixer)
            ?? .identity
        points = try container.decodeIfPresent([PointColorAdjustment].self, forKey: .points)
            ?? []
        grading = try container.decodeIfPresent(ColorGradingAdjustments.self, forKey: .grading)
            ?? .identity
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !mixer.isIdentity { try container.encode(mixer, forKey: .mixer) }
        if !points.isEmpty { try container.encode(points, forKey: .points) }
        if !grading.isIdentity { try container.encode(grading, forKey: .grading) }
    }
}
