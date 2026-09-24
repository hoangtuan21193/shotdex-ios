import ShotDexKit

/// One row of the New Mask sheet.
///
/// Not the same thing as `PhotoMaskComponentKind`: **Background** is a row a
/// photographer looks for by name, but it is not a new kind of mask — it is
/// Subject turned inside out, which `PhotoMask.isInverted` already renders.
/// Keeping the two apart means the renderer learns nothing it did not need
/// to, and the sheet can still offer the words people use.
enum EditorNewMaskOption: String, CaseIterable, Identifiable, Sendable {
    case subject
    case sky
    case background
    case faceSkin
    case eyes
    case lips
    case brush
    case radialGradient
    case linearGradient
    case colorRange
    case luminanceRange
    case depthRange

    var id: String { rawValue }

    /// The component the mask is built from.
    var componentKind: PhotoMaskComponentKind {
        switch self {
        case .subject, .background: .subject
        case .sky: .sky
        case .brush: .brush
        case .radialGradient: .radialGradient
        case .linearGradient: .linearGradient
        case .colorRange: .colorRange
        case .luminanceRange: .luminanceRange
        case .depthRange: .depthRange
        case .faceSkin: .faceSkin
        case .eyes: .eyes
        case .lips: .lips
        }
    }

    /// Whether the new mask starts inverted — the whole of Background.
    var startsInverted: Bool { self == .background }

    var title: String {
        switch self {
        case .background: "Background"
        default: componentKind.displayName
        }
    }

    /// The name on a chip and the start of a new mask's name ("Radial 1"): the
    /// panel's chips are 30pt and the strip shows the name beside four thumbnails.
    var shortTitle: String {
        switch self {
        case .radialGradient: "Radial"
        case .linearGradient: "Linear"
        case .colorRange: "Color"
        case .luminanceRange: "Luminance"
        case .depthRange: "Depth"
        default: title
        }
    }

    /// The phone panel's three chip rows (FS-03.05 §2): what Vision finds, what the
    /// user draws, and what a range of values selects. Every case is in exactly
    /// one row, in `allCases` order.
    enum Row: CaseIterable {
        case detect, draw, range
    }

    var row: Row {
        switch self {
        case .subject, .sky, .background, .faceSkin, .eyes, .lips: .detect
        case .brush, .linearGradient, .radialGradient: .draw
        case .colorRange, .luminanceRange, .depthRange: .range
        }
    }

    static func options(in row: Row) -> [EditorNewMaskOption] {
        allCases.filter { $0.row == row }
    }

    var systemImage: String {
        switch self {
        case .background: "person.and.background.dotted"
        default: componentKind.systemImage
        }
    }

    var description: String {
        switch self {
        case .subject: "Isolates the subject on device"
        case .sky: "Finds the sky automatically"
        case .background: "Everything except the subject"
        case .radialGradient: "Elliptical area, drag to place"
        case .linearGradient: "Straight transition across the frame"
        case .colorRange: "Tap a colour on the photo"
        case .luminanceRange: "Follows a band of brightness"
        case .depthRange: "Follows distance from the camera"
        case .faceSkin: "Skin of every face, not eyes, brows or lips"
        case .eyes: "Both eyes of every face"
        case .lips: "Lips of every face"
        case .brush: "Paint by hand · size, flow, feather"
        }
    }

    /// Why this row is off for the photo in hand, or nil when it can be used.
    /// A row that is greyed out and says why beats a mask that is created and
    /// then turns out to be empty.
    ///
    /// `hasFaces` is nil while the face check is still running; the rows stay
    /// live until it says no, because the check takes a moment and a row that
    /// flickers from grey to live is worse than one that goes grey once.
    func unavailableReason(hasDepth: Bool, hasFaces: Bool? = nil) -> String? {
        switch self {
        case .depthRange where !hasDepth:
            "This photo has no depth map. Portrait mode photos do."
        case .faceSkin, .eyes, .lips:
            hasFaces == false ? "No face found in this photo" : nil
        default:
            nil
        }
    }
}
