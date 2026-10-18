import CoreImage
import Foundation
import os
import CoreText
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Draws one caption line (FS-12.14 §5): white bold text — with a shadow
/// (Clean), on a dark plate (Box, Word by Word) or with a black outline
/// (Outline) — set so its ink height is the lane's Size of the frame's short
/// edge. The export burns the image in; the preview draws the very same
/// image over the player, scaled — one drawing, so the two cannot drift.
enum VideoCaptionRenderer {
    /// Where the line goes in a frame, in the frame's pixels, top-left origin.
    struct Typeset: Equatable {
        let fontSize: CGFloat
        /// The plate (or, for Clean and Outline, the text's own box).
        let plate: CGRect
        let textHeight: CGFloat
    }

    static func font(size: CGFloat) -> PlatformFont {
        PlatformFont.systemFont(ofSize: size, weight: .bold)
    }

    /// The font size whose ink — the top of an "h" to the bottom of a "g"
    /// — is `textHeight` (what AC-9 measures in the exported pixels).
    static func fontSize(forTextHeight textHeight: CGFloat) -> CGFloat {
        textHeight / inkRatio
    }

    /// Ink height of "hg" per point of font size, read from the glyphs.
    static let inkRatio: CGFloat = {
        let probe = font(size: 100) as CTFont
        var characters: [UniChar] = Array("hg".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        guard CTFontGetGlyphsForCharacters(probe, &characters, &glyphs, characters.count) else { return 0.94 }
        var rects = [CGRect](repeating: .zero, count: glyphs.count)
        CTFontGetBoundingRectsForGlyphs(probe, .horizontal, glyphs, &rects, glyphs.count)
        let top = rects.map(\.maxY).max() ?? 75
        let bottom = rects.map(\.minY).min() ?? -20
        return max(0.5, (top - bottom) / 100)
    }()

    static func typeset(_ text: String, lane: VideoCaptionLane, frame: CGSize) -> Typeset {
        var height = CaptionLayout.textHeight(frame: frame, sizePercent: lane.sizePercent)
        var size = fontSize(forTextHeight: height)
        var width = textWidth(text, size: size)
        let maximum = frame.width * CaptionLayout.maximumLineWidth - 2 * height * CaptionLayout.boxHorizontalPadding
        if width > maximum, width > 0 {
            let scale = maximum / width
            size *= scale
            height *= scale
            width = maximum
        }
        let font = font(size: size)
        let lineHeight = font.capHeight + abs(font.descender)
        let padX = height * CaptionLayout.boxHorizontalPadding
        let padY = height * CaptionLayout.boxVerticalPadding
        let plateSize = CGSize(width: width + 2 * padX, height: lineHeight + 2 * padY)
        let centreY = CaptionLayout.centreY(frame: frame, position: lane.position)
        let plate = CGRect(
            x: (frame.width - plateSize.width) / 2,
            y: centreY - plateSize.height / 2,
            width: plateSize.width,
            height: plateSize.height
        )
        return Typeset(fontSize: size, plate: plate, textHeight: height)
    }

    static func textWidth(_ text: String, size: CGFloat) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font(size: size)]).width)
    }

    /// The line drawn at `scale` × the frame's pixels: an image the size
    /// of the plate, words past `visibleWords` laid out but not drawn.
    static func image(_ text: String, visibleWords: Int = .max, lane: VideoCaptionLane, typeset: Typeset, scale: CGFloat = 1) -> CGImage? {
        let size = CGSize(width: typeset.plate.width * scale, height: typeset.plate.height * scale)
        guard size.width >= 1, size.height >= 1 else { return nil }
        #if canImport(UIKit)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.scaleBy(x: scale, y: scale)
            let bounds = CGRect(origin: .zero, size: typeset.plate.size)
            if lane.style == .box || lane.style == .wordByWord {
                let radius = typeset.textHeight * CaptionLayout.boxCornerRadius
                UIColor.black.withAlphaComponent(CaptionLayout.boxOpacity).setFill()
                UIBezierPath(roundedRect: bounds, cornerRadius: radius).fill()
            }
            let font = font(size: typeset.fontSize)
            let attributed = attributedLine(text, visibleWords: lane.style == .wordByWord ? visibleWords : .max, font: font, lane: lane)
            let lineHeight = font.capHeight + abs(font.descender)
            // Baseline so the ink is centred in the plate: cap height above,
            // the descender below.
            let baseline = (bounds.height - lineHeight) / 2 + font.capHeight
            let origin = CGPoint(x: (bounds.width - attributed.size().width) / 2, y: baseline - font.ascender)
            if lane.style == .clean {
                cg.setShadow(offset: CGSize(width: 0, height: typeset.textHeight * 0.04), blur: typeset.textHeight * 0.18, color: UIColor.black.withAlphaComponent(0.75).cgColor)
            }
            attributed.draw(at: origin)
        }
        return image.cgImage
        #else
        return PlatformDrawing.image(size: size) { cg in
            cg.scaleBy(x: scale, y: scale)
            let bounds = CGRect(origin: .zero, size: typeset.plate.size)
            if lane.style == .box || lane.style == .wordByWord {
                let radius = typeset.textHeight * CaptionLayout.boxCornerRadius
                NSColor.black.withAlphaComponent(CaptionLayout.boxOpacity).setFill()
                NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
            }
            let font = font(size: typeset.fontSize)
            let attributed = attributedLine(text, visibleWords: lane.style == .wordByWord ? visibleWords : .max, font: font, lane: lane)
            let lineHeight = font.capHeight + abs(font.descender)
            // Baseline so the ink is centred in the plate: cap height above,
            // the descender below.
            let baseline = (bounds.height - lineHeight) / 2 + font.capHeight
            let origin = CGPoint(x: (bounds.width - attributed.size().width) / 2, y: baseline - font.ascender)
            if lane.style == .clean {
                cg.setShadow(offset: CGSize(width: 0, height: typeset.textHeight * 0.04), blur: typeset.textHeight * 0.18, color: NSColor.black.withAlphaComponent(0.75).cgColor)
            }
            attributed.draw(at: origin)
        }
        #endif
    }

    private static func attributedLine(_ text: String, visibleWords: Int, font: PlatformFont, lane: VideoCaptionLane) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: PlatformColor.white]
        if lane.style == .outline {
            attributes[.strokeColor] = PlatformColor.black
            attributes[.strokeWidth] = -9.0
        }
        guard visibleWords != .max else { return NSAttributedString(string: text, attributes: attributes) }
        let result = NSMutableAttributedString()
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        for (index, word) in words.enumerated() {
            var wordAttributes = attributes
            if index >= visibleWords { wordAttributes[.foregroundColor] = PlatformColor.clear }
            result.append(NSAttributedString(string: (index == 0 ? "" : " ") + word, attributes: wordAttributes))
        }
        return result
    }
}

