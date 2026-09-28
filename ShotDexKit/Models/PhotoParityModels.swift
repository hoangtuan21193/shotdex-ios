import Foundation

// Recipe parts added for Lightroom parity (FS-03.15). Every one decodes
// forgivingly and defaults to "untouched", so Reset and the edited badge stay
// right and a value this build cannot read costs only itself.

// MARK: - Upright

/// Which automatic straightening the photo asked for.
public enum PhotoUprightMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, auto, level, vertical, full, guided

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .auto: "Auto"
        case .level: "Level"
        case .vertical: "Vertical"
        case .full: "Full"
        case .guided: "Guided"
        }
    }
}

/// One line drawn along an edge that should be straight (Upright Guided).
public struct PhotoUprightGuide: Codable, Equatable, Sendable {
    public var start: NormalizedPoint
    public var end: NormalizedPoint

    public init(start: NormalizedPoint, end: NormalizedPoint) {
        self.start = start
        self.end = end
    }
}

/// The perspective correction Upright solved for this photo. Kept apart from
/// the Geometry sliders, which add on top of it (FS-03.15 D57).
public struct PhotoUprightTransform: Codable, Equatable, Sendable {
    public var vertical = 0.0
    public var horizontal = 0.0
    public var rotate = 0.0
    public var scale = 0.0
    public var offsetX = 0.0
    public var offsetY = 0.0
    public var aspect = 0.0

    public static let identity = PhotoUprightTransform()

    public init() {}

    public var isIdentity: Bool { self == .identity }
}

/// Upright: the mode travels with a look and is solved again on each photo;
/// the solved transform and the guides belong to this frame.
public struct PhotoUprightRecipe: Codable, Equatable, Sendable {
    public var mode: PhotoUprightMode = .off
    /// At most four (Lightroom's limit).
    public var guides: [PhotoUprightGuide] = []
    public var solved = PhotoUprightTransform.identity

    public static let identity = PhotoUprightRecipe()
    public static let maximumGuides = 4

    public init() {}

    public var isIdentity: Bool { mode == .off && guides.isEmpty && solved.isIdentity }

    private enum CodingKeys: String, CodingKey {
        case mode, guides, solved
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A mode this build does not know falls back to Off, not the recipe.
        mode = (try? container.decodeIfPresent(PhotoUprightMode.self, forKey: .mode)) ?? .off
        guides = Array((try container.decodeLossyArrayIfPresent(PhotoUprightGuide.self, forKey: .guides) ?? [])
            .prefix(Self.maximumGuides))
        solved = (try? container.decodeIfPresent(PhotoUprightTransform.self, forKey: .solved)) ?? .identity
    }
}

// MARK: - Lens Blur

public enum PhotoBokehShape: String, Codable, CaseIterable, Identifiable, Sendable {
    case circle, bubble, blade, ring, catEye

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .circle: "Circle"
        case .bubble: "Bubble"
        case .blade: "5-Blade"
        case .ring: "Ring"
        case .catEye: "Cat Eye"
        }
    }
}

/// Lens Blur: how much, what the out-of-focus highlights look like, and the
/// depth range kept sharp, on the photo's normalised depth (0 = farthest,
/// 1 = nearest — the scale the Focus Range rows show ×100, FS-03.15e §1).
/// `focusFar` is the far edge of the sharp band and so the lower number.
public struct PhotoLensBlurRecipe: Codable, Equatable, Sendable {
    public var amount = 0.0
    public var bokeh: PhotoBokehShape = .circle
    public var focusNear = 1.0
    public var focusFar = 0.6

    public static let identity = PhotoLensBlurRecipe()

    public init() {}

    /// Only the amount makes a picture differ; a moved focus range with no
    /// blur changes nothing.
    public var isIdentity: Bool { amount == 0 }

    private enum CodingKeys: String, CodingKey {
        case amount, bokeh, focusNear, focusFar
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        amount = try container.decodeIfPresent(Double.self, forKey: .amount) ?? 0
        bokeh = (try? container.decodeIfPresent(PhotoBokehShape.self, forKey: .bokeh)) ?? .circle
        focusNear = try container.decodeIfPresent(Double.self, forKey: .focusNear) ?? 1
        focusFar = try container.decodeIfPresent(Double.self, forKey: .focusFar) ?? 0.6
    }
}

// MARK: - Vignette style

/// How the post-crop vignette darkens (Lightroom's Style).
public enum PhotoVignetteStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case highlightPriority, colorPriority, paintOverlay

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .highlightPriority: "Highlight Priority"
        case .colorPriority: "Color Priority"
        case .paintOverlay: "Paint Overlay"
        }
    }
}

// MARK: - Red Eye

/// One pupil made dark again. Coordinates normalized to the cropped frame,
/// top-left origin, like the healing spots.
public struct PhotoRedEyeSpot: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var center: NormalizedPoint
    /// Radius as a fraction of the frame's short edge.
    public var radius: Double
    /// Pupil size within the circle, 0…1.
    public var pupilSize: Double
    /// How dark the pupil turns, 0…1.
    public var darken: Double

    public init(
        id: UUID = UUID(),
        center: NormalizedPoint,
        radius: Double,
        pupilSize: Double = 0.5,
        darken: Double = 0.5
    ) {
        self.id = id
        self.center = center
        self.radius = radius
        self.pupilSize = pupilSize
        self.darken = darken
    }
}
