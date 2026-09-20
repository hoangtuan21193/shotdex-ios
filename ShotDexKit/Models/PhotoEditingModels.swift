import CoreGraphics
import Foundation
import UniformTypeIdentifiers

public struct PhotoHistogram: Equatable, Sendable {
    public var red: [Double]
    public var green: [Double]
    public var blue: [Double]
    /// Fraction of sampled pixels at the top of the range, used by the editor's
    /// clipping indicator. Kept out of the plotted bins so a clipped peak can be
    /// flagged even after percentile normalization flattens it.
    public var clippedHighlightFraction = 0.0
    public var clippedShadowFraction = 0.0

    public static let empty = PhotoHistogram(red: [], green: [], blue: [])

    public var luminance: [Double] {
        zip(zip(red, green), blue).map {
            0.2126 * $0.0.0 + 0.7152 * $0.0.1 + 0.0722 * $0.1
        }
    }

    public var hasClippedHighlights: Bool { clippedHighlightFraction > 0.001 }
    public var hasClippedShadows: Bool { clippedShadowFraction > 0.001 }
}

public enum PhotoOutputFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case preserve
    case jpeg
    case heic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .preserve: "Same as Original"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        }
    }

    public var fileExtension: String {
        switch self {
        case .preserve, .jpeg: "jpg"
        case .heic: "heic"
        }
    }

    public var uniformType: UTType {
        switch self {
        case .preserve, .jpeg: .jpeg
        case .heic: .heic
        }
    }
}

public enum ResizeCropMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fill
    case fit

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}

public enum ResizePresetKind: String, Codable, Sendable {
    case original
    case longEdge
    case exact
}

public struct ResizePreset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: ResizePresetKind
    public var longEdge: Int?
    public var width: Int?
    public var height: Int?
    public var cropMode: ResizeCropMode
    public var quality: Double
    public var format: PhotoOutputFormat
    public var isBuiltIn: Bool

    public init(
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

    public static let original = ResizePreset(
        id: UUID(uuidString: "5CEB1742-9BB8-4E36-8075-5C60543B40D9")!,
        name: "Original",
        kind: .original,
        isBuiltIn: true
    )

    public static let fourK = ResizePreset(
        id: UUID(uuidString: "447E6B22-6070-47C8-8E39-A06523B34462")!,
        name: "4K",
        kind: .longEdge,
        longEdge: 3_840,
        isBuiltIn: true
    )

    public static let twoK = ResizePreset(
        id: UUID(uuidString: "9E85B65C-C492-435F-8DA1-A4DA2732852F")!,
        name: "2048 px",
        kind: .longEdge,
        longEdge: 2_048,
        isBuiltIn: true
    )

    public static let social = ResizePreset(
        id: UUID(uuidString: "91A9AA69-47DF-4FB2-9D1E-E5AF8B111A30")!,
        name: "1080 px",
        kind: .longEdge,
        longEdge: 1_080,
        isBuiltIn: true
    )

    public static let builtIns: [ResizePreset] = [.original, .fourK, .twoK, .social]

    public var allowsLongEdgeUpscaling: Bool {
        id == Self.fourK.id || id == Self.social.id
    }

    public func targetPixelSize(sourceWidth: Int, sourceHeight: Int) -> CGSize {
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

public enum PhotoEditSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case raw
    case rendered

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .raw: "RAW"
        case .rendered: "JPEG"
        }
    }
}

/// Every look the Filters tab offers. Raw values are persisted inside saved
/// recipes, so a case may be added but never renamed.
///
/// The first ten are the original Core Image presets. Everything after them is a
/// film simulation driven by a `FilmLook` — the nineteen an X-T5 has, the twelve
/// Leica Looks, and six well-known stocks neither company sells a mode for.
public enum PhotoFilter: String, Codable, CaseIterable, Identifiable, Sendable {
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

    // Fujifilm colour simulations.
    case provia
    case velvia
    case astia
    case classicChrome
    case proNegHi
    case proNegStd
    case classicNeg
    case nostalgicNeg
    case eterna
    case eternaBleachBypass

    // Fujifilm monochrome simulations, plus the two black-and-white stocks that
    // belong in the same strip. `fuji`-prefixed because `mono` and `silvertone`
    // above are already taken by the original presets.
    case acros
    case acrosYellow
    case acrosRed
    case acrosGreen
    case fujiMonochrome
    case fujiMonochromeYellow
    case fujiMonochromeRed
    case fujiMonochromeGreen
    case fujiSepia
    case hp5
    case triX

