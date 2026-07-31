import CoreGraphics
import Foundation
import UniformTypeIdentifiers

struct PhotoHistogram: Equatable, Sendable {
    var red: [Double]
    var green: [Double]
    var blue: [Double]
    /// Fraction of sampled pixels at the top of the range, used by the editor's
    /// clipping indicator. Kept out of the plotted bins so a clipped peak can be
    /// flagged even after percentile normalization flattens it.
    var clippedHighlightFraction = 0.0
    var clippedShadowFraction = 0.0

    static let empty = PhotoHistogram(red: [], green: [], blue: [])

    var luminance: [Double] {
        zip(zip(red, green), blue).map {
            0.2126 * $0.0.0 + 0.7152 * $0.0.1 + 0.0722 * $0.1
        }
    }

    var hasClippedHighlights: Bool { clippedHighlightFraction > 0.001 }
    var hasClippedShadows: Bool { clippedShadowFraction > 0.001 }
}

enum PhotoOutputFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case preserve
    case jpeg
    case heic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .preserve: "Same as Original"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        }
    }

    var fileExtension: String {
        switch self {
        case .preserve, .jpeg: "jpg"
        case .heic: "heic"
        }
    }

    var uniformType: UTType {
        switch self {
        case .preserve, .jpeg: .jpeg
        case .heic: .heic
        }
    }
}

enum ResizeCropMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fill
    case fit

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum ResizePresetKind: String, Codable, Sendable {
    case original
    case longEdge
    case exact
}

struct ResizePreset: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var kind: ResizePresetKind
    var longEdge: Int?
    var width: Int?
    var height: Int?
    var cropMode: ResizeCropMode
    var quality: Double
    var format: PhotoOutputFormat
    var isBuiltIn: Bool

    init(
        id: UUID = UUID(),
        name: String,
        kind: ResizePresetKind,
        longEdge: Int? = nil,
        width: Int? = nil,
        height: Int? = nil,
        cropMode: ResizeCropMode = .fit,
        quality: Double = 0.8,
        format: PhotoOutputFormat = .preserve,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.longEdge = longEdge
        self.width = width
        self.height = height
        self.cropMode = cropMode
        self.quality = quality
        self.format = format
        self.isBuiltIn = isBuiltIn
    }

    static let original = ResizePreset(
        id: UUID(uuidString: "5CEB1742-9BB8-4E36-8075-5C60543B40D9")!,
        name: "Original",
        kind: .original,
        isBuiltIn: true
    )

    static let fourK = ResizePreset(
        id: UUID(uuidString: "447E6B22-6070-47C8-8E39-A06523B34462")!,
        name: "4K",
        kind: .longEdge,
        longEdge: 3_840,
        isBuiltIn: true
    )

    static let twoK = ResizePreset(
        id: UUID(uuidString: "9E85B65C-C492-435F-8DA1-A4DA2732852F")!,
        name: "2048 px",
        kind: .longEdge,
        longEdge: 2_048,
        isBuiltIn: true
    )

    static let social = ResizePreset(
        id: UUID(uuidString: "91A9AA69-47DF-4FB2-9D1E-E5AF8B111A30")!,
        name: "1080 px",
        kind: .longEdge,
        longEdge: 1_080,
        isBuiltIn: true
    )

    static let builtIns: [ResizePreset] = [.original, .fourK, .twoK, .social]

    var allowsLongEdgeUpscaling: Bool {
        id == Self.fourK.id || id == Self.social.id
    }

    func targetPixelSize(sourceWidth: Int, sourceHeight: Int) -> CGSize {
        let source = CGSize(width: max(1, sourceWidth), height: max(1, sourceHeight))
        switch kind {
        case .original:
            return source
        case .longEdge:
            guard let longEdge, longEdge > 0 else { return source }
            let sourceLongEdge = max(source.width, source.height)
            guard allowsLongEdgeUpscaling || sourceLongEdge > CGFloat(longEdge)
            else { return source }
            let scale = CGFloat(longEdge) / sourceLongEdge
            return CGSize(
                width: max(1, (source.width * scale).rounded()),
                height: max(1, (source.height * scale).rounded())
            )
        case .exact:
            return CGSize(width: max(1, width ?? 1), height: max(1, height ?? 1))
        }
    }
}

