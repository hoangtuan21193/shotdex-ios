import Foundation

/// One slot of a collage: which asset fills it and how the photo sits inside
/// the cell. `contentScale` multiplies the aspect-fill baseline (1 = exactly
/// filling), `contentOffset` pans in fractions of the cell's own size — both
/// resolution-independent so the interactive canvas and the 4096px export
/// resolve to the same picture.
struct CollageCell: Equatable, Sendable {
    var assetID: String
    var contentScale: Double = 1
    var contentOffset: NormalizedPoint = NormalizedPoint(x: 0, y: 0)

    static let minimumContentScale: Double = 1
    static let maximumContentScale: Double = 4
}

enum CollageAspect: String, CaseIterable, Identifiable, Sendable {
    case square
    case fourFive
    case threeTwo
    case nineSixteen
    case sixteenNine

    var id: String { rawValue }

    /// width / height of the output canvas.
    var ratio: Double {
        switch self {
        case .square: 1
        case .fourFive: 4.0 / 5.0
        case .threeTwo: 3.0 / 2.0
        case .nineSixteen: 9.0 / 16.0
        case .sixteenNine: 16.0 / 9.0
        }
    }

    var displayName: String {
        switch self {
        case .square: "1:1"
        case .fourFive: "4:5"
        case .threeTwo: "3:2"
        case .nineSixteen: "9:16"
        case .sixteenNine: "16:9"
        }
    }
}

/// The whole collage state. In-memory only — the export is a flat new asset,
/// nothing is recalled from adjustment data, so there is deliberately no
/// Codable conformance (and none of its compatibility burden).
///
/// `gutter` and `cornerRadius` are fractions of the output's short edge, the
/// same convention `PhotoOverlay.size` uses, so they survive any resolution.
struct CollageRecipe: Equatable, Sendable {
    var templateID: String
    var aspect: CollageAspect = .square
    var gutter: Double = 0.02
    var cornerRadius: Double = 0
    var background: OverlayColor = .white
    var cells: [CollageCell]
    var overlays: [PhotoOverlay] = []

    static let gutterRange: ClosedRange<Double> = 0...0.06
    static let cornerRadiusRange: ClosedRange<Double> = 0...0.08
}