    // Leica Looks.
    case leicaChrome
    case leicaClassic
    case leicaContemporary
    case leicaEternal
    case leicaBlue
    case leicaSelenium
    case leicaSepia
    case leicaBleach
    case leicaSilver
    case leicaTeal
    case leicaBrass
    case leicaGregWilliams

    // Colour stocks.
    case portra400
    case gold200
    case kodachrome64
    case ektar100
    case superia400
    case cineStill800T

    public var id: String { rawValue }

    public var displayName: String {
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
        case .provia: "PROVIA / Standard"
        case .velvia: "Velvia / Vivid"
        case .astia: "ASTIA / Soft"
        case .classicChrome: "Classic Chrome"
        case .proNegHi: "PRO Neg. Hi"
        case .proNegStd: "PRO Neg. Std"
        case .classicNeg: "Classic Negative"
        case .nostalgicNeg: "Nostalgic Neg."
        case .eterna: "ETERNA / Cinema"
        case .eternaBleachBypass: "ETERNA Bleach Bypass"
        case .acros: "ACROS"
        case .acrosYellow: "ACROS + Ye Filter"
        case .acrosRed: "ACROS + R Filter"
        case .acrosGreen: "ACROS + G Filter"
        case .fujiMonochrome: "Monochrome"
        case .fujiMonochromeYellow: "Monochrome + Ye Filter"
        case .fujiMonochromeRed: "Monochrome + R Filter"
        case .fujiMonochromeGreen: "Monochrome + G Filter"
        case .fujiSepia: "Sepia"
        case .hp5: "Ilford HP5 Plus"
        case .triX: "Kodak Tri-X 400"
        case .leicaChrome: "Leica Chrome"
        case .leicaClassic: "Leica Classic"
        case .leicaContemporary: "Leica Contemporary"
        case .leicaEternal: "Leica Eternal"
        case .leicaBlue: "Leica Blue"
        case .leicaSelenium: "Leica Selenium"
        case .leicaSepia: "Leica Sepia"
        case .leicaBleach: "Leica Bleach"
        case .leicaSilver: "Leica Silver"
        case .leicaTeal: "Leica Teal"
        case .leicaBrass: "Leica Brass"
        case .leicaGregWilliams: "Leica Greg Williams"
        case .portra400: "Kodak Portra 400"
        case .gold200: "Kodak Gold 200"
        case .kodachrome64: "Kodachrome 64"
        case .ektar100: "Kodak Ektar 100"
        case .superia400: "Fujicolor Superia 400"
        case .cineStill800T: "CineStill 800T"
        }
    }

    /// Caption under a swatch. A tile is about 60pt wide, so anything longer than
    /// roughly twelve characters has to lose the part the strip's own heading
    /// already says — the brand.
    public var tileName: String {
        switch self {
        case .provia: "PROVIA"
        case .velvia: "Velvia"
        case .astia: "ASTIA"
        case .classicChrome: "Cl. Chrome"
        case .proNegHi: "Neg. Hi"
        case .proNegStd: "Neg. Std"
        case .classicNeg: "Cl. Neg."
        case .nostalgicNeg: "Nostalgic"
        case .eterna: "ETERNA"
        case .eternaBleachBypass: "Bleach BP"
        case .acrosYellow: "ACROS+Ye"
        case .acrosRed: "ACROS+R"
        case .acrosGreen: "ACROS+G"
        case .fujiMonochrome: "Mono"
        case .fujiMonochromeYellow: "Mono+Ye"
        case .fujiMonochromeRed: "Mono+R"
        case .fujiMonochromeGreen: "Mono+G"
        case .hp5: "HP5"
        case .triX: "Tri-X"
        case .leicaChrome: "Chrome"
        case .leicaClassic: "Classic"
        case .leicaContemporary: "Contemp."
        case .leicaEternal: "Eternal"
        case .leicaBlue: "Blue"
        case .leicaSelenium: "Selenium"
        case .leicaSepia: "Sepia"
        case .leicaBleach: "Bleach"
        case .leicaSilver: "Silver"
        case .leicaTeal: "Teal"
        case .leicaBrass: "Brass"
        case .leicaGregWilliams: "G. Williams"
        case .portra400: "Portra 400"
        case .gold200: "Gold 200"
        case .kodachrome64: "Kodachrome"
        case .ektar100: "Ektar 100"
        case .superia400: "Superia"
        case .cineStill800T: "800T"
        default: displayName
        }
    }

    public var category: FilmLookCategory {
        switch self {
        case .original, .vivid, .vividWarm, .vividCool, .dramatic, .dramaticWarm,
             .dramaticCool, .mono, .silvertone, .noir:
            .basic
        case .provia, .velvia, .astia, .classicChrome, .proNegHi, .proNegStd,
             .classicNeg, .nostalgicNeg, .eterna, .eternaBleachBypass,
             .leicaChrome, .leicaClassic, .leicaContemporary, .leicaEternal,
             .leicaBleach, .leicaTeal, .leicaBrass, .leicaGregWilliams,
             .portra400, .gold200, .kodachrome64, .ektar100, .superia400,
             .cineStill800T:
            .film
        // Sorted by what the look *is*, not who makes it: a toned silver print
        // belongs beside the other black-and-white looks.
        case .acros, .acrosYellow, .acrosRed, .acrosGreen, .fujiMonochrome,
             .fujiMonochromeYellow, .fujiMonochromeRed, .fujiMonochromeGreen,
             .fujiSepia, .hp5, .triX, .leicaBlue, .leicaSelenium, .leicaSepia,
             .leicaSilver:
            .monochrome
        }
    }

    /// Ordered as declared, so a strip always shows its looks in the order the
    /// camera's own menu does.
    public static func all(in category: FilmLookCategory) -> [PhotoFilter] {
        allCases.filter { $0.category == category }
    }
}

