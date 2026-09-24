import Foundation

/// What an overlay layer draws.
///
/// One kind enum on one struct rather than an enum with two payloads, following
/// `PhotoMaskComponent`: the layer list treats both kinds uniformly, and adding a
/// field to either kind stays a one-line change.
public enum PhotoOverlayKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case text
    case image
    /// A drawn outline — box, oval, speech bubble, arrow or line.
    case shape
    /// A circle that magnifies the photo beneath it, the way Photos' Markup
    /// loupe does. The only overlay whose appearance depends on the picture
    /// under it, which is why the renderer handles it apart from the rest.
    case magnifier
    /// Freehand strokes — one PencilKit drawing per layer, so a scribble is a layer
    /// like any other: it has a place in the stack, can go above a caption, be
    /// hidden, duplicated or deleted on its own (FS-05.01 §4).
    case drawing

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .text: "Text"
        case .image: "Image"
        case .shape: "Shape"
        case .magnifier: "Magnifier"
        case .drawing: "Drawing"
        }
    }

    public var systemImage: String {
        switch self {
        case .text: "textformat"
        case .image: "photo"
        case .shape: "square.on.circle"
        case .magnifier: "plus.magnifyingglass"
        case .drawing: "scribble.variable"
        }
    }
}

/// What a shape layer draws. The set Photos' Markup offers, plus a plain line,
/// which is the one people reach for that Photos makes them fake with an arrow.
public enum OverlayShapeStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case rectangle
    case oval
    case speechBubble
    case arrow
    case line

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .rectangle: "Rectangle"
        case .oval: "Oval"
        case .speechBubble: "Speech Bubble"
        case .arrow: "Arrow"
        case .line: "Line"
        }
    }

    public var systemImage: String {
        switch self {
        case .rectangle: "rectangle"
        case .oval: "oval"
        case .speechBubble: "bubble.left"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        }
    }

    /// An arrow and a line are strokes by definition — filling them would paint
    /// the triangle they are made of, not a thicker arrow.
    public var supportsFill: Bool {
        switch self {
        case .rectangle, .oval, .speechBubble: true
        case .arrow, .line: false
        }
    }
}

/// Where each line sits inside the layer's text box.
public enum OverlayTextAlignment: String, Codable, CaseIterable, Identifiable, Sendable {
    case leading
    case center
    case trailing

    public var id: String { rawValue }