enum PhotoEditSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case raw
    case rendered

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .raw: "RAW"
        case .rendered: "JPEG"
        }
    }
}

enum PhotoFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case original
    case vivid
    case vividWarm
    case vividCool
    case dramatic
    case dramaticWarm
    case dramaticCool
    case mono
    case silvertone
    case noir

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original: "Original"
        case .vivid: "Vivid"
        case .vividWarm: "Vivid Warm"
        case .vividCool: "Vivid Cool"
        case .dramatic: "Dramatic"
        case .dramaticWarm: "Dramatic Warm"
        case .dramaticCool: "Dramatic Cool"
        case .mono: "Mono"
        case .silvertone: "Silvertone"
        case .noir: "Noir"
        }
    }
}

enum PhotoAdjustmentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case exposure
    case brilliance
    case highlights
    case shadows
    case whites
    case contrast
    case brightness
    case blackPoint
    case saturation
    case vibrance
    case warmth
    case tint
    case sharpness
    case definition
    case noiseReduction
    case vignette
    case grain
    case rawTemperature
    case rawTint
    case rawLuminanceNoise
    case rawColorNoise
    case rawSharpness
    case lensCorrection

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .exposure: "Exposure"
        case .brilliance: "Brilliance"
        case .highlights: "Highlights"
        case .shadows: "Shadows"
        case .whites: "Whites"
        case .contrast: "Contrast"
        case .brightness: "Brightness"
        case .blackPoint: "Black Point"
        case .saturation: "Saturation"
        case .vibrance: "Vibrance"
        case .warmth: "Warmth"
        case .tint: "Tint"
        case .sharpness: "Sharpness"
        case .definition: "Definition"
        case .noiseReduction: "Noise"
        case .vignette: "Vignette"
        case .grain: "Grain"
        case .rawTemperature: "RAW White Balance"
        case .rawTint: "RAW Tint"
        case .rawLuminanceNoise: "RAW Luminance Noise"
        case .rawColorNoise: "RAW Color Noise"
        case .rawSharpness: "RAW Sharpening"
        case .lensCorrection: "Lens Correction"
        }
    }

    var systemImage: String {
        switch self {
        case .exposure: "plusminus.circle"
        case .brilliance: "wand.and.stars"
        case .highlights: "sun.max"
        case .shadows: "circle.lefthalf.filled"
        case .whites: "sun.max.trianglebadge.exclamationmark"
        case .contrast: "circle.righthalf.filled"
        case .brightness: "sun.min"
        case .blackPoint: "circle.fill"
        case .saturation: "drop.fill"
        case .vibrance: "paintpalette.fill"
        case .warmth: "thermometer.sun"
        case .tint: "eyedropper.halffull"
        case .sharpness: "triangle"
        case .definition: "circle.dotted"
        case .noiseReduction: "aqi.medium"
        case .vignette: "viewfinder"
        case .grain: "circle.grid.3x3.fill"
        case .rawTemperature: "thermometer.medium"
        case .rawTint: "slider.horizontal.2.square"
        case .rawLuminanceNoise: "sparkles.rectangle.stack"
        case .rawColorNoise: "circle.hexagongrid"
        case .rawSharpness: "camera.filters"
        case .lensCorrection: "camera.metering.center.weighted"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .lensCorrection, .grain: 0...1
        case .exposure: -2...2
        default: -1...1
        }
    }

    var isRAWOnly: Bool {
        switch self {
        case .rawTemperature, .rawTint, .rawLuminanceNoise, .rawColorNoise,
             .rawSharpness, .lensCorrection:
            true
        default:
            false
        }
    }

    var affectsRAWDemosaic: Bool {
        self == .exposure || isRAWOnly
    }
}

