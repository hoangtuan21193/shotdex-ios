import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import ShotDex

struct TextOverlayLayoutTests {
    private func caption(_ text: String = "Shot on Canon EOS R6") -> PhotoOverlay {
        var overlay = PhotoOverlay.text()
        overlay.text = text
        return overlay
    }

    // MARK: Scale

    /// The whole reason sizes are normalized: the interactive preview and the
    /// full-resolution export have to lay the caption out at proportional sizes,
    /// or what the user positions is not what gets saved.
    @Test func pointSizeScalesWithTheShortEdge() {
        let preview = TextOverlayLayout.pointSize(for: 0.05, shortEdge: 768)
        let export = TextOverlayLayout.pointSize(for: 0.05, shortEdge: 6_000)
        #expect(Self.isClose(preview, 38.4))
        #expect(Self.isClose(export, 300))
        #expect(Self.isClose(export / preview, 6_000 / 768))
    }

    @Test func pointSizeNeverCollapsesToZero() {
        #expect(TextOverlayLayout.pointSize(for: 0, shortEdge: 4_000) == 1)
        #expect(TextOverlayLayout.pointSize(for: 0.05, shortEdge: 0) == 1)
    }

    /// The wrap limit is about how far across the frame a line may run, so it is
    /// measured against the width — and clamped, because a zero-width box would
    /// wrap every glyph onto its own line.
    @Test func maximumWidthIsAFractionOfTheWidthAndClamped() {
        var overlay = caption()
        let extent = CGRect(x: 0, y: 0, width: 4_000, height: 3_000)
        overlay.maximumWidth = 0.5
        #expect(Self.isClose(TextOverlayLayout.maximumWidth(for: overlay, extent: extent), 2_000))
        overlay.maximumWidth = 0
        #expect(Self.isClose(TextOverlayLayout.maximumWidth(for: overlay, extent: extent), 200))
        overlay.maximumWidth = 4
        #expect(Self.isClose(TextOverlayLayout.maximumWidth(for: overlay, extent: extent), 4_000))
    }

    // MARK: Fonts

    @Test func anEmptyFontNameResolvesToTheSystemFontWithoutSubstituting() {
        let resolved = TextOverlayLayout.resolvedFont(for: caption(), pointSize: 40)
        #expect(!resolved.didSubstitute)
        #expect(CTFontGetSize(resolved.font) == 40)
    }

    @Test func aKnownFaceResolvesExactly() {
        var overlay = caption()
        overlay.fontPostScriptName = "Helvetica"
        overlay.fontFamilyName = "Helvetica"
        let resolved = TextOverlayLayout.resolvedFont(for: overlay, pointSize: 40)
        #expect(!resolved.didSubstitute)
        #expect(CTFontCopyPostScriptName(resolved.font) as String == "Helvetica")
    }

    /// `CTFontCreateWithName` hands back Helvetica for a name it does not know, so
    /// a missing face has to be detected rather than trusted — otherwise a recipe
    /// saved with a font this device lacks reflows with no warning.
    @Test func aMissingFaceFallsBackWithinItsFamily() {
        var overlay = caption()
        overlay.fontPostScriptName = "Helvetica-NotARealFace"
        overlay.fontFamilyName = "Courier"
        let resolved = TextOverlayLayout.resolvedFont(for: overlay, pointSize: 40)
        #expect(resolved.didSubstitute)
        #expect(CTFontCopyFamilyName(resolved.font) as String == "Courier")
    }