public enum PhotoAdjustmentKind: String, Codable, CaseIterable, Identifiable, Sendable {
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
    case blackAndWhite
    case sharpness
    case sharpenRadius
    case sharpenDetail
    case sharpenMasking
    case definition
    case noiseReduction
    case colorNoiseReduction
    case texture
    case clarity
    case dehaze
    case vignette
    case vignetteMidpoint
    case vignetteFeather
    case vignetteRoundness
    case vignetteHighlights
    case grain
    case grainSize
    case grainRoughness
    /// Portrait depth blur. Only meaningful on a photo that carries depth, so
    /// the catalog hides the row on every other photo rather than offering a
    /// slider that does nothing.
    case depthBlur
    // Optics
    case chromaticAberration
    case defringe
    // Geo (transform)
    case geoVertical
    case geoHorizontal
    case geoRotate
    case geoScale
    case geoOffsetX
    case geoOffsetY
    case rawTemperature
    case rawTint
    case rawLuminanceNoise
    case rawColorNoise
    case rawSharpness
    case lensCorrection

    public var id: String { rawValue }

    public var displayName: String {
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
        case .blackAndWhite: "Black & White"
        case .sharpness: "Sharpness"
        case .sharpenRadius: "Sharpen Radius"
        case .sharpenDetail: "Sharpen Detail"
        case .sharpenMasking: "Sharpen Masking"
        case .definition: "Definition"
        case .noiseReduction: "Noise"
        case .colorNoiseReduction: "Color Noise"
        case .texture: "Texture"
        case .clarity: "Clarity"
        case .depthBlur: "Depth Blur"
        case .dehaze: "Dehaze"
        case .vignette: "Vignette"
        case .vignetteMidpoint: "Vignette Midpoint"
        case .vignetteFeather: "Vignette Feather"
        case .vignetteRoundness: "Vignette Roundness"
        case .vignetteHighlights: "Vignette Highlights"
        case .grain: "Grain"
        case .grainSize: "Grain Size"
        case .grainRoughness: "Grain Roughness"
        case .chromaticAberration: "Remove Chromatic Aberration"
        case .defringe: "Defringe"
        case .geoVertical: "Vertical"
        case .geoHorizontal: "Horizontal"
        case .geoRotate: "Rotate"
        case .geoScale: "Scale"
        case .geoOffsetX: "Offset X"
        case .geoOffsetY: "Offset Y"
        case .rawTemperature: "RAW White Balance"
        case .rawTint: "RAW Tint"
        case .rawLuminanceNoise: "RAW Luminance Noise"
        case .rawColorNoise: "RAW Color Noise"
        case .rawSharpness: "RAW Sharpening"
        case .lensCorrection: "Lens Correction"
        }
    }

    public var systemImage: String {
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
        case .blackAndWhite: "circle.lefthalf.filled.inverse"
        case .sharpness: "triangle"
        case .sharpenRadius: "triangle.tophalf.filled"
        case .sharpenDetail: "triangle.righthalf.filled"
        case .sharpenMasking: "theatermask.and.paintbrush"
        case .definition: "circle.dotted"
        case .noiseReduction: "aqi.medium"
        case .colorNoiseReduction: "drop.halffull"
        case .texture: "circle.grid.2x2"
        case .clarity: "circle.hexagonpath"
        case .depthBlur: "camera.aperture"
        case .dehaze: "sun.haze"
        case .vignette: "viewfinder"
        case .vignetteMidpoint: "smallcircle.circle"
        case .vignetteFeather: "circle.dashed"
        case .vignetteRoundness: "squareshape.dashed.squareshape"
        case .vignetteHighlights: "sun.max.circle"
        case .grain: "circle.grid.3x3.fill"
        case .grainSize: "circle.grid.3x3"
        case .grainRoughness: "circle.grid.3x3.circle"
        case .chromaticAberration: "camera.aperture"
        case .defringe: "scribble.variable"
        case .geoVertical: "perspective"
        case .geoHorizontal: "perspective"
        case .geoRotate: "rotate.right"
        case .geoScale: "arrow.up.left.and.arrow.down.right"
        case .geoOffsetX: "arrow.left.and.right"
        case .geoOffsetY: "arrow.up.and.down"
        case .rawTemperature: "thermometer.medium"
        case .rawTint: "slider.horizontal.2.square"
        case .rawLuminanceNoise: "sparkles.rectangle.stack"
        case .rawColorNoise: "circle.hexagongrid"
        case .rawSharpness: "camera.filters"
        case .lensCorrection: "camera.metering.center.weighted"
        }
    }

    public var range: ClosedRange<Double> {
        switch self {
        case .lensCorrection, .grain, .grainSize, .grainRoughness,
             .vignetteMidpoint, .vignetteFeather, .blackAndWhite,
             .sharpenRadius, .sharpenDetail, .sharpenMasking, .colorNoiseReduction,
             .vignetteHighlights, .chromaticAberration, .defringe, .depthBlur: 0...1
        case .exposure: -2...2
        default: -1...1
        }
    }

    public var isRAWOnly: Bool {
        switch self {
        case .rawTemperature, .rawTint, .rawLuminanceNoise, .rawColorNoise,
             .rawSharpness, .lensCorrection:
            true
        default:
            false
        }
    }

    public var affectsRAWDemosaic: Bool {
        self == .exposure || isRAWOnly
    }
}