struct PhotoAdjustments: Codable, Equatable, Sendable {
    var exposure = 0.0
    var brilliance = 0.0
    var highlights = 0.0
    var shadows = 0.0
    var whites = 0.0
    var contrast = 0.0
    var brightness = 0.0
    var blackPoint = 0.0
    var saturation = 0.0
    var vibrance = 0.0
    var warmth = 0.0
    var tint = 0.0
    var sharpness = 0.0
    var definition = 0.0
    var noiseReduction = 0.0
    var vignette = 0.0
    var grain = 0.0
    var rawTemperature = 0.0
    var rawTint = 0.0
    var rawLuminanceNoise = 0.0
    var rawColorNoise = 0.0
    var rawSharpness = 0.0
    var lensCorrection = 1.0

    static let zero = PhotoAdjustments()

    subscript(kind: PhotoAdjustmentKind) -> Double {
        get {
            switch kind {
            case .exposure: exposure
            case .brilliance: brilliance
            case .highlights: highlights
            case .shadows: shadows
            case .whites: whites
            case .contrast: contrast
            case .brightness: brightness
            case .blackPoint: blackPoint
            case .saturation: saturation
            case .vibrance: vibrance
            case .warmth: warmth
            case .tint: tint
            case .sharpness: sharpness
            case .definition: definition
            case .noiseReduction: noiseReduction
            case .vignette: vignette
            case .grain: grain
            case .rawTemperature: rawTemperature
            case .rawTint: rawTint
            case .rawLuminanceNoise: rawLuminanceNoise
            case .rawColorNoise: rawColorNoise
            case .rawSharpness: rawSharpness
            case .lensCorrection: lensCorrection
            }
        }
        set {
            switch kind {
            case .exposure: exposure = newValue
            case .brilliance: brilliance = newValue
            case .highlights: highlights = newValue
            case .shadows: shadows = newValue
            case .whites: whites = newValue
            case .contrast: contrast = newValue
            case .brightness: brightness = newValue
            case .blackPoint: blackPoint = newValue
            case .saturation: saturation = newValue
            case .vibrance: vibrance = newValue
            case .warmth: warmth = newValue
            case .tint: tint = newValue
            case .sharpness: sharpness = newValue
            case .definition: definition = newValue
            case .noiseReduction: noiseReduction = newValue
            case .vignette: vignette = newValue
            case .grain: grain = newValue
            case .rawTemperature: rawTemperature = newValue
            case .rawTint: rawTint = newValue
            case .rawLuminanceNoise: rawLuminanceNoise = newValue
            case .rawColorNoise: rawColorNoise = newValue
            case .rawSharpness: rawSharpness = newValue
            case .lensCorrection: lensCorrection = newValue
            }
        }
    }

    var isIdentity: Bool {
        var comparison = self
        comparison.lensCorrection = 1
        return comparison == .zero
    }
}

/// The stored keys are exactly the slider names, so the kind enum doubles as the
/// coding key. Decoding each value with `decodeIfPresent` keeps recipes saved by
/// an earlier build readable after a new slider is added.
extension PhotoAdjustmentKind: CodingKey {
    var stringValue: String { rawValue }
    var intValue: Int? { nil }

    init?(stringValue: String) {
        self.init(rawValue: stringValue)
    }

    init?(intValue _: Int) {
        return nil
    }
}

extension PhotoAdjustments {
    init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: PhotoAdjustmentKind.self)
        for kind in PhotoAdjustmentKind.allCases {
            guard let value = try container.decodeIfPresent(Double.self, forKey: kind)
            else { continue }
            self[kind] = value
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: PhotoAdjustmentKind.self)
        let defaults = PhotoAdjustments()
        for kind in PhotoAdjustmentKind.allCases where self[kind] != defaults[kind] {
            try container.encode(self[kind], forKey: kind)
        }
    }
}

struct NormalizedPoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double

    static let center = NormalizedPoint(x: 0.5, y: 0.5)

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

struct NormalizedRect: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

enum CropAspect: String, Codable, CaseIterable, Identifiable, Sendable {
    case free
    case original
    case square
    case fourThree
    case threeTwo
    case sixteenNine
    case fourFive
    case nineSixteen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .free: "Free"
        case .original: "Original"
        case .square: "1:1"
        case .fourThree: "4:3"
        case .threeTwo: "3:2"
        case .sixteenNine: "16:9"
        case .fourFive: "4:5"
        case .nineSixteen: "9:16"
        }
    }

    var ratio: Double? {
        switch self {
        case .free, .original: nil
        case .square: 1
        case .fourThree: 4 / 3
        case .threeTwo: 3 / 2
        case .sixteenNine: 16 / 9
        case .fourFive: 4 / 5
        case .nineSixteen: 9 / 16
        }
    }
}

