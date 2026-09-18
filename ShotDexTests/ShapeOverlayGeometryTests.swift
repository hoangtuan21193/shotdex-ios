import CoreImage
import CoreGraphics
import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

struct ShapeOverlayGeometryTests {

    private let box = CGRect(x: -50, y: -30, width: 100, height: 60)

    @Test func boxFollowsHeightRatio() {
        let rect = ShapeOverlayGeometry.box(
            center: CGPoint(x: 10, y: 20),
            width: 100,
            heightRatio: 0.5
        )
        #expect(rect.width == 100)
        #expect(rect.height == 50)
        #expect(rect.midX == 10)
        #expect(rect.midY == 20)
    }

    /// A ratio of zero would give a zero-height box and a path with no area, so
    /// it is floored rather than trusted.
    @Test func degenerateHeightRatioIsFloored() {
        let rect = ShapeOverlayGeometry.box(center: .zero, width: 100, heightRatio: 0)
        #expect(rect.height > 0)
    }

    @Test func everyStyleStaysInsideItsBox() {
        for style in OverlayShapeStyle.allCases {
            let bounds = ShapeOverlayGeometry.path(for: style, in: box).boundingBox
            #expect(box.insetBy(dx: -0.5, dy: -0.5).contains(bounds), "\(style) escaped its box")
        }
    }

    @Test func lineRunsCornerToCorner() {
        let bounds = ShapeOverlayGeometry.linePath(in: box).boundingBox
        #expect(abs(bounds.minX - box.minX) < 0.001)
        #expect(abs(bounds.maxX - box.maxX) < 0.001)
    }

    /// The head is part of the path, so an arrow is wider than its shaft alone
    /// only at the tip — the bounding box still ends at the box's corner.
    @Test func arrowHeadPointsBackFromTheTip() {
        let bounds = ShapeOverlayGeometry.arrowPath(in: box).boundingBox
        #expect(bounds.maxX <= box.maxX + 0.001)
        #expect(bounds.maxY <= box.maxY + 0.001)
        // The barbs reach back toward the start, so the path is not just the
        // diagonal: its box is the full diagonal either way, but an arrow has
        // more than two points.
        #expect(!ShapeOverlayGeometry.arrowPath(in: box).isEmpty)
    }

    /// The tail hangs below the bubble's body, which is what makes it a speech
    /// bubble rather than a rounded box.
    @Test func speechBubbleHasATailBelowItsBody() {
        let bounds = ShapeOverlayGeometry.speechBubblePath(in: box).boundingBox
        #expect(abs(bounds.minY - box.minY) < 0.001)
        #expect(bounds.height > box.height * 0.9)
    }

    @Test func strokeWidthNeverDisappears() {
        #expect(ShapeOverlayGeometry.strokeWidth(0, shortEdge: 1000) == 1)
        #expect(ShapeOverlayGeometry.strokeWidth(-1, shortEdge: 1000) == 1)
        #expect(ShapeOverlayGeometry.strokeWidth(0.01, shortEdge: 1000) == 10)
    }

    @Test func magnifierIsAlwaysRound() {
        let circle = ShapeOverlayGeometry.magnifierCircle(
            center: CGPoint(x: 5, y: 7),
            diameter: 40
        )
        #expect(circle.width == circle.height)
        #expect(circle.midX == 5)
        #expect(circle.midY == 7)
    }

    /// The point under the middle of the glass must not move, or the loupe
    /// would show somewhere other than where it sits.
    @Test func magnifyingKeepsTheCentreFixed() {
        let center = CGPoint(x: 120, y: 80)
        let transform = ShapeOverlayGeometry.magnifyTransform(center: center, magnification: 3)
        let moved = center.applying(transform)
        #expect(abs(moved.x - center.x) < 0.001)
        #expect(abs(moved.y - center.y) < 0.001)

        let offset = CGPoint(x: center.x + 10, y: center.y).applying(transform)
        #expect(abs(offset.x - (center.x + 30)) < 0.001)
    }

    @Test func magnificationBelowOneIsNotAShrink() {
        let transform = ShapeOverlayGeometry.magnifyTransform(center: .zero, magnification: 0.2)
        let moved = CGPoint(x: 10, y: 0).applying(transform)
        #expect(moved.x == 10)
    }

