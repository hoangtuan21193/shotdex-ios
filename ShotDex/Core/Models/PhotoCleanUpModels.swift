import Foundation

/// What a Clean Up stroke does with the pixels it covers.
///
/// All three are the same primitive at render time — an offset field that says,
/// for every covered pixel, which other pixel of the same image to read instead.
/// Clone's field is constant, Heal's is constant plus a low-frequency
/// correction, Remove's is solved by PatchMatch (or replaced outright by the
/// inpainting model when `CleanUpStroke.usesModel` is set).
enum CleanUpMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case clone
    case heal
    case remove

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clone: "Clone"
        case .heal: "Heal"
        case .remove: "Remove"
        }
    }

    var systemImage: String {
        switch self {
        case .clone: "square.on.square"
        case .heal: "bandage"
        case .remove: "wand.and.stars"
        }
    }

    /// Clone and Heal read from a source the user places; Remove finds its own.
    var usesSourceOffset: Bool { self != .remove }
}

/// One brushed-over area to clone, heal or remove.
///
/// `points` and `size` follow `BrushStroke` exactly — normalized against the
/// image *after* crop, size as a fraction of the short edge — so the same
/// rasterizer serves both and the on-image cursor matches the rendered pixels.
struct CleanUpStroke: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var mode: CleanUpMode
    var points: [NormalizedPoint]
    var size: Double
    var feather: Double
    /// Where Clone and Heal read from, as an offset from the stroke's own
    /// centroid. Normalized like `NormalizedPoint`: x against the width, y
    /// against the height, so it survives any render resolution.
    var sourceOffsetX = 0.0
    var sourceOffsetY = 0.0
    /// Remove only: fill with the bundled inpainting model instead of
    /// PatchMatch. Recipes written on a device that has the model still open on
    /// one that does not — the renderer falls back rather than skipping the
    /// stroke.
    var usesModel = false
    var opacity = 1.0

    init(
        mode: CleanUpMode,
        points: [NormalizedPoint],
        size: Double,
        feather: Double,
        usesModel: Bool = false
    ) {
        self.mode = mode
        self.points = points
        self.size = size
        self.feather = feather
        self.usesModel = usesModel
    }

    /// Anchor for the on-image pin and for the source ring.
    var centroid: NormalizedPoint {
        guard !points.isEmpty else { return .center }
        let sum = points.reduce(into: (x: 0.0, y: 0.0)) { total, point in
            total.x += point.x
            total.y += point.y
        }
        let count = Double(points.count)
        return NormalizedPoint(x: sum.x / count, y: sum.y / count)
    }

    var hasVisibleEffect: Bool { !points.isEmpty && opacity > 0.001 }

    /// Everything that invalidates a cached offset field or model patch — and
    /// deliberately nothing that only affects compositing. Opacity is absent so
    /// fading a removal never re-runs PatchMatch, and tone is absent because
    /// the field is resolved against the current image at composite time.
    var fillSignature: String {
        var parts: [String] = [
            mode.rawValue,
            usesModel ? "m1" : "m0",
            String(format: "%.4f", size),
            String(format: "%.4f", feather),
        ]
        if mode.usesSourceOffset {
            parts.append(String(format: "%.5f", sourceOffsetX))
            parts.append(String(format: "%.5f", sourceOffsetY))
        }
        for point in points {
            parts.append(String(format: "%.5f,%.5f", point.x, point.y))
        }
        return parts.joined(separator: "|")
    }

    /// Stable across launches, unlike `Hashable` — Swift seeds `Hasher` per
    /// process, so a hash-derived PatchMatch seed would fill the same recipe
    /// differently in the preview and in the exported file.
    var fillSeed: UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.uuidString.utf8 {
            hash ^= UInt64(byte)
            hash = hash.multipliedReportingOverflow(by: 0x100_0000_01b3).partialValue
        }
        return hash
    }
}