    public var systemImage: String {
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
public struct OverlayColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public static let white = OverlayColor(red: 1, green: 1, blue: 1)
    public static let black = OverlayColor(red: 0, green: 0, blue: 0)

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(white: Double) {
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
public struct PhotoOverlay: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var kind: PhotoOverlayKind
    /// What the user renamed the layer to; empty means "named by its content".
    public var name = ""
    public var isVisible = true
    public var opacity = 1.0
    /// Anchor point of the layer, and the point it rotates about.
    public var center: NormalizedPoint
    public var rotationDegrees = 0.0
    /// Text: the font's point size. Image: the layer's width. Both as a fraction
    /// of the cropped image's short edge.
    public var size: Double

    // MARK: Text

    /// The literal the user typed, EXIF tokens and all — `{camera}` is resolved at
    /// render time, never stored resolved, so reopening the edit still shows the
    /// template.
    public var text = ""
    /// PostScript name of the chosen face; empty means the system font. The family
    /// is kept beside it so a face that is gone on this device can still fall back
    /// within its own family instead of jumping to Helvetica.
    public var fontPostScriptName = ""
    public var fontFamilyName = ""
    public var isBold = false
    public var isItalic = false
    public var alignment: OverlayTextAlignment = .center
    /// Extra leading, as a multiple of the point size.
    public var lineSpacing = 0.15
    /// Letter spacing, as a multiple of the point size.
    public var tracking = 0.0
    /// Width of the text box as a fraction of the image width. Lines wrap inside
    /// it, and `alignment` positions them within it, so a long caption cannot run
    /// off the frame.
    public var maximumWidth = 0.9
    public var fill = OverlayColor.white
    /// Outline thickness as a fraction of the point size. Zero disables it.
    public var outlineWidth = 0.0
    public var outlineColor = OverlayColor.black
    /// Blur radius as a fraction of the point size.
    public var shadowRadius = 0.0
    /// Downward offset as a fraction of the point size.
    public var shadowOffsetY = 0.0
    /// Zero disables the shadow regardless of radius and offset.
    public var shadowOpacity = 0.0

    // MARK: Shape and magnifier

    public var shapeStyle: OverlayShapeStyle = .rectangle
    /// Filled rather than outlined. Ignored by the styles that cannot be filled.
    public var isFilled = false
    /// Outline thickness as a fraction of the cropped image's short edge. The
    /// same unit as `size`, so a shape keeps its proportions when resized.
    public var strokeWidth = 0.006
    /// Height as a fraction of the layer's own width, so one `size` plus this
    /// describes a box of any proportion. A circle is 1.
    public var heightRatio = 0.62
    /// How much bigger the photo appears inside the loupe.
    public var magnification = 2.0

    // MARK: Image

    /// File in the watermark cache. Nil on a text layer.
    public var imageID: UUID?
    /// The photo-library asset the signature was picked from, so a cache file lost
    /// to a reinstall can be fetched again rather than silently dropping the layer.
    public var imageAssetIdentifier: String?

    // MARK: Drawing

    /// The strokes of a drawing layer: PencilKit's vector data plus the canvas it
    /// was drawn on. Covers the whole frame — a drawing layer has no box of its own.
    public var drawing: PhotoDrawing?

    /// Per-kind defaults: a caption belongs across the bottom, a signature in the
    /// bottom-right corner, and a signature needs to be far bigger than a font's
    /// point size to read as a mark.
    public init(kind: PhotoOverlayKind) {
        self.kind = kind
        switch kind {
        case .text:
            center = NormalizedPoint(x: 0.5, y: 0.9)
            size = 0.05
        case .image:
            center = NormalizedPoint(x: 0.82, y: 0.88)
            size = 0.25
        case .shape:
            // Middle of the frame: a shape is drawn to point at something, and
            // the user drags it there straight away.
            center = NormalizedPoint(x: 0.5, y: 0.5)
            size = 0.45
        case .magnifier:
            center = NormalizedPoint(x: 0.5, y: 0.5)
            size = 0.35
        case .drawing:
            center = NormalizedPoint(x: 0.5, y: 0.5)
            size = 1
        }
    }

    public static func drawing(_ drawing: PhotoDrawing?) -> PhotoOverlay {
        var overlay = PhotoOverlay(kind: .drawing)
        overlay.drawing = drawing
        return overlay
    }

    public static func text() -> PhotoOverlay {
        PhotoOverlay(kind: .text)
    }

    public static func shape(_ style: OverlayShapeStyle) -> PhotoOverlay {
        var overlay = PhotoOverlay(kind: .shape)
        overlay.shapeStyle = style
        // An arrow reads as a diagonal, not as a wide flat box.
        if style == .arrow || style == .line {
            overlay.heightRatio = 0.5
        }
        return overlay
    }

    public static func magnifier() -> PhotoOverlay {
        PhotoOverlay(kind: .magnifier)
    }

    public static func image(id: UUID, assetIdentifier: String?) -> PhotoOverlay {
        var overlay = PhotoOverlay(kind: .image)
        overlay.imageID = id
        overlay.imageAssetIdentifier = assetIdentifier
        return overlay
    }

    /// Whether the layer would put any pixels on the photo. An empty string and a
    /// fully transparent layer are both no-ops the renderer can skip.
    public var hasVisibleEffect: Bool {
        guard isVisible, opacity > 0.001 else { return false }
        switch kind {
        case .text: return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image: return imageID != nil
        case .shape: return size > 0.001
        case .magnifier: return size > 0.001 && magnification > 1.001
        case .drawing: return drawing.map { !$0.isEmpty } ?? false
        }
    }

    public var hasShadow: Bool { shadowOpacity > 0.001 && (shadowRadius > 0 || shadowOffsetY != 0) }

    public var hasOutline: Bool { outlineWidth > 0.0005 }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case name
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
        case shapeStyle
        case isFilled
        case strokeWidth
        case heightRatio
        case magnification
        case drawing
    }

    /// Hand-written for the same reason as `PhotoEditRecipe`: these recipes live
    /// inside users' photos forever, so a layer written by an older build has to
    /// decode against whatever fields exist today. Every key is optional on the
    /// wire and falls back to the kind's default.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(PhotoOverlayKind.self, forKey: .kind)
        self.init(kind: kind)
        let defaults = self

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? defaults.id
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
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

        shapeStyle = try container.decodeIfPresent(OverlayShapeStyle.self, forKey: .shapeStyle)
            ?? defaults.shapeStyle
        isFilled = try container.decodeIfPresent(Bool.self, forKey: .isFilled) ?? defaults.isFilled
        strokeWidth = try container.decodeIfPresent(Double.self, forKey: .strokeWidth)
            ?? defaults.strokeWidth
        heightRatio = try container.decodeIfPresent(Double.self, forKey: .heightRatio)
            ?? defaults.heightRatio
        magnification = try container.decodeIfPresent(Double.self, forKey: .magnification)
            ?? defaults.magnification
        drawing = try? container.decodeIfPresent(PhotoDrawing.self, forKey: .drawing)
    }

