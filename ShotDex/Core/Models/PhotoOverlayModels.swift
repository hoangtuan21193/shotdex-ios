import Foundation

/// What an overlay layer draws.
///
/// One kind enum on one struct rather than an enum with two payloads, following
/// `PhotoMaskComponent`: the layer list treats both kinds uniformly, and adding a
/// field to either kind stays a one-line change.
enum PhotoOverlayKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case text
    case image

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text: "Text"
        case .image: "Image"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "textformat"
        case .image: "photo"
        }
    }
}

/// Where each line sits inside the layer's text box.
enum OverlayTextAlignment: String, Codable, CaseIterable, Identifiable, Sendable {
    case leading
    case center
    case trailing

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .leading: "text.alignleft"
        case .center: "text.aligncenter"
        case .trailing: "text.alignright"
        }
    }
}

/// An opaque sRGB colour, 0…1 per channel.
///
/// No alpha channel on purpose: transparency belongs to the layer's own opacity
/// sliders, so a swatch can never carry hidden translucency that makes two
/// identical-looking colours behave differently.
struct OverlayColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    static let white = OverlayColor(red: 1, green: 1, blue: 1)
    static let black = OverlayColor(red: 0, green: 0, blue: 0)

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(white: Double) {
        self.init(red: white, green: white, blue: white)
    }
}