/// Side of the crop frame being dragged. Photos lets you grab an edge, not just a
/// corner, so the frame can be trimmed one side at a time.
enum CropEdge: String, CaseIterable, Identifiable, Sendable {
    case left
    case right
    case top
    case bottom

    var id: String { rawValue }
    var isHorizontal: Bool { self == .left || self == .right }
}

struct PhotoCropRecipe: Codable, Equatable, Sendable {
    var rect = NormalizedRect.full
    var aspect: CropAspect = .free
    var straightenDegrees = 0.0
    var quarterTurns = 0
    var flippedHorizontally = false

    static let identity = PhotoCropRecipe()
}

enum MaskBlendOperation: String, Codable, CaseIterable, Identifiable, Sendable {
    case add
    case subtract

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum PhotoMaskComponentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case brush
    case linearGradient
    case radialGradient
    case subject
    case sky
    case luminanceRange
    case colorRange

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .brush: "Brush"
        case .linearGradient: "Linear Gradient"
        case .radialGradient: "Radial Gradient"
        case .subject: "Subject"
        case .sky: "Sky"
        case .luminanceRange: "Luminance Range"
        case .colorRange: "Color Range"
        }
    }

    var systemImage: String {
        switch self {
        case .brush: "paintbrush.pointed"
        case .linearGradient: "square.tophalf.filled"
        case .radialGradient: "circle.dotted"
        case .subject: "person.crop.rectangle"
        case .sky: "cloud.sun"
        case .luminanceRange: "circle.lefthalf.striped.horizontal"
        case .colorRange: "eyedropper"
        }
    }
}

struct BrushStroke: Codable, Equatable, Sendable {
    var points: [NormalizedPoint]
    var size: Double
    var feather: Double
    var flow: Double
    var isEraser: Bool
}

struct PhotoMaskComponent: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var kind: PhotoMaskComponentKind
    var operation: MaskBlendOperation = .add
    var opacity = 1.0

    var brushStrokes: [BrushStroke] = []
    var startPoint = NormalizedPoint(x: 0.5, y: 0.2)
    var endPoint = NormalizedPoint(x: 0.5, y: 0.8)
    var center = NormalizedPoint.center
    var radiusX = 0.3
    var radiusY = 0.3
    var feather = 0.5
    var subjectPoint = NormalizedPoint.center
    var luminanceMinimum = 0.25
    var luminanceMaximum = 0.75
    var sampledRed = 0.5
    var sampledGreen = 0.5
    var sampledBlue = 0.5
    var colorTolerance = 0.2

    init(kind: PhotoMaskComponentKind, operation: MaskBlendOperation = .add) {
        self.kind = kind
        self.operation = operation
    }
}

struct PhotoMask: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var isVisible = true
    var isInverted = false
    var components: [PhotoMaskComponent]
    var adjustments = PhotoAdjustments.zero

    init(name: String, component: PhotoMaskComponent) {
        self.name = name
        self.components = [component]
    }
}

struct PhotoEditRecipe: Codable, Equatable, Sendable {
    static let formatIdentifier = "com.hoangtuan.shotdex.photo-edit"
    static let formatVersion = "1.0"

    var source: PhotoEditSource = .automatic
    var sourceFilename: String?
    /// Save Copy keeps rendering from the original asset's immutable PhotoKit
    /// resource so RAW controls can be recalled exactly on the rendered copy.
    /// Local identifiers are intentionally device-local; no separate iCloud
    /// recipe/source synchronization is attempted.
    var sourceAssetIdentifier: String?
    var adjustments = PhotoAdjustments.zero
    var filter: PhotoFilter = .original
    /// How much of the chosen filter is mixed over the unfiltered image. Only
    /// meaningful when `filter != .original`.
    var filterIntensity = 1.0
    var crop = PhotoCropRecipe.identity
    var masks: [PhotoMask] = []
    var color = PhotoColorRecipe.identity
    /// Clone / Heal / Remove areas, applied after crop and before local masks.
    /// Order matters: a later stroke reads the pixels earlier ones produced.
    var cleanUpStrokes: [CleanUpStroke] = []

