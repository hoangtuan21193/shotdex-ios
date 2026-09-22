import Foundation

/// How a healing spot fills itself from its source.
public enum PhotoHealingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Copies the source's texture and matches the colour of the ground
    /// around the spot — what removes a dust speck from a sky.
    case heal
    /// Copies the source as it is.
    case clone

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .heal: "Heal"
        case .clone: "Clone"
        }
    }
}

/// One spot of the Heal tool: a circle that is filled from another circle of
/// the same photo.
///
/// Coordinates are normalized to the **cropped** frame with the origin at the
/// top left — the space masks and the drawing live in — so the canvas can
/// draw and drag them with the machinery it already has. Like a mask, a spot
/// does not follow a crop made after it.
public struct PhotoHealingSpot: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var mode: PhotoHealingMode
    /// Centre of the area being repaired.
    public var center: NormalizedPoint
    /// Centre of the area it is filled from.
    public var source: NormalizedPoint
    /// Radius as a fraction of the frame's short edge.
    public var radius: Double
    /// 0 = hard edge, 1 = the whole radius is a blend.
    public var feather: Double
    public var opacity: Double

    public init(
        id: UUID = UUID(),
        mode: PhotoHealingMode = .heal,
        center: NormalizedPoint,
        source: NormalizedPoint,
        radius: Double = 0.03,
        feather: Double = 0.5,
        opacity: Double = 1
    ) {
        self.id = id
        self.mode = mode
        self.center = center
        self.source = source
        self.radius = radius
        self.feather = feather
        self.opacity = opacity
    }

    /// The source ShotDex proposes for a spot at `center`: beside it, at a
    /// distance that clears the spot and its blending ring. Sideways first,
    /// because skies and walls — where dust shows — change top to bottom far
    /// more than side to side; the far side when the near one leaves the frame.
    public static func suggestedSource(
        for center: NormalizedPoint,
        radius: Double,
        aspectRatio: Double
    ) -> NormalizedPoint {
        // Radius is on the short edge; convert the offset into each axis.
        let shortOverWidth = aspectRatio >= 1 ? 1 / aspectRatio : 1
        let offset = radius * 2.6 * shortOverWidth
        let right = center.x + offset
        let x = right + radius * shortOverWidth <= 1 ? right : center.x - offset
        return NormalizedPoint(x: min(1, max(0, x)), y: center.y)
    }
}
