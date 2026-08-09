import CoreGraphics
import CoreText
import Foundation

/// Resolved faces, keyed by the name pair the recipe stores.
///
/// Same shape and the same reasoning as `FilmLookTableCache`: the layout functions
/// are `static` so the renderer, the canvas proxy and the tests can all reach them,
/// which means no actor isolation to lean on. Tiny capacity — a photo has one or two
/// typefaces on it.
private final class TextOverlayFontCache: @unchecked Sendable {
    static let shared = TextOverlayFontCache()
    /// Faces are cached at one size and resized on use; `CTFontCreateCopyWithAttributes`
    /// is cheap, a descriptor match is not.
    static let referenceSize: CGFloat = 100

    private static let capacity = 8
    private let lock = NSLock()
    private var fonts: [String: TextOverlayLayout.ResolvedFont] = [:]
    private var order: [String] = []

    func font(for key: String) -> TextOverlayLayout.ResolvedFont? {
        lock.lock()
        defer { lock.unlock() }
        return fonts[key]
    }

    func store(_ font: TextOverlayLayout.ResolvedFont, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        guard fonts[key] == nil else { return }
        fonts[key] = font
        order.append(key)
        while order.count > Self.capacity {
            fonts.removeValue(forKey: order.removeFirst())
        }
    }
}

/// Laid-out text sizes, keyed by everything that changes them.
///
/// Dragging a caption changes only its position, so without this every frame builds
/// a `CTFramesetter` two or three times over — once for the selection box, once for
/// the proxy, once for the panel — to arrive at the same number.
private final class TextOverlayMeasurementCache: @unchecked Sendable {
    static let shared = TextOverlayMeasurementCache()

    private static let capacity = 16
    private let lock = NSLock()
    private var sizes: [String: CGSize] = [:]
    private var order: [String] = []

    func size(for key: String) -> CGSize? {
        lock.lock()
        defer { lock.unlock() }
        return sizes[key]
    }

    func store(_ size: CGSize, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        if sizes[key] == nil { order.append(key) }
        sizes[key] = size
        while order.count > Self.capacity {
            sizes.removeValue(forKey: order.removeFirst())
        }
    }
}

/// Everything about laying out and drawing an overlay layer that does not need a
/// UI framework.
///
/// Core Text rather than UIKit's attributed-string additions on purpose: this is
/// the single source of truth for the *geometry* of a layer, and it is used from
/// three places — the render actor that bakes the pixels, the on-canvas proxy the
/// user drags, and the tests — so it cannot live behind `UIKit`.
enum TextOverlayLayout {
    /// A face that could not be found is a real possibility: recipes live inside
    /// users' photos, and the font that was installed when the edit was saved may
    /// be gone on the next device. `didSubstitute` exists so the UI can say so
    /// rather than silently reflowing the caption.
    struct ResolvedFont {
        var font: CTFont
        var didSubstitute: Bool
    }

    /// Point size from the layer's normalized size. Against the short edge, so a
    /// caption keeps its apparent size when the same recipe renders at a 768px
    /// interactive preview and at full export resolution.
    static func pointSize(for size: Double, shortEdge: CGFloat) -> CGFloat {
        max(1, CGFloat(size) * shortEdge)
    }

    /// Width of the text box in pixels. Against the *width* rather than the short
    /// edge: a wrap limit is about how far across the frame a line may run.
    static func maximumWidth(for overlay: PhotoOverlay, extent: CGRect) -> CGFloat {
        max(1, extent.width * CGFloat(min(max(overlay.maximumWidth, 0.05), 1)))
    }

    // MARK: Font

    static func resolvedFont(for overlay: PhotoOverlay, pointSize: CGFloat) -> ResolvedFont {
        let base = baseFont(for: overlay, pointSize: pointSize)
        return ResolvedFont(
            font: applyTraits(to: base.font, overlay: overlay, pointSize: pointSize),
            didSubstitute: base.didSubstitute
        )
    }