public struct PhotoAdjustments: Codable, Equatable, Sendable {
    public init(
        exposure: Double = 0.0,
        brilliance: Double = 0.0,
        highlights: Double = 0.0,
        shadows: Double = 0.0,
        whites: Double = 0.0,
        contrast: Double = 0.0,
        brightness: Double = 0.0,
        blackPoint: Double = 0.0,
        saturation: Double = 0.0,
        vibrance: Double = 0.0,
        warmth: Double = 0.0,
        tint: Double = 0.0,
        blackAndWhite: Double = 0.0,
        sharpness: Double = 0.0,
        sharpenRadius: Double = 0.0,
        sharpenDetail: Double = 0.0,
        sharpenMasking: Double = 0.0,
        definition: Double = 0.0,
        noiseReduction: Double = 0.0,
        colorNoiseReduction: Double = 0.0,
        texture: Double = 0.0,
        clarity: Double = 0.0,
        dehaze: Double = 0.0,
        depthBlur: Double = 0.0,
        vignette: Double = 0.0,
        vignetteMidpoint: Double = 0.5,
        vignetteFeather: Double = 0.5,
        vignetteRoundness: Double = 0.0,
        vignetteHighlights: Double = 0.0,
        grain: Double = 0.0,
        grainSize: Double = 0.0,
        grainRoughness: Double = 0.0,
        chromaticAberration: Double = 0.0,
        defringe: Double = 0.0,
        geoVertical: Double = 0.0,
        geoHorizontal: Double = 0.0,
        geoRotate: Double = 0.0,
        geoScale: Double = 0.0,
        geoOffsetX: Double = 0.0,
        geoOffsetY: Double = 0.0,
        rawTemperature: Double = 0.0,
        rawTint: Double = 0.0,
        rawLuminanceNoise: Double = 0.0,
        rawColorNoise: Double = 0.0,
        rawSharpness: Double = 0.0,
        lensCorrection: Double = 1.0,
    ) {
        self.exposure = exposure
        self.brilliance = brilliance
        self.highlights = highlights
        self.shadows = shadows
        self.whites = whites
        self.contrast = contrast
        self.brightness = brightness
        self.blackPoint = blackPoint
        self.saturation = saturation
        self.vibrance = vibrance
        self.warmth = warmth
        self.tint = tint
        self.blackAndWhite = blackAndWhite
        self.sharpness = sharpness
        self.sharpenRadius = sharpenRadius
        self.sharpenDetail = sharpenDetail
        self.sharpenMasking = sharpenMasking
        self.definition = definition
        self.noiseReduction = noiseReduction
        self.colorNoiseReduction = colorNoiseReduction
        self.texture = texture
        self.clarity = clarity
        self.dehaze = dehaze
        self.depthBlur = depthBlur
        self.vignette = vignette
        self.vignetteMidpoint = vignetteMidpoint
        self.vignetteFeather = vignetteFeather
        self.vignetteRoundness = vignetteRoundness
        self.vignetteHighlights = vignetteHighlights
        self.grain = grain
        self.grainSize = grainSize
        self.grainRoughness = grainRoughness
        self.chromaticAberration = chromaticAberration
        self.defringe = defringe
        self.geoVertical = geoVertical
        self.geoHorizontal = geoHorizontal
        self.geoRotate = geoRotate
        self.geoScale = geoScale
        self.geoOffsetX = geoOffsetX
        self.geoOffsetY = geoOffsetY
        self.rawTemperature = rawTemperature
        self.rawTint = rawTint
        self.rawLuminanceNoise = rawLuminanceNoise
        self.rawColorNoise = rawColorNoise
        self.rawSharpness = rawSharpness
        self.lensCorrection = lensCorrection
    }

