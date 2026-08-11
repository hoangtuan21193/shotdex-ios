import Foundation

/// One slot of a collage. `assetID` is nil for an **empty slot** — a cell the
/// layout drew but no photo fills yet (§6); tapping it opens the picker. When a
/// photo is present, `contentScale`/`contentOffset` say how it sits inside the
/// cell: `contentScale` multiplies the aspect-fill baseline (1 = exactly
/// filling), `contentOffset` pans in fractions of the cell's own size — both
/// resolution-independent so the interactive canvas and the export resolve to
/// the same picture.
struct CollageCell: Equatable, Sendable {
    var assetID: String?
    var contentScale: Double = 1
    var contentOffset: NormalizedPoint = NormalizedPoint(x: 0, y: 0)
    /// Polaroid caption typed under this photo (§10/§11). Empty shows the
    /// `Add caption` placeholder; never auto-filled from EXIF.
    var caption: String = ""

    var isEmpty: Bool { assetID == nil }

    static let minimumContentScale: Double = 1
    static let maximumContentScale: Double = 4
}

/// How the canvas behind the cells is filled (§10).
enum CollageBackgroundMode: String, Codable, Sendable {
    /// A flat colour (`CollageRecipe.background`).
    case color
    /// The selected photo, blurred and darkened.
    case blurredPhoto
}

/// The preset aspect ratios offered as chips (§5). `Custom` is not a case here —
/// it is the absence of a preset (`CollageRecipe.aspectPreset == nil`), driven
/// by its own popover, so this enum stays a clean list the chip row and the
/// output-size tests can both iterate.
enum CollageAspect: String, CaseIterable, Identifiable, Codable, Sendable {
    case square
    case fourFive
    case fiveFour
    case twoThree
    case threeTwo
    case nineSixteen
    case sixteenNine
    case a4
    case letter
    case fiveSeven
    case twentyOneNine

    var id: String { rawValue }

    /// width / height of the output canvas.
    var ratio: Double {
        switch self {
        case .square: 1
        case .fourFive: 4.0 / 5.0
        case .fiveFour: 5.0 / 4.0
        case .twoThree: 2.0 / 3.0
        case .threeTwo: 3.0 / 2.0
        case .nineSixteen: 9.0 / 16.0
        case .sixteenNine: 16.0 / 9.0
        case .a4: 210.0 / 297.0
        case .letter: 8.5 / 11.0
        case .fiveSeven: 5.0 / 7.0
        case .twentyOneNine: 21.0 / 9.0
        }
    }

    var displayName: String {
        switch self {
        case .square: "1:1"
        case .fourFive: "4:5"
        case .fiveFour: "5:4"
        case .twoThree: "2:3"
        case .threeTwo: "3:2"
        case .nineSixteen: "9:16"
        case .sixteenNine: "16:9"
        case .a4: "A4"
        case .letter: "Letter"
        case .fiveSeven: "5:7"
        case .twentyOneNine: "21:9"
        }
    }

    /// The preset whose ratio matches `ratio` (within a hair), or nil for a
    /// genuinely custom ratio. Lets the chip row light up when a custom entry
    /// happens to land on a named ratio.
    static func matching(ratio: Double) -> CollageAspect? {
        allCases.first { abs($0.ratio - ratio) < 0.001 }
    }
}

/// The whole collage state. In-memory only — the export is a flat new asset,
/// nothing is recalled from adjustment data, so there is deliberately no
/// Codable conformance (and none of its compatibility burden).
///
/// `aspectRatio` is the source of truth for the canvas shape; `aspectPreset`
/// records which named chip produced it (nil = a custom ratio). `gutter`,
/// `cornerRadius` and `borderWidth` are fractions of the output's short edge,
/// the same convention `PhotoOverlay.size` uses, so they survive any resolution.
struct CollageRecipe: Equatable, Sendable {
    var templateID: String
    var aspectRatio: Double = 1
    var aspectPreset: CollageAspect? = .square
    var gutter: Double = 0.02
    var cornerRadius: Double = 0
    var borderWidth: Double = 0
    var borderColor: OverlayColor = .white
    var background: OverlayColor = .white
    /// Background fill mode (§10). `blurredPhoto` blurs the selected photo.
    var backgroundMode: CollageBackgroundMode = .color
    /// Blur strength (0…1) and darkening (0…1, 0 = untouched) for the blurred
    /// photo background.
    var backgroundBlur: Double = 0.5
    var backgroundDarken: Double = 0.38
    /// Which cell's photo feeds the blur; nil follows the selection / first photo.
    var backgroundSourceIndex: Int?
    /// Polaroid style: each photo on a white plate with a caption line (§10).
    var isPolaroid: Bool = false
    var cells: [CollageCell]
    var overlays: [PhotoOverlay] = []
    /// Divider drags, keyed by split-node id (§9). Reset when the template
    /// changes — a new template's nodes are a different tree.
    var dividerWeights: [String: [Double]] = [:]

    static let gutterRange: ClosedRange<Double> = 0...0.06
    static let cornerRadiusRange: ClosedRange<Double> = 0...0.08
    static let borderWidthRange: ClosedRange<Double> = 0...0.04
    static let aspectRatioRange: ClosedRange<Double> = 0.25...4
    static let backgroundBlurRange: ClosedRange<Double> = 0...1
    static let backgroundDarkenRange: ClosedRange<Double> = 0...0.8

    /// The custom aspect popover's shortcut ratios (§5).
    static let customShortcuts: [(label: String, ratio: Double?)] = [
        ("3:4", 3.0 / 4.0),
        ("4:3", 4.0 / 3.0),
        ("2.35:1", 2.35),
        ("Free", nil),
    ]
}

/// A saved collage look (§8): the **frame and style**, never the photos or the
/// text. Applying one restamps the layout and its styling onto whatever photos
/// are currently placed. Codable for `UserDefaults` persistence.
struct CollagePreset: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    /// The layout. Applied only when its cell count matches the current slots —
    /// a template is tied to a photo count, and grafting a 4-cell tree onto a
    /// 3-slot collage would desync.
    var templateID: String
    var dividerWeights: [String: [Double]]
    var aspectRatio: Double
    var aspectPreset: CollageAspect?
    var gutter: Double
    var cornerRadius: Double
    var borderWidth: Double
    var borderColor: OverlayColor
    var background: OverlayColor
    var backgroundMode: CollageBackgroundMode
    var backgroundBlur: Double
    var backgroundDarken: Double
    var isPolaroid: Bool

    /// Snapshots the styling half of a recipe (the frame is `templateID` +
    /// `dividerWeights`).
    init(name: String, recipe: CollageRecipe) {
        self.name = name
        self.templateID = recipe.templateID
        self.dividerWeights = recipe.dividerWeights
        self.aspectRatio = recipe.aspectRatio
        self.aspectPreset = recipe.aspectPreset
        self.gutter = recipe.gutter
        self.cornerRadius = recipe.cornerRadius
        self.borderWidth = recipe.borderWidth
        self.borderColor = recipe.borderColor
        self.background = recipe.background
        self.backgroundMode = recipe.backgroundMode
        self.backgroundBlur = recipe.backgroundBlur
        self.backgroundDarken = recipe.backgroundDarken
        self.isPolaroid = recipe.isPolaroid
    }
}