    /// Font lookup is cached because this runs on every frame of a drag — from the
    /// panel, from the selection box and from the live proxy — and resolving a face
    /// by name means a font-descriptor match, which is tens of milliseconds when it
    /// has to search. The cache holds one font per face at a reference size and
    /// resizes copies, which is cheap.
    private static func baseFont(
        for overlay: PhotoOverlay,
        pointSize: CGFloat
    ) -> ResolvedFont {
        let key = "\(overlay.fontPostScriptName)|\(overlay.fontFamilyName)"
        if let cached = TextOverlayFontCache.shared.font(for: key) {
            return ResolvedFont(
                font: CTFontCreateCopyWithAttributes(cached.font, pointSize, nil, nil),
                didSubstitute: cached.didSubstitute
            )
        }
        let resolved = lookUpBaseFont(
            for: overlay,
            pointSize: TextOverlayFontCache.referenceSize
        )
        TextOverlayFontCache.shared.store(resolved, for: key)
        return ResolvedFont(
            font: CTFontCreateCopyWithAttributes(resolved.font, pointSize, nil, nil),
            didSubstitute: resolved.didSubstitute
        )
    }

    private static func lookUpBaseFont(
        for overlay: PhotoOverlay,
        pointSize: CGFloat
    ) -> ResolvedFont {
        guard !overlay.fontPostScriptName.isEmpty else {
            return ResolvedFont(font: systemFont(pointSize: pointSize), didSubstitute: false)
        }
        // `CTFontCreateWithName` never fails — it quietly hands back Helvetica for
        // a name it does not know — so the only way to detect a missing face is to
        // ask the result what it is called.
        let requested = CTFontCreateWithName(
            overlay.fontPostScriptName as CFString,
            pointSize,
            nil
        )
        let actual = CTFontCopyPostScriptName(requested) as String
        if actual.caseInsensitiveCompare(overlay.fontPostScriptName) == .orderedSame {
            return ResolvedFont(font: requested, didSubstitute: false)
        }
        if !overlay.fontFamilyName.isEmpty,
           let family = font(inFamily: overlay.fontFamilyName, pointSize: pointSize) {
            // The exact face is gone but its family is here: staying inside the
            // family is a far smaller change than dropping to the system font.
            return ResolvedFont(font: family, didSubstitute: true)
        }
        return ResolvedFont(font: systemFont(pointSize: pointSize), didSubstitute: true)
    }