/// The compositor's captions: the lane's cues in timeline seconds and its
/// style, drawn over the finished frame — after every overlay and after the
/// frame is cut to the export's shape, so a caption is never cropped
/// (FS-12.14 §6, FS-12.16 §4). Rasterised once per cue, size and word count.
final class VideoCaptionBurner: @unchecked Sendable {
    let lane: VideoCaptionLane
    let cues: [CaptionLayout.Cue]
    private let lock = OSAllocatedUnfairLock<[String: CIImage]>(initialState: [:])

    init?(lane: VideoCaptionLane?, recipe: VideoProjectRecipe) {
        guard let lane, lane.burnsIn else { return nil }
        let cues = CaptionLayout.cues(lane, in: recipe)
        guard !cues.isEmpty else { return nil }
        self.lane = lane
        self.cues = cues
    }

    /// `image` with the caption at `time` drawn on it, in Core Image's
    /// bottom-left space over `frame`.
    func burn(into image: CIImage, frame: CGRect, at time: Double) -> CIImage {
        guard let cue = CaptionLayout.cue(at: time, in: cues) else { return image }
        let words = lane.style == .wordByWord ? CaptionLayout.visibleWordCount(cue, at: time) : Int.max
        let typeset = VideoCaptionRenderer.typeset(cue.text, lane: lane, frame: frame.size)
        let key = "\(cue.id)|\(words)|\(Int(frame.width))x\(Int(frame.height))"
        let layer: CIImage
        if let cached = lock.withLock({ $0[key] }) {
            layer = cached
        } else {
            guard let cg = VideoCaptionRenderer.image(cue.text, visibleWords: words, lane: lane, typeset: typeset) else { return image }
            layer = CIImage(cgImage: cg)
            lock.withLock { cache in
                if cache.count > 24 { cache.removeAll() }
                cache[key] = layer
            }
        }
        // Top-left plate → Core Image's bottom-left origin.
        let x = frame.minX + typeset.plate.minX
        let y = frame.minY + frame.height - typeset.plate.maxY
        return layer.transformed(by: CGAffineTransform(translationX: x, y: y)).composited(over: image)
    }
}