/// One layer drawn on top of the finished photo: a text block or a signature image.
///
/// Geometry follows the same convention as `BrushStroke` — normalized against
/// the image *after* crop, with `size` a fraction of the short
/// edge. That is what makes a layer render identically in the small interactive
/// preview and in a full-resolution export, and what lets a signature saved on a
/// landscape photo keep its apparent size on a portrait one.
struct PhotoOverlay: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var kind: PhotoOverlayKind
    var isVisible = true
    var opacity = 1.0
    /// Anchor point of the layer, and the point it rotates about.
    var center: NormalizedPoint
    var rotationDegrees = 0.0
    /// Text: the font's point size. Image: the layer's width. Both as a fraction
    /// of the cropped image's short edge.
    var size: Double

    // MARK: Text

    /// The literal the user typed, EXIF tokens and all — `{camera}` is resolved at
    /// render time, never stored resolved, so reopening the edit still shows the
    /// template.
    var text = ""
    /// PostScript name of the chosen face; empty means the system font. The family
    /// is kept beside it so a face that is gone on this device can still fall back
    /// within its own family instead of jumping to Helvetica.
    var fontPostScriptName = ""
    var fontFamilyName = ""
    var isBold = false
    var isItalic = false
    var alignment: OverlayTextAlignment = .center
    /// Extra leading, as a multiple of the point size.
    var lineSpacing = 0.15
    /// Letter spacing, as a multiple of the point size.
    var tracking = 0.0
    /// Width of the text box as a fraction of the image width. Lines wrap inside
    /// it, and `alignment` positions them within it, so a long caption cannot run
    /// off the frame.
    var maximumWidth = 0.9
    var fill = OverlayColor.white
    /// Outline thickness as a fraction of the point size. Zero disables it.
    var outlineWidth = 0.0
    var outlineColor = OverlayColor.black
    /// Blur radius as a fraction of the point size.
    var shadowRadius = 0.0
    /// Downward offset as a fraction of the point size.
    var shadowOffsetY = 0.0
    /// Zero disables the shadow regardless of radius and offset.
    var shadowOpacity = 0.0

    // MARK: Image

    /// File in the watermark cache. Nil on a text layer.
    var imageID: UUID?
    /// The photo-library asset the signature was picked from, so a cache file lost
    /// to a reinstall can be fetched again rather than silently dropping the layer.
    var imageAssetIdentifier: String?

    /// Per-kind defaults: a caption belongs across the bottom, a signature in the
    /// bottom-right corner, and a signature needs to be far bigger than a font's
    /// point size to read as a mark.
    init(kind: PhotoOverlayKind) {
        self.kind = kind
        switch kind {
        case .text:
            center = NormalizedPoint(x: 0.5, y: 0.9)
            size = 0.05
        case .image:
            center = NormalizedPoint(x: 0.82, y: 0.88)
            size = 0.25
        }
    }

    static func text() -> PhotoOverlay {
        PhotoOverlay(kind: .text)
    }

    static func image(id: UUID, assetIdentifier: String?) -> PhotoOverlay {
        var overlay = PhotoOverlay(kind: .image)
        overlay.imageID = id
        overlay.imageAssetIdentifier = assetIdentifier
        return overlay
    }

    /// Whether the layer would put any pixels on the photo. An empty string and a
    /// fully transparent layer are both no-ops the renderer can skip.
    var hasVisibleEffect: Bool {
        guard isVisible, opacity > 0.001 else { return false }
        switch kind {
        case .text: return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image: return imageID != nil
        }
    }

    var hasShadow: Bool { shadowOpacity > 0.001 && (shadowRadius > 0 || shadowOffsetY != 0) }

    var hasOutline: Bool { outlineWidth > 0.0005 }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case isVisible
        case opacity
        case center
        case rotationDegrees
        case size
        case text
        case fontPostScriptName
        case fontFamilyName
        case isBold
        case isItalic
        case alignment
        case lineSpacing
        case tracking
        case maximumWidth
        case fill
        case outlineWidth
        case outlineColor
        case shadowRadius
        case shadowOffsetY
        case shadowOpacity
        case imageID
        case imageAssetIdentifier
    }

    /// Hand-written for the same reason as `PhotoEditRecipe`: these recipes live
    /// inside users' photos forever, so a layer written by an older build has to
    /// decode against whatever fields exist today. Every key is optional on the
    /// wire and falls back to the kind's default.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(PhotoOverlayKind.self, forKey: .kind)
        self.init(kind: kind)
        let defaults = self

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? defaults.id
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible)
            ?? defaults.isVisible
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? defaults.opacity
        center = try container.decodeIfPresent(NormalizedPoint.self, forKey: .center)
            ?? defaults.center
        rotationDegrees = try container.decodeIfPresent(Double.self, forKey: .rotationDegrees)
            ?? defaults.rotationDegrees
        size = try container.decodeIfPresent(Double.self, forKey: .size) ?? defaults.size

        text = try container.decodeIfPresent(String.self, forKey: .text) ?? defaults.text
        fontPostScriptName = try container.decodeIfPresent(
            String.self,
            forKey: .fontPostScriptName
        ) ?? defaults.fontPostScriptName
        fontFamilyName = try container.decodeIfPresent(String.self, forKey: .fontFamilyName)
            ?? defaults.fontFamilyName
        isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? defaults.isBold
        isItalic = try container.decodeIfPresent(Bool.self, forKey: .isItalic) ?? defaults.isItalic
        alignment = try container.decodeIfPresent(OverlayTextAlignment.self, forKey: .alignment)
            ?? defaults.alignment
        lineSpacing = try container.decodeIfPresent(Double.self, forKey: .lineSpacing)
            ?? defaults.lineSpacing
        tracking = try container.decodeIfPresent(Double.self, forKey: .tracking)
            ?? defaults.tracking
        maximumWidth = try container.decodeIfPresent(Double.self, forKey: .maximumWidth)
            ?? defaults.maximumWidth
        fill = try container.decodeIfPresent(OverlayColor.self, forKey: .fill) ?? defaults.fill
        outlineWidth = try container.decodeIfPresent(Double.self, forKey: .outlineWidth)
            ?? defaults.outlineWidth
        outlineColor = try container.decodeIfPresent(OverlayColor.self, forKey: .outlineColor)
            ?? defaults.outlineColor
        shadowRadius = try container.decodeIfPresent(Double.self, forKey: .shadowRadius)
            ?? defaults.shadowRadius
        shadowOffsetY = try container.decodeIfPresent(Double.self, forKey: .shadowOffsetY)
            ?? defaults.shadowOffsetY
        shadowOpacity = try container.decodeIfPresent(Double.self, forKey: .shadowOpacity)
            ?? defaults.shadowOpacity

        imageID = try container.decodeIfPresent(UUID.self, forKey: .imageID)
        imageAssetIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .imageAssetIdentifier
        )
    }

    /// Only what differs from the kind's default is written — a plain white
    /// caption is a handful of keys rather than two dozen, and the recipe has to
    /// fit in a photo's adjustment data alongside everything else.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let defaults = PhotoOverlay(kind: kind)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        if isVisible != defaults.isVisible {
            try container.encode(isVisible, forKey: .isVisible)
        }
        if opacity != defaults.opacity { try container.encode(opacity, forKey: .opacity) }
        if center != defaults.center { try container.encode(center, forKey: .center) }
        if rotationDegrees != defaults.rotationDegrees {
            try container.encode(rotationDegrees, forKey: .rotationDegrees)
        }
        if size != defaults.size { try container.encode(size, forKey: .size) }

        if text != defaults.text { try container.encode(text, forKey: .text) }
        if fontPostScriptName != defaults.fontPostScriptName {
            try container.encode(fontPostScriptName, forKey: .fontPostScriptName)
        }
        if fontFamilyName != defaults.fontFamilyName {
            try container.encode(fontFamilyName, forKey: .fontFamilyName)
        }
        if isBold != defaults.isBold { try container.encode(isBold, forKey: .isBold) }
        if isItalic != defaults.isItalic { try container.encode(isItalic, forKey: .isItalic) }
        if alignment != defaults.alignment { try container.encode(alignment, forKey: .alignment) }
        if lineSpacing != defaults.lineSpacing {
            try container.encode(lineSpacing, forKey: .lineSpacing)
        }
        if tracking != defaults.tracking { try container.encode(tracking, forKey: .tracking) }
        if maximumWidth != defaults.maximumWidth {
            try container.encode(maximumWidth, forKey: .maximumWidth)
        }
        if fill != defaults.fill { try container.encode(fill, forKey: .fill) }
        if outlineWidth != defaults.outlineWidth {
            try container.encode(outlineWidth, forKey: .outlineWidth)
        }
        if outlineColor != defaults.outlineColor {
            try container.encode(outlineColor, forKey: .outlineColor)
        }
        if shadowRadius != defaults.shadowRadius {
            try container.encode(shadowRadius, forKey: .shadowRadius)
        }
        if shadowOffsetY != defaults.shadowOffsetY {
            try container.encode(shadowOffsetY, forKey: .shadowOffsetY)
        }
        if shadowOpacity != defaults.shadowOpacity {
            try container.encode(shadowOpacity, forKey: .shadowOpacity)
        }

        try container.encodeIfPresent(imageID, forKey: .imageID)
        try container.encodeIfPresent(imageAssetIdentifier, forKey: .imageAssetIdentifier)
    }
}

/// A typeface the user picked, as the three strings a layer needs to render it and
/// a picker needs to list it.
///
/// The PostScript name is the identity that goes in the recipe; the family is kept
/// so a face missing on another device can fall back within its own family; the
/// display name is what the picker showed, so the panel can say which font is set
/// without asking the font system again.
struct OverlayFontChoice: Codable, Equatable, Identifiable, Sendable {
    var postScriptName: String
    var familyName: String
    var displayName: String

    var id: String { postScriptName.isEmpty ? "system" : postScriptName }

    static let system = OverlayFontChoice(
        postScriptName: "",
        familyName: "",
        displayName: "System"
    )
}

/// A named, reusable set of overlay layers — the Lightroom "signature" workflow.
///
/// A layer *set* rather than a single layer, because a real watermark is usually a
/// logo plus a credit line, and the two only make sense together.
struct SignaturePreset: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var createdAt: Date
    var layers: [PhotoOverlay]

    init(id: UUID = UUID(), name: String, createdAt: Date, layers: [PhotoOverlay]) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.layers = layers
    }
}
