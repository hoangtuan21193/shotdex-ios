import ShotDexKit

/// The Transform list's groups, in order (FS-03.13b §3). A group that has
/// nothing to show yet is left out rather than drawn dim; today all four do.
enum EditorTransformSection: String, CaseIterable, Hashable, Sendable {
    case crop, straighten, upright, geometry

    var title: String {
        switch self {
        case .crop: "Crop"
        case .straighten: "Straighten"
        case .upright: "Upright"
        case .geometry: "Geometry"
        }
    }

    var isAvailable: Bool { true }

    static var shown: [EditorTransformSection] { allCases.filter(\.isAvailable) }
}

/// CROP's ratio row: four chips and More…, which holds every other ratio —
/// built from the ratio list, so a ratio added to it lands in More… without
/// anyone listing it twice.
enum EditorCropRatioRow {
    static let chips: [CropAspect] = [.original, .free, .square, .fourFive]

    static var more: [CropAspect] {
        CropAspect.allCases.filter { !chips.contains($0) }
    }
}