    static let identity = PhotoEditRecipe()

    var isIdentity: Bool {
        adjustments.isIdentity
            && filter == .original
            && crop == .identity
            && masks.isEmpty
            && color.isIdentity
            && cleanUpStrokes.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case sourceFilename
        case sourceAssetIdentifier
        case adjustments
        case filter
        case filterIntensity
        case crop
        case masks
        case color
        case cleanUpStrokes
    }

    init() {}

    /// Recipes written by an earlier build lack the newer keys, so every field is
    /// optional on the wire and falls back to its identity value.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decodeIfPresent(PhotoEditSource.self, forKey: .source)
            ?? .automatic
        sourceFilename = try container.decodeIfPresent(String.self, forKey: .sourceFilename)
        sourceAssetIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .sourceAssetIdentifier
        )
        adjustments = try container.decodeIfPresent(
            PhotoAdjustments.self,
            forKey: .adjustments
        ) ?? .zero
        filter = try container.decodeIfPresent(PhotoFilter.self, forKey: .filter) ?? .original
        filterIntensity = try container.decodeIfPresent(
            Double.self,
            forKey: .filterIntensity
        ) ?? 1
        crop = try container.decodeIfPresent(PhotoCropRecipe.self, forKey: .crop) ?? .identity
        masks = try container.decodeIfPresent([PhotoMask].self, forKey: .masks) ?? []
        color = try container.decodeIfPresent(PhotoColorRecipe.self, forKey: .color) ?? .identity
        cleanUpStrokes = try container.decodeIfPresent(
            [CleanUpStroke].self,
            forKey: .cleanUpStrokes
        ) ?? []
    }

    /// Written by hand so an untouched Color or Clean Up tab adds no key at all —
    /// a recipe saved without those edits stays byte-compatible with earlier
    /// builds.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(sourceFilename, forKey: .sourceFilename)
        try container.encodeIfPresent(sourceAssetIdentifier, forKey: .sourceAssetIdentifier)
        try container.encode(adjustments, forKey: .adjustments)
        try container.encode(filter, forKey: .filter)
        try container.encode(filterIntensity, forKey: .filterIntensity)
        try container.encode(crop, forKey: .crop)
        try container.encode(masks, forKey: .masks)
        if !color.isIdentity { try container.encode(color, forKey: .color) }
        if !cleanUpStrokes.isEmpty {
            try container.encode(cleanUpStrokes, forKey: .cleanUpStrokes)
        }
    }
}

struct PhotoExportOptions: Codable, Equatable, Sendable {
    var format: PhotoOutputFormat
    var quality: Double
    var preset: ResizePreset
    var includeMetadata: Bool
    var cropAnchor: NormalizedPoint

    static let compressDefault = PhotoExportOptions(
        format: .preserve,
        quality: 0.8,
        preset: .original,
        includeMetadata: true,
        cropAnchor: .center
    )
}

enum PhotoEditingError: LocalizedError, Sendable {
    case unavailable
    case unsupportedRAW
    case missingSource
    case cannotDecode
    case cannotRender
    case cannotEncode
    case unsupportedOutputFormat
    case cancelled
    case cannotCreateAsset
    case cannotAddToAlbum

    var errorDescription: String? {
        switch self {
        case .unavailable: "This photo is unavailable."
        case .unsupportedRAW: "This RAW format can't be decoded on this device."
        case .missingSource: "The original photo file couldn't be loaded."
        case .cannotDecode: "The photo couldn't be decoded."
        case .cannotRender: "The edits couldn't be rendered."
        case .cannotEncode: "The edited photo couldn't be encoded."
        case .unsupportedOutputFormat: "Photos doesn't support the selected output format for this asset."
        case .cancelled: "The operation was cancelled."
        case .cannotCreateAsset: "The new photo couldn't be saved."
        case .cannotAddToAlbum: "The photo was saved, but couldn't be added to the album."
        }
    }
}