    public var exposure = 0.0
    public var brilliance = 0.0
    public var highlights = 0.0
    public var shadows = 0.0
    public var whites = 0.0
    public var contrast = 0.0
    public var brightness = 0.0
    public var blackPoint = 0.0
    public var saturation = 0.0
    public var vibrance = 0.0
    public var warmth = 0.0
    public var tint = 0.0
    public var blackAndWhite = 0.0
    public var sharpness = 0.0
    public var sharpenRadius = 0.0
    public var sharpenDetail = 0.0
    public var sharpenMasking = 0.0
    public var definition = 0.0
    public var noiseReduction = 0.0
    public var colorNoiseReduction = 0.0
    public var texture = 0.0
    public var clarity = 0.0
    public var dehaze = 0.0
    /// Portrait depth blur, 0 = the photo as shot. Not a stop count: the
    /// f-number the panel shows is a label over this, because the strength
    /// Core Image's depth blur takes is not calibrated in stops.
    public var depthBlur = 0.0
    public var vignette = 0.0
    /// Where the vignette starts falling off (0 = near the centre, 1 = only the
    /// extreme corners). Default 0.5 — a neutral value, so it is part of `.zero`
    /// and adds no key until touched.
    public var vignetteMidpoint = 0.5
    public var vignetteFeather = 0.5
    public var vignetteRoundness = 0.0
    public var vignetteHighlights = 0.0
    public var grain = 0.0
    public var grainSize = 0.0
    public var grainRoughness = 0.0
    public var chromaticAberration = 0.0
    public var defringe = 0.0
    public var geoVertical = 0.0
    public var geoHorizontal = 0.0
    public var geoRotate = 0.0
    public var geoScale = 0.0
    public var geoOffsetX = 0.0
    public var geoOffsetY = 0.0
    public var rawTemperature = 0.0
    public var rawTint = 0.0
    public var rawLuminanceNoise = 0.0
    public var rawColorNoise = 0.0
    public var rawSharpness = 0.0
    public var lensCorrection = 1.0

    public static let zero = PhotoAdjustments()

