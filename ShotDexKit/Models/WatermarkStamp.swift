import Foundation

/// Where a watermark sits on the photo — the 3×3 grid of FS-05.04 §3.
public enum WatermarkAnchor: String, Codable, CaseIterable, Identifiable, Sendable {
    case topLeft
    case top
    case topRight
    case left
    case center
    case right
    case bottomLeft
    case bottom
    case bottomRight

    public var id: String { rawValue }

    /// Column across the grid: 0 left, 1 middle, 2 right.
    public var column: Int {
        switch self {
        case .topLeft, .left, .bottomLeft: 0
        case .top, .center, .bottom: 1
        case .topRight, .right, .bottomRight: 2
        }
    }

    /// Row down the grid: 0 top, 1 middle, 2 bottom.
    public var row: Int {
        switch self {
        case .topLeft, .top, .topRight: 0
        case .left, .center, .right: 1
        case .bottomLeft, .bottom, .bottomRight: 2
        }
    }
}

/// How a watermark is placed on every photo of an export (FS-05.04 §3): one
/// anchor and three numbers, all relative to the photo's **short edge**, so a
/// 1080px and a 6000px photo of the same batch look alike.
public struct WatermarkPlacement: Codable, Equatable, Sendable {
    public var anchor: WatermarkAnchor
    /// Gap from the anchored edges, a fraction of the short edge.
    public var margin: Double
    /// Height of the whole block, a fraction of the short edge. Nil is the
    /// preset's own size, as it was saved.
    public var size: Double?
    /// Multiplies every layer's own opacity.
    public var opacity: Double

    public static let marginRange = 0.0...0.10
    public static let marginStep = 0.005
    public static let sizeRange = 0.01...0.25
    public static let sizeStep = 0.01
    public static let opacityRange = 0.10...1.0
    public static let opacityStep = 0.05

    public init(
        anchor: WatermarkAnchor = .bottomRight,
        margin: Double = 0.03,
        size: Double? = nil,
        opacity: Double = 1
    ) {
        self.anchor = anchor
        self.margin = Self.clamp(margin, to: Self.marginRange)
        self.size = size.map { Self.clamp($0, to: Self.sizeRange) }
        self.opacity = Self.clamp(opacity, to: Self.opacityRange)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private enum CodingKeys: String, CodingKey {
        case anchor, margin, size, opacity
    }

    /// Lenient, like every stored choice: an anchor this build does not know
    /// falls back to the default instead of losing the whole configuration.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            anchor: (try? container.decodeIfPresent(WatermarkAnchor.self, forKey: .anchor)) ?? .bottomRight,
            margin: (try? container.decodeIfPresent(Double.self, forKey: .margin)) ?? 0.03,
            size: (try? container.decodeIfPresent(Double.self, forKey: .size)) ?? nil,
            opacity: (try? container.decodeIfPresent(Double.self, forKey: .opacity)) ?? 1
        )
    }
}

/// One watermark ready to stamp: the preset's layers as one block, and where
/// it goes (FS-05.04 §3). A value, `Sendable`, with no decoded images in it,
/// so it can travel from the form to the renderer actor and into a share.
public struct WatermarkStamp: Codable, Equatable, Sendable {
    /// The preset it came from, so a photo whose edit already carries a layer
    /// pasted from the same preset is not stamped twice (FS-05.04 §5).
    public var presetID: UUID
    public var name: String
    /// The preset's layers. Loupes are never part of a stamp: a loupe magnifies
    /// one place of one particular photo.
    public var layers: [PhotoOverlay]
    /// Width ÷ height of the photo the preset was saved on. The layers keep
    /// their positions relative to each other in a frame of this shape.
    public var sourceAspect: Double
    public var placement: WatermarkPlacement

    public init(
        presetID: UUID,
        name: String,
        layers: [PhotoOverlay],
        sourceAspect: Double,
        placement: WatermarkPlacement
    ) {
        self.presetID = presetID
        self.name = name
        self.layers = layers.filter { $0.kind != .magnifier }
        self.sourceAspect = sourceAspect > 0.01 ? sourceAspect : SignaturePreset.defaultSourceAspect
        self.placement = placement
    }

    public init(preset: SignaturePreset, placement: WatermarkPlacement) {
        self.init(
            presetID: preset.id,
            name: preset.name,
            layers: preset.layers,
            sourceAspect: preset.sourceAspect ?? SignaturePreset.defaultSourceAspect,
            placement: placement
        )
    }

    /// The stamp for one photo: every `{camera}`-style token replaced by that
    /// photo's value, with FS-05.02's rule for empty ones.
    public func resolved(with values: OverlayTokenValues) -> WatermarkStamp {
        var copy = self
        copy.layers = layers.map { layer in
            guard layer.kind == .text, OverlayTokenResolver.containsKnownToken(layer.text) else { return layer }
            var resolved = layer
            resolved.text = OverlayTokenResolver.resolve(layer.text, values: values)
            return resolved
        }
        return copy
    }

    /// Whether any layer would put pixels on the photo — false when every token
    /// of a token-only preset came out empty (FS-05.04 §5).
    public var hasVisibleLayers: Bool { layers.contains(where: \.hasVisibleEffect) }
}