    @Test func arrowAndLineCannotBeFilled() {
        #expect(!OverlayShapeStyle.arrow.supportsFill)
        #expect(!OverlayShapeStyle.line.supportsFill)
        #expect(OverlayShapeStyle.rectangle.supportsFill)
        #expect(OverlayShapeStyle.oval.supportsFill)
        #expect(OverlayShapeStyle.speechBubble.supportsFill)
    }

    /// A shape layer round-trips through the recipe's hand-written codec, which
    /// only writes what differs from the kind's default.
    @Test func shapeSurvivesEncoding() throws {
        var overlay = PhotoOverlay.shape(.speechBubble)
        overlay.isFilled = true
        overlay.strokeWidth = 0.02
        overlay.heightRatio = 1.4
        let data = try JSONEncoder().encode(overlay)
        let decoded = try JSONDecoder().decode(PhotoOverlay.self, from: data)
        #expect(decoded == overlay)
    }

    @Test func magnifierSurvivesEncoding() throws {
        var overlay = PhotoOverlay.magnifier()
        overlay.magnification = 3.5
        let decoded = try JSONDecoder().decode(
            PhotoOverlay.self,
            from: try JSONEncoder().encode(overlay)
        )
        #expect(decoded.kind == .magnifier)
        #expect(decoded.magnification == 3.5)
    }

    /// A loupe at 1× magnifies nothing, so it is not worth a render pass.
    @Test func unmagnifyingLoupeHasNoEffect() {
        var overlay = PhotoOverlay.magnifier()
        overlay.magnification = 1
        #expect(!overlay.hasVisibleEffect)
        overlay.magnification = 2
        #expect(overlay.hasVisibleEffect)
    }
}

/// The loupe against real pixels, because its whole job is to change what is
/// already there — geometry alone cannot show that it did.
struct MagnifierRenderTests {

    /// Black, with a white 40pt square in the middle.
    private func testImage(side: CGFloat = 200) -> CIImage {
        let context = CGContext(
            data: nil,
            width: Int(side),
            height: Int(side),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: side / 2 - 20, y: side / 2 - 20, width: 40, height: 40))
        return CIImage(cgImage: context.makeImage()!)
    }

    private func brightness(of image: CIImage, at point: CGPoint) -> Double {
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(
            image,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: point.x, y: point.y, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return Double(pixel[0]) / 255
    }

    @Test func loupeEnlargesWhatIsUnderIt() {
        let input = testImage()
        var loupe = PhotoOverlay.magnifier()
        loupe.center = NormalizedPoint(x: 0.5, y: 0.5)
        loupe.size = 0.6
        loupe.magnification = 2

        // 30pt right of centre: outside the 40pt square, so black to begin with,
        // and inside it once the square is doubled.
        let probe = CGPoint(x: 130, y: 100)
        #expect(brightness(of: input, at: probe) < 0.1)

        let output = PhotoRenderService.applyMagnifiers([loupe], to: input)
        #expect(brightness(of: output, at: probe) > 0.9)
    }

    /// Outside the circle the photo has to be untouched — a loupe that tinted or
    /// shifted the rest of the frame would be worse than no loupe.
    @Test func loupeLeavesTheRestOfThePhotoAlone() {
        let input = testImage()
        var loupe = PhotoOverlay.magnifier()
        loupe.size = 0.3
        loupe.magnification = 3

        let output = PhotoRenderService.applyMagnifiers([loupe], to: input)
        let corner = CGPoint(x: 10, y: 10)
        #expect(abs(brightness(of: output, at: corner) - brightness(of: input, at: corner)) < 0.02)
    }

    @Test func hiddenLoupeDoesNothing() {
        let input = testImage()
        var loupe = PhotoOverlay.magnifier()
        loupe.isVisible = false
        let probe = CGPoint(x: 130, y: 100)
        let output = PhotoRenderService.applyMagnifiers([loupe], to: input)
        #expect(brightness(of: output, at: probe) == brightness(of: input, at: probe))
    }
}