    public subscript(kind: PhotoAdjustmentKind) -> Double {
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
            case .blackAndWhite: blackAndWhite
            case .sharpness: sharpness
            case .sharpenRadius: sharpenRadius
            case .sharpenDetail: sharpenDetail
            case .sharpenMasking: sharpenMasking
            case .definition: definition
            case .noiseReduction: noiseReduction
            case .colorNoiseReduction: colorNoiseReduction
            case .texture: texture
            case .clarity: clarity
            case .depthBlur: depthBlur
            case .dehaze: dehaze
            case .vignette: vignette
            case .vignetteMidpoint: vignetteMidpoint
            case .vignetteFeather: vignetteFeather
            case .vignetteRoundness: vignetteRoundness
            case .vignetteHighlights: vignetteHighlights
            case .grain: grain
            case .grainSize: grainSize
            case .grainRoughness: grainRoughness
            case .chromaticAberration: chromaticAberration
            case .defringe: defringe
            case .geoVertical: geoVertical
            case .geoHorizontal: geoHorizontal
            case .geoRotate: geoRotate
            case .geoScale: geoScale
            case .geoOffsetX: geoOffsetX
            case .geoOffsetY: geoOffsetY
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
            case .blackAndWhite: blackAndWhite = newValue
            case .sharpness: sharpness = newValue
            case .sharpenRadius: sharpenRadius = newValue
            case .sharpenDetail: sharpenDetail = newValue
            case .sharpenMasking: sharpenMasking = newValue
            case .definition: definition = newValue
            case .noiseReduction: noiseReduction = newValue
            case .colorNoiseReduction: colorNoiseReduction = newValue
            case .texture: texture = newValue
            case .clarity: clarity = newValue
            case .depthBlur: depthBlur = newValue
            case .dehaze: dehaze = newValue
            case .vignette: vignette = newValue
            case .vignetteMidpoint: vignetteMidpoint = newValue
            case .vignetteFeather: vignetteFeather = newValue
            case .vignetteRoundness: vignetteRoundness = newValue
            case .vignetteHighlights: vignetteHighlights = newValue
            case .grain: grain = newValue
            case .grainSize: grainSize = newValue
            case .grainRoughness: grainRoughness = newValue
            case .chromaticAberration: chromaticAberration = newValue
            case .defringe: defringe = newValue
            case .geoVertical: geoVertical = newValue
            case .geoHorizontal: geoHorizontal = newValue
            case .geoRotate: geoRotate = newValue
            case .geoScale: geoScale = newValue
            case .geoOffsetX: geoOffsetX = newValue
            case .geoOffsetY: geoOffsetY = newValue
            case .rawTemperature: rawTemperature = newValue
            case .rawTint: rawTint = newValue
            case .rawLuminanceNoise: rawLuminanceNoise = newValue
            case .rawColorNoise: rawColorNoise = newValue
            case .rawSharpness: rawSharpness = newValue
            case .lensCorrection: lensCorrection = newValue
            }
        }
    }

    public var isIdentity: Bool {
        var comparison = self
        comparison.lensCorrection = 1
        return comparison == .zero
    }
}

/// The stored keys are exactly the slider names, so the kind enum doubles as the
/// coding key. Decoding each value with `decodeIfPresent` keeps recipes saved by
/// an earlier build readable after a new slider is added.
extension PhotoAdjustmentKind: CodingKey {
    public var stringValue: String { rawValue }
    public var intValue: Int? { nil }

    public init?(stringValue: String) {
        self.init(rawValue: stringValue)
    }

    public init?(intValue _: Int) {
        return nil
    }
}

public extension PhotoAdjustments {
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

public struct NormalizedPoint: Codable, Hashable, Sendable {
    public init(
        x: Double,
        y: Double,
    ) {
        self.x = x
        self.y = y
    }

    public var x: Double
    public var y: Double

    public static let center = NormalizedPoint(x: 0.5, y: 0.5)