    private static func font(inFamily family: String, pointSize: CGFloat) -> CTFont? {
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: family as CFString,
        ] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, pointSize, nil)
        let resolved = CTFontCopyFamilyName(font) as String
        guard resolved.caseInsensitiveCompare(family) == .orderedSame else { return nil }
        return font
    }

    private static func systemFont(pointSize: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.system, pointSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, pointSize, nil)
    }

    /// Bold and italic are requested as symbolic traits so a family that ships a
    /// real bold face gets it. A family with no such face keeps the base font —
    /// deliberately no synthetic slant, which would make the bake and the
    /// on-canvas proxy disagree.
    private static func applyTraits(
        to font: CTFont,
        overlay: PhotoOverlay,
        pointSize: CGFloat
    ) -> CTFont {
        var traits: CTFontSymbolicTraits = []
        if overlay.isBold { traits.insert(.traitBold) }
        if overlay.isItalic { traits.insert(.traitItalic) }
        guard !traits.isEmpty else { return font }
        let mask: CTFontSymbolicTraits = [.traitBold, .traitItalic]
        return CTFontCreateCopyWithSymbolicTraits(font, pointSize, nil, traits, mask) ?? font
    }

    // MARK: Attributed string

    static func attributedString(
        for overlay: PhotoOverlay,
        resolvedText: String,
        pointSize: CGFloat
    ) -> NSAttributedString {
        let font = resolvedFont(for: overlay, pointSize: pointSize).font
        var attributes: [NSAttributedString.Key: Any] = [
            key(kCTFontAttributeName): font,
            key(kCTForegroundColorAttributeName): cgColor(overlay.fill),
            key(kCTParagraphStyleAttributeName): paragraphStyle(
                for: overlay,
                pointSize: pointSize
            ),
        ]
        if overlay.tracking != 0 {
            attributes[key(kCTKernAttributeName)] = CGFloat(overlay.tracking) * pointSize
        }
        if overlay.hasOutline {
            // Core Text takes stroke width as a percentage of the point size, and
            // a *negative* width means "stroke and fill" — a positive one would
            // give hollow letters, which is not what an outline control means here.
            attributes[key(kCTStrokeWidthAttributeName)] = -CGFloat(overlay.outlineWidth) * 100
            attributes[key(kCTStrokeColorAttributeName)] = cgColor(overlay.outlineColor)
        }
        return NSAttributedString(string: resolvedText, attributes: attributes)
    }

    /// Core Text hands out its attribute names as `CFString`, which does not bridge
    /// straight to `NSAttributedString.Key`.
    private static func key(_ name: CFString) -> NSAttributedString.Key {
        NSAttributedString.Key(name as String)
    }

    private static func paragraphStyle(
        for overlay: PhotoOverlay,
        pointSize: CGFloat
    ) -> CTParagraphStyle {
        let alignment = ctAlignment(overlay.alignment)
        let spacing = CGFloat(overlay.lineSpacing) * pointSize
        // The pointers a `CTParagraphStyleSetting` holds have to stay valid until
        // `CTParagraphStyleCreate` has read them, so the array is built and
        // consumed inside the `withUnsafePointer` bodies rather than escaping them.
        return withUnsafePointer(to: alignment) { alignmentPointer in
            withUnsafePointer(to: spacing) { spacingPointer in
                let settings = [
                    CTParagraphStyleSetting(
                        spec: .alignment,
                        valueSize: MemoryLayout<CTTextAlignment>.size,
                        value: alignmentPointer
                    ),
                    CTParagraphStyleSetting(
                        spec: .lineSpacingAdjustment,
                        valueSize: MemoryLayout<CGFloat>.size,
                        value: spacingPointer
                    ),
                ]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }
    }

    private static func ctAlignment(_ alignment: OverlayTextAlignment) -> CTTextAlignment {
        switch alignment {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
    }

    static func cgColor(_ color: OverlayColor, alpha: Double = 1) -> CGColor {
        CGColor(
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            components: [color.red, color.green, color.blue, alpha]
        ) ?? CGColor(gray: CGFloat(color.red), alpha: CGFloat(alpha))
    }

    // MARK: Measurement

    /// Size of the laid-out text, wrapped to the layer's box width. Rounded up:
    /// Core Text's suggestion can land a fraction short of what it then draws,
    /// which clips the last line.
    /// The one entry point everything measures through: the renderer, the canvas
    /// proxy and the selection box. They have to agree to the pixel, or the dashed
    /// box does not sit around the glyphs and the caption jumps when the bake takes
    /// over from the proxy.
    static func textContentSize(
        for overlay: PhotoOverlay,
        resolvedText: String,
        extent: CGRect,
        shortEdge: CGFloat
    ) -> CGSize {
        contentSize(
            for: overlay,
            resolvedText: resolvedText,
            pointSize: pointSize(for: overlay.size, shortEdge: shortEdge),
            maximumWidth: maximumWidth(for: overlay, extent: extent)
        )
    }

    static func contentSize(
        for overlay: PhotoOverlay,
        resolvedText: String,
        pointSize: CGFloat,
        maximumWidth: CGFloat
    ) -> CGSize {
        guard !resolvedText.isEmpty else { return .zero }
        let key = measurementKey(
            overlay,
            resolvedText: resolvedText,
            pointSize: pointSize,
            maximumWidth: maximumWidth
        )
        if let cached = TextOverlayMeasurementCache.shared.size(for: key) { return cached }
        let size = measure(
            overlay,
            resolvedText: resolvedText,
            pointSize: pointSize,
            maximumWidth: maximumWidth
        )
        TextOverlayMeasurementCache.shared.store(size, for: key)
        return size
    }

    /// Everything that changes the laid-out size, and deliberately nothing that only
    /// changes where it is drawn — position, rotation and opacity are absent, which
    /// is what makes a move drag a cache hit on every frame.
    private static func measurementKey(
        _ overlay: PhotoOverlay,
        resolvedText: String,
        pointSize: CGFloat,
        maximumWidth: CGFloat
    ) -> String {
        [
            resolvedText,
            overlay.fontPostScriptName,
            overlay.fontFamilyName,
            overlay.isBold ? "b" : "-",
            overlay.isItalic ? "i" : "-",
            overlay.alignment.rawValue,
            String(format: "%.2f", pointSize),
            String(format: "%.1f", maximumWidth),
            String(format: "%.4f", overlay.lineSpacing),
            String(format: "%.4f", overlay.tracking),
            String(format: "%.4f", overlay.outlineWidth),
        ].joined(separator: "|")
    }

    private static func measure(
        _ overlay: PhotoOverlay,
        resolvedText: String,
        pointSize: CGFloat,
        maximumWidth: CGFloat
    ) -> CGSize {
        let attributed = attributedString(
            for: overlay,
            resolvedText: resolvedText,
            pointSize: pointSize
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var fitRange = CFRange()
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: maximumWidth, height: .greatestFiniteMagnitude),
            &fitRange
        )
        return CGSize(width: ceil(suggested.width), height: ceil(suggested.height))
    }

    // MARK: Drawing

    /// Draws one layer into a bottom-up (standard Core Graphics) bitmap context.
    ///
    /// `point` maps the layer's normalized anchor into context coordinates,
    /// including the y-flip — the same injected-closure arrangement as
    /// `BrushStrokeRasterizer.draw`, so this file never has to know which way up
    /// the caller's image is.
    static func drawText(
        _ overlay: PhotoOverlay,
        resolvedText: String,
        in context: CGContext,
        extent: CGRect,
        shortEdge: CGFloat,
        point: (NormalizedPoint) -> CGPoint
    ) {
        guard overlay.kind == .text, !resolvedText.isEmpty else { return }
        let pointSize = pointSize(for: overlay.size, shortEdge: shortEdge)
        let size = textContentSize(
            for: overlay,
            resolvedText: resolvedText,
            extent: extent,
            shortEdge: shortEdge
        )
        guard size.width > 0, size.height > 0 else { return }

        let attributed = attributedString(
            for: overlay,
            resolvedText: resolvedText,
            pointSize: pointSize
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: 0),
            path,
            nil
        )

        context.saveGState()
        context.textMatrix = .identity
        context.setAlpha(CGFloat(overlay.opacity))
        context.concatenate(transform(for: overlay, contentSize: size, point: point))
        if overlay.hasShadow {
            // Negative y: the context is bottom-up, and a drop shadow belongs
            // below the glyphs on screen.
            context.setShadow(
                offset: CGSize(width: 0, height: -CGFloat(overlay.shadowOffsetY) * pointSize),
                blur: CGFloat(overlay.shadowRadius) * pointSize,
                color: cgColor(.black, alpha: overlay.shadowOpacity)
            )
        }
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    static func drawImage(
        _ overlay: PhotoOverlay,
        image: CGImage,
        in context: CGContext,
        extent: CGRect,
        shortEdge: CGFloat,
        point: (NormalizedPoint) -> CGPoint
    ) {
        let size = imageContentSize(for: overlay, image: image, shortEdge: shortEdge)
        guard size.width > 0, size.height > 0 else { return }
        context.saveGState()
        context.setAlpha(CGFloat(overlay.opacity))
        context.concatenate(transform(for: overlay, contentSize: size, point: point))
        context.draw(image, in: CGRect(origin: .zero, size: size))
        context.restoreGState()
    }

    /// A signature's width is what the user sets; its height follows the source
    /// image's own aspect ratio so a logo is never squashed.
    static func imageContentSize(
        for overlay: PhotoOverlay,
        image: CGImage,
        shortEdge: CGFloat
    ) -> CGSize {
        guard image.width > 0, image.height > 0 else { return .zero }
        let width = max(1, CGFloat(overlay.size) * shortEdge)
        let aspect = CGFloat(image.width) / CGFloat(image.height)
        return CGSize(width: width, height: max(1, width / aspect))
    }

    /// Places the content box so its centre sits on the layer's anchor, rotated
    /// about that same anchor.
    ///
    /// Rotation is negated because the context is bottom-up: a positive
    /// `rotationDegrees` has to read as clockwise on screen, which is the
    /// direction the on-canvas handle turns.
    static func transform(
        for overlay: PhotoOverlay,
        contentSize: CGSize,
        point: (NormalizedPoint) -> CGPoint
    ) -> CGAffineTransform {
        let anchor = point(overlay.center)
        return CGAffineTransform(translationX: anchor.x, y: anchor.y)
            .rotated(by: -CGFloat(overlay.rotationDegrees) * .pi / 180)
            .translatedBy(x: -contentSize.width / 2, y: -contentSize.height / 2)
    }
}
