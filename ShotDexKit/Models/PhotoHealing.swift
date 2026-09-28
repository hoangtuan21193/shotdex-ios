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
    /// A brush-stroke spot's points, **relative to `center`** — so moving the
    /// spot moves the stroke, and the source is the same stroke laid at
    /// `source`. `radius` is then half the stroke's width. Nil for a round
    /// spot (FS-03.15c §2).
    public var stroke: [NormalizedPoint]?

    public init(
        id: UUID = UUID(),
        mode: PhotoHealingMode = .heal,
        center: NormalizedPoint,
        source: NormalizedPoint,
        radius: Double = 0.03,
        feather: Double = 0.5,
        opacity: Double = 1,
        stroke: [NormalizedPoint]? = nil
    ) {
        self.id = id
        self.mode = mode
        self.center = center
        self.source = source
        self.radius = radius
        self.feather = feather
        self.opacity = opacity
        self.stroke = stroke.flatMap { $0.count >= 2 ? $0 : nil }
    }

    /// A stroke spot from the absolute points the finger went through: centred
    /// on their middle, its source laid beside it.
    public static func stroke(
        through points: [NormalizedPoint],
        mode: PhotoHealingMode,
        radius: Double,
        feather: Double,
        opacity: Double,
        aspectRatio: Double
    ) -> PhotoHealingSpot? {
        guard points.count >= 2 else { return nil }
        let center = NormalizedPoint(
            x: points.map(\.x).reduce(0, +) / Double(points.count),
            y: points.map(\.y).reduce(0, +) / Double(points.count)
        )
        let relative = points.map { NormalizedPoint(x: $0.x - center.x, y: $0.y - center.y) }
        return PhotoHealingSpot(
            mode: mode,
            center: center,
            source: suggestedSource(forStroke: relative, at: center, radius: radius, aspectRatio: aspectRatio),
            radius: radius,
            feather: feather,
            opacity: opacity,
            stroke: relative
        )
    }

    /// A stroke's proposed source: the whole stroke moved sideways,
    /// square to its main direction, 1.3 widths off (FS-03.15c §2) — to the
    /// side that stays in frame.
    public static func suggestedSource(
        forStroke relative: [NormalizedPoint],
        at center: NormalizedPoint,
        radius: Double,
        aspectRatio: Double
    ) -> NormalizedPoint {
        guard let first = relative.first, let last = relative.last else { return center }
        // Work in a square space (short edge = 1), where "square to" is square.
        let shortOverWidth = aspectRatio >= 1 ? 1 / aspectRatio : 1
        let shortOverHeight = aspectRatio >= 1 ? 1 : aspectRatio
        let dx = (last.x - first.x) / shortOverWidth, dy = (last.y - first.y) / shortOverHeight
        let length = max(1e-9, (dx * dx + dy * dy).squareRoot())
        let normal = (x: -dy / length, y: dx / length)
        let distance = radius * 2 * 1.3 + radius * 2
        func candidate(_ sign: Double) -> NormalizedPoint {
            NormalizedPoint(
                x: center.x + sign * normal.x * distance * shortOverWidth,
                y: center.y + sign * normal.y * distance * shortOverHeight
            )
        }
        func fits(_ point: NormalizedPoint) -> Bool {
            relative.allSatisfy { p in
                (0...1).contains(point.x + p.x) && (0...1).contains(point.y + p.y)
            }
        }
        let near = candidate(1)
        if fits(near) { return near }
        let far = candidate(-1)
        return fits(far) ? far : near
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