    public var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

public struct NormalizedRect: Codable, Equatable, Sendable {
    public init(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public static let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

public enum CropAspect: String, Codable, CaseIterable, Identifiable, Sendable {
    case free
    case original
    case square
    case fourThree
    case threeTwo
    case sixteenNine
    case fourFive
    case nineSixteen

    public var id: String { rawValue }

    public var displayName: String {
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

    public var ratio: Double? {
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
public enum CropEdge: String, CaseIterable, Identifiable, Sendable {
    case left
    case right
    case top
    case bottom

    public var id: String { rawValue }
    public var isHorizontal: Bool { self == .left || self == .right }
}

public struct PhotoCropRecipe: Codable, Equatable, Sendable {
    public var rect = NormalizedRect.full
    public var aspect: CropAspect = .free
    public var straightenDegrees = 0.0
    public var quarterTurns = 0
    public var flippedHorizontally = false

    public static let identity = PhotoCropRecipe()
}

public enum MaskBlendOperation: String, Codable, CaseIterable, Identifiable, Sendable {
    case add
    case subtract

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}

public enum PhotoMaskComponentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case brush
    case linearGradient
    case radialGradient
    case subject
    case sky
    case luminanceRange
    case colorRange

    public var id: String { rawValue }

    public var displayName: String {
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

    public var systemImage: String {
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

public struct BrushStroke: Codable, Equatable, Sendable {
    public init(
        points: [NormalizedPoint],
        size: Double,
        feather: Double,
        flow: Double,
        isEraser: Bool,
        pressures: [Double] = [],
    ) {
        self.points = points
        self.size = size
        self.feather = feather
        self.flow = flow
        self.isEraser = isEraser
        self.pressures = pressures
    }

    public var points: [NormalizedPoint]
    public var size: Double
    public var feather: Double
    public var flow: Double
    public var isEraser: Bool

    /// Apple Pencil force at each point, normalised to 0…1 against the
    /// Pencil's maximum, and **empty for a finger** — a finger reports a
    /// constant force that means nothing, so a stroke with no pressures is
    /// drawn at its nominal size from end to end.
    ///
    /// Additive and defaulted, so a recipe written before pressure existed
    /// decodes unchanged.
    public var pressures: [Double] = []

    private enum CodingKeys: String, CodingKey {
        case points, size, feather, flow, isEraser, pressures
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        points = try container.decode([NormalizedPoint].self, forKey: .points)
        size = try container.decode(Double.self, forKey: .size)
        feather = try container.decode(Double.self, forKey: .feather)
        flow = try container.decode(Double.self, forKey: .flow)
        isEraser = try container.decode(Bool.self, forKey: .isEraser)
        pressures = try container.decodeIfPresent([Double].self, forKey: .pressures) ?? []
    }

    /// How much a pressure reading may scale the nominal width. A Pencil at
    /// rest still marks, and a hard press does not double the brush — the
    /// range is the one Procreate and Notes both feel like.
    public static let pressureWidthRange: ClosedRange<Double> = 0.45...1.25

    /// Width multiplier for a normalised force.
    public static func widthScale(forPressure pressure: Double) -> Double {
        let clamped = min(max(pressure, 0), 1)
        let range = pressureWidthRange
        return range.lowerBound + (range.upperBound - range.lowerBound) * clamped
    }
}

public struct PhotoMaskComponent: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var kind: PhotoMaskComponentKind
    public var operation: MaskBlendOperation = .add
    public var opacity = 1.0

    public var brushStrokes: [BrushStroke] = []
    public var startPoint = NormalizedPoint(x: 0.5, y: 0.2)
    public var endPoint = NormalizedPoint(x: 0.5, y: 0.8)
    public var center = NormalizedPoint.center
    public var radiusX = 0.3
    public var radiusY = 0.3
    public var feather = 0.5
    public var subjectPoint = NormalizedPoint.center
    public var luminanceMinimum = 0.25
    public var luminanceMaximum = 0.75
    public var sampledRed = 0.5
    public var sampledGreen = 0.5
    public var sampledBlue = 0.5
    public var colorTolerance = 0.2

    public init(kind: PhotoMaskComponentKind, operation: MaskBlendOperation = .add) {
        self.kind = kind
        self.operation = operation
    }
}

public struct PhotoMask: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var isVisible = true
    public var isInverted = false
    public var components: [PhotoMaskComponent]
    public var adjustments = PhotoAdjustments.zero

    public init(name: String, component: PhotoMaskComponent) {
        self.name = name
        self.components = [component]
    }
}

public struct PhotoEditRecipe: Codable, Equatable, Sendable {
    public static let formatIdentifier = "com.hoangtuan.shotdex.photo-edit"
    public static let formatVersion = "1.0"

    public var source: PhotoEditSource = .automatic
    public var sourceFilename: String?
    /// Save Copy keeps rendering from the original asset's immutable PhotoKit
    /// resource so RAW controls can be recalled exactly on the rendered copy.
    /// Local identifiers are intentionally device-local; no separate iCloud
    /// recipe/source synchronization is attempted.
    public var sourceAssetIdentifier: String?
    public var adjustments = PhotoAdjustments.zero
    public var filter: PhotoFilter = .original
    /// How much of the chosen filter is mixed over the unfiltered image. Only
    /// meaningful when `filter != .original`.
    public var filterIntensity = 1.0
    public var crop = PhotoCropRecipe.identity
    public var masks: [PhotoMask] = []
    public var color = PhotoColorRecipe.identity
    /// Point tone curve (RGB master + per-channel). Applied right after Color in
    /// the render chain. Identity (straight line) adds no key to the JSON.
    public var curve = ToneCurveAdjustments.identity
    /// Text and signature layers drawn on top of the finished photo, back to
    /// front. Composited last of everything, so nothing in the tone or colour
    /// pipeline can tint them and the downscale cannot soften them.
    public var overlays: [PhotoOverlay] = []
    /// Freehand Markup drawing, composited just under the overlays (so a caption
    /// stays legible over a scribble). `nil` when nothing is drawn.
    public var drawing: PhotoDrawing?

    public static let identity = PhotoEditRecipe()

    /// Whether this recipe needs a full-extent bitmap layer of its own to
    /// render — a mask, a drawing or an overlay.
    ///
    /// Each of those rasterizes into a `CGContext` the size of the whole
    /// image: at 48MP that is ~195MB of RGBA for **one** layer, before the
    /// source decode. An app doing that is close to the edge; an app
    /// *extension*, whose ceiling is a fraction of an app's, is over it.
    /// `ShotDexEdit` checks this before offering to continue an edit.
    /// Counts only layers that would actually be drawn: a hidden mask or an
    /// overlay with nothing visible in it costs the renderer nothing, and
    /// declining those would lose the user a continuable edit for no reason.
    public var needsFullExtentLayers: Bool {
        masks.contains(where: \.isVisible)
            || overlays.contains(where: \.hasVisibleEffect)
            || (drawing?.hasVisibleEffect ?? false)
    }

    public var isIdentity: Bool {
        adjustments.isIdentity
            && filter == .original
            && crop == .identity
            && masks.isEmpty
            && color.isIdentity
            && curve.isIdentity
            && overlays.isEmpty
            && (drawing?.isEmpty ?? true)
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
        case curve
        case overlays
        case drawing
    }

    public init() {}

    /// Recipes written by an earlier build lack the newer keys, so every field is
    /// optional on the wire and falls back to its identity value.
    public init(from decoder: any Decoder) throws {
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
        curve = try container.decodeIfPresent(
            ToneCurveAdjustments.self,
            forKey: .curve
        ) ?? .identity
        overlays = try container.decodeIfPresent([PhotoOverlay].self, forKey: .overlays) ?? []
        drawing = try container.decodeIfPresent(PhotoDrawing.self, forKey: .drawing)
    }

    /// Written by hand so an untouched Color tab adds no key at all — a recipe
    /// saved without those edits stays byte-compatible with earlier builds.
    public func encode(to encoder: any Encoder) throws {
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
        if !curve.isIdentity { try container.encode(curve, forKey: .curve) }
        if !overlays.isEmpty { try container.encode(overlays, forKey: .overlays) }
        if let drawing, !drawing.isEmpty { try container.encode(drawing, forKey: .drawing) }
    }
}

public struct PhotoExportOptions: Codable, Equatable, Sendable {
    public init(
        format: PhotoOutputFormat,
        quality: Double,
        preset: ResizePreset,
        includeMetadata: Bool,
        cropAnchor: NormalizedPoint,
    ) {
        self.format = format
        self.quality = quality
        self.preset = preset
        self.includeMetadata = includeMetadata
        self.cropAnchor = cropAnchor
    }

    public var format: PhotoOutputFormat
    public var quality: Double
    public var preset: ResizePreset
    public var includeMetadata: Bool
    public var cropAnchor: NormalizedPoint

    public static let compressDefault = PhotoExportOptions(
        format: .preserve,
        quality: 0.8,
        preset: .original,
        includeMetadata: true,
        cropAnchor: .center
    )
}

public enum PhotoEditingError: LocalizedError, Sendable {
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

    public var errorDescription: String? {
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