    @Test func aMissingFaceAndFamilyFallsBackToTheSystemFont() {
        var overlay = caption()
        overlay.fontPostScriptName = "NoSuchFace"
        overlay.fontFamilyName = "No Such Family"
        let resolved = TextOverlayLayout.resolvedFont(for: overlay, pointSize: 40)
        #expect(resolved.didSubstitute)
        let system = CTFontCreateUIFontForLanguage(.system, 40, nil)!
        #expect(
            CTFontCopyFamilyName(resolved.font) as String
                == CTFontCopyFamilyName(system) as String
        )
    }

    @Test func boldIsRequestedAsARealFaceNotASyntheticOne() {
        var overlay = caption()
        overlay.isBold = true
        let resolved = TextOverlayLayout.resolvedFont(for: overlay, pointSize: 40)
        #expect(CTFontGetSymbolicTraits(resolved.font).contains(.traitBold))
    }

    // MARK: Measurement

    @Test func emptyTextMeasuresToNothing() {
        let size = TextOverlayLayout.contentSize(
            for: caption(""),
            resolvedText: "",
            pointSize: 40,
            maximumWidth: 1_000
        )
        #expect(size == .zero)
    }

    @Test func measurementScalesWithPointSize() {
        let overlay = caption()
        let small = TextOverlayLayout.contentSize(
            for: overlay,
            resolvedText: overlay.text,
            pointSize: 20,
            maximumWidth: 10_000
        )
        let large = TextOverlayLayout.contentSize(
            for: overlay,
            resolvedText: overlay.text,
            pointSize: 80,
            maximumWidth: 10_000
        )
        #expect(large.width > small.width * 3)
        #expect(large.height > small.height * 3)
    }

    /// A caption longer than its box has to wrap rather than run off the frame.
    @Test func aNarrowBoxWrapsIntoMoreLines() {
        let overlay = caption("Shot on a Canon EOS R6 with an RF 85mm F1.2 L USM lens")
        let wide = TextOverlayLayout.contentSize(
            for: overlay,
            resolvedText: overlay.text,
            pointSize: 40,
            maximumWidth: 10_000
        )
        let narrow = TextOverlayLayout.contentSize(
            for: overlay,
            resolvedText: overlay.text,
            pointSize: 40,
            maximumWidth: 400
        )
        #expect(narrow.width <= 400)
        #expect(narrow.height > wide.height)
    }

    @Test func aSignatureKeepsItsSourceAspectRatio() {
        let image = Self.solidImage(width: 400, height: 100)
        var overlay = PhotoOverlay(kind: .image)
        overlay.size = 0.5
        let size = TextOverlayLayout.imageContentSize(
            for: overlay,
            image: image,
            shortEdge: 1_000
        )
        #expect(size.width == 500)
        #expect(size.height == 125)
    }

    // MARK: Transform

    /// The content box is centred on the anchor and rotates about it, so turning a
    /// layer never slides it away from where the user put it.
    @Test func theContentCentreLandsOnTheAnchorAtEveryRotation() {
        let extent = CGRect(x: 0, y: 0, width: 800, height: 600)
        let contentSize = CGSize(width: 200, height: 60)
        let point = Self.pointMapper(extent: extent)

        for degrees in [0.0, 17.0, -33.0, 90.0, 180.0] {
            var overlay = caption()
            overlay.center = NormalizedPoint(x: 0.3, y: 0.8)
            overlay.rotationDegrees = degrees
            let transform = TextOverlayLayout.transform(
                for: overlay,
                contentSize: contentSize,
                point: point
            )
            let mapped = CGPoint(x: contentSize.width / 2, y: contentSize.height / 2)
                .applying(transform)
            let anchor = point(overlay.center)
            #expect(abs(mapped.x - anchor.x) < 0.001)
            #expect(abs(mapped.y - anchor.y) < 0.001)
        }
    }

    /// A positive rotation has to read as clockwise on screen, matching the way the
    /// on-canvas handle turns. In a bottom-up context that is a negative angle.
    @Test func aPositiveRotationReadsAsClockwise() {
        let extent = CGRect(x: 0, y: 0, width: 800, height: 600)
        var overlay = caption()
        overlay.center = .center
        overlay.rotationDegrees = 90
        let transform = TextOverlayLayout.transform(
            for: overlay,
            contentSize: CGSize(width: 200, height: 60),
            point: Self.pointMapper(extent: extent)
        )
        // The box's right edge, at 90° clockwise on screen, points downward — which
        // in the bottom-up context means a smaller y than the anchor.
        let rightEdge = CGPoint(x: 200, y: 30).applying(transform)
        #expect(rightEdge.y < 300)
    }

    // MARK: Drawing

    /// End-to-end check of the y-flip: a layer anchored near the top of the photo
    /// must put its ink in the top rows of the bitmap, not the bottom ones.
    @Test func textLandsOnTheSideOfTheFrameItIsAnchoredTo() throws {
        let top = try Self.inkCentroidRow(normalizedY: 0.15)
        let bottom = try Self.inkCentroidRow(normalizedY: 0.85)
        #expect(top < bottom)
        #expect(top < 0.4)
        #expect(bottom > 0.6)
    }

    @Test func anEmptyLayerDrawsNothing() throws {
        let ink = try Self.render { context, extent in
            TextOverlayLayout.drawText(
                caption(""),
                resolvedText: "",
                in: context,
                extent: extent,
                shortEdge: min(extent.width, extent.height),
                point: Self.pointMapper(extent: extent)
            )
        }
        #expect(ink.allSatisfy { $0 == 0 })
    }

    // MARK: Helpers

    /// Normalized sizes are fractions of a pixel dimension, so every expected
    /// value here is the product of two inexact binary doubles.
    private static func isClose(_ value: CGFloat, _ expected: CGFloat) -> Bool {
        abs(value - expected) < 0.0001
    }

    /// Mirrors `PhotoRenderService.imagePoint`: normalized y is measured downward
    /// from the top, Core Graphics measures it upward from the bottom.
    private static func pointMapper(extent: CGRect) -> (NormalizedPoint) -> CGPoint {
        { point in
            CGPoint(
                x: extent.minX + extent.width * point.x,
                y: extent.minY + extent.height * (1 - point.y)
            )
        }
    }

    private static let renderSize = 240

    /// Alpha channel of a freshly rendered bitmap, row-major from the top row.
    private static func render(
        _ draw: (CGContext, CGRect) -> Void
    ) throws -> [UInt8] {
        let size = renderSize
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let extent = CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size))
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(
                CGContext(
                    data: buffer.baseAddress,
                    width: size,
                    height: size,
                    bitsPerComponent: 8,
                    bytesPerRow: size * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            )
            draw(context, extent)
        }
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }

    /// Where the ink sits vertically, as a fraction of the frame from the top.
    private static func inkCentroidRow(normalizedY: Double) throws -> Double {
        var overlay = PhotoOverlay.text()
        overlay.text = "SHOTDEX"
        overlay.size = 0.1
        overlay.center = NormalizedPoint(x: 0.5, y: normalizedY)

        let alpha = try render { context, extent in
            TextOverlayLayout.drawText(
                overlay,
                resolvedText: overlay.text,
                in: context,
                extent: extent,
                shortEdge: min(extent.width, extent.height),
                point: pointMapper(extent: extent)
            )
        }

        var weighted = 0.0
        var total = 0.0
        for (index, value) in alpha.enumerated() where value > 0 {
            weighted += Double(index / renderSize) * Double(value)
            total += Double(value)
        }
        #expect(total > 0)
        return weighted / total / Double(renderSize)
    }

    private static func solidImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}