    /// Only what differs from the kind's default is written — a plain white
    /// caption is a handful of keys rather than two dozen, and the recipe has to
    /// fit in a photo's adjustment data alongside everything else.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let defaults = PhotoOverlay(kind: kind)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        if !name.isEmpty { try container.encode(name, forKey: .name) }
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

        if shapeStyle != defaults.shapeStyle {
            try container.encode(shapeStyle, forKey: .shapeStyle)
        }
        if isFilled != defaults.isFilled { try container.encode(isFilled, forKey: .isFilled) }
        if strokeWidth != defaults.strokeWidth {
            try container.encode(strokeWidth, forKey: .strokeWidth)
        }
        if heightRatio != defaults.heightRatio {
            try container.encode(heightRatio, forKey: .heightRatio)
        }
        if magnification != defaults.magnification {
            try container.encode(magnification, forKey: .magnification)
        }
        if let drawing, !drawing.isEmpty { try container.encode(drawing, forKey: .drawing) }
    }
}

/// A typeface the user picked, as the three strings a layer needs to render it and
/// a picker needs to list it.
///
/// The PostScript name is the identity that goes in the recipe; the family is kept
/// so a face missing on another device can fall back within its own family; the
/// display name is what the picker showed, so the panel can say which font is set
/// without asking the font system again.
public struct OverlayFontChoice: Codable, Equatable, Identifiable, Sendable {
    public init(
        postScriptName: String,
        familyName: String,
        displayName: String,
    ) {
        self.postScriptName = postScriptName
        self.familyName = familyName
        self.displayName = displayName
    }

    public var postScriptName: String
    public var familyName: String
    public var displayName: String

    public var id: String { postScriptName.isEmpty ? "system" : postScriptName }

    public static let system = OverlayFontChoice(
        postScriptName: "",
        familyName: "",
        displayName: "System"
    )
}

/// A named, reusable set of overlay layers — the Lightroom "signature" workflow.
///
/// A layer *set* rather than a single layer, because a real watermark is usually a
/// logo plus a credit line, and the two only make sense together.
public struct SignaturePreset: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var createdAt: Date
    public var layers: [PhotoOverlay]

    public init(id: UUID = UUID(), name: String, createdAt: Date, layers: [PhotoOverlay]) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.layers = layers
    }
}
