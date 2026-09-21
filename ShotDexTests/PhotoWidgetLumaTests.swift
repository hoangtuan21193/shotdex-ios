import CoreGraphics
import Foundation
import Testing
@testable import ShotDex

/// The Smart text colour: measuring the picture, working out which part of it
/// a line of text is standing on, and picking white or black from that. All
/// arithmetic, so none of it needs a widget on a Home Screen to check.
struct PhotoWidgetLumaTests {

    // MARK: The grid

    /// A grid built from an image that is black on the left and white on the
    /// right reads dark on the left and bright on the right — the axes are not
    /// swapped and the rows are not upside down.
    @Test func gridKeepsTheImageOrientation() throws {
        let image = try #require(makeImage(width: 32, height: 32) { context in
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 32))
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 16, y: 0, width: 16, height: 32))
        })
        let grid = try #require(PhotoWidgetLumaGrid.make(from: image))

        let left = grid.luma(inNormalizedRect: CGRect(x: 0, y: 0, width: 0.4, height: 1))
        let right = grid.luma(inNormalizedRect: CGRect(x: 0.6, y: 0, width: 0.4, height: 1))
        #expect(left < 0.1)
        #expect(right > 0.9)
    }

    /// Top and bottom are told apart too, and in the direction the rest of the
    /// code assumes: y = 0 is the top of the picture.
    @Test func gridTopIsTheTopOfThePicture() throws {
        // CoreGraphics draws from the bottom up, so the *second* fill is the
        // one that lands at the top of the image as UIKit sees it.
        let image = try #require(makeImage(width: 32, height: 32) { context in
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 16))
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 16, width: 32, height: 16))
        })
        let grid = try #require(PhotoWidgetLumaGrid.make(from: image))

        let top = grid.luma(inNormalizedRect: CGRect(x: 0, y: 0, width: 1, height: 0.4))
        let bottom = grid.luma(inNormalizedRect: CGRect(x: 0, y: 0.6, width: 1, height: 0.4))
        #expect(top > 0.9)
        #expect(bottom < 0.1)
    }

    /// A rectangle that has been dragged and zoomed off the picture entirely
    /// reads as the whole picture, not as black — a clock does not turn white
    /// because the maths ran out of image.
    @Test func rectangleOffThePictureFallsBackToTheAverage() throws {
        let image = try #require(makeImage(width: 8, height: 8) { context in
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        })
        let grid = try #require(PhotoWidgetLumaGrid.make(from: image))

        let outside = grid.luma(inNormalizedRect: CGRect(x: 3, y: 3, width: 0.2, height: 0.2))
        #expect(outside > 0.9)
    }

    /// A grid can only be built at its own size, so a hand-made one of the
    /// wrong length is refused rather than read out of bounds.
    @Test func gridRefusesTheWrongNumberOfCells() {
        #expect(PhotoWidgetLumaGrid(values: [0.5]) == nil)
        let full = [Double](
            repeating: 0.5, count: PhotoWidgetLumaGrid.side * PhotoWidgetLumaGrid.side
        )
        #expect(PhotoWidgetLumaGrid(values: full) != nil)
    }

    // MARK: Widget space to image space

    /// With the picture the same shape as the widget and no zoom, the widget
    /// *is* the picture: a rectangle in the middle of one is in the middle of
    /// the other.
    @Test func matchingShapeAtOneTimesMapsStraightThrough() {
        let size = CGSize(width: 100, height: 100)
        let rect = PhotoWidgetImageLayer.normalizedImageRect(
            for: CGRect(x: 25, y: 50, width: 50, height: 25),
            in: size,
            aspectRatio: 1,
            scale: 1,
            offsetX: 0,
            offsetY: 0
        )
        #expect(abs(rect.minX - 0.25) < 0.0001)
        #expect(abs(rect.minY - 0.5) < 0.0001)
        #expect(abs(rect.width - 0.5) < 0.0001)
        #expect(abs(rect.height - 0.25) < 0.0001)
    }

    /// A 3:2 picture in a square widget is already cropped left and right
    /// before any zoom, so the widget's own left edge is *inside* the picture.
    @Test func fillCropsTheLongSideBeforeAnyZoom() {
        let rect = PhotoWidgetImageLayer.normalizedImageRect(
            for: CGRect(x: 0, y: 0, width: 100, height: 100),
            in: CGSize(width: 100, height: 100),
            aspectRatio: 1.5,
            scale: 1,
            offsetX: 0,
            offsetY: 0
        )
        // 150pt of picture shown through a 100pt window, centred.
        #expect(abs(rect.minX - (1.0 / 6.0)) < 0.0001)
        #expect(abs(rect.width - (2.0 / 3.0)) < 0.0001)
        #expect(abs(rect.minY - 0) < 0.0001)
        #expect(abs(rect.height - 1) < 0.0001)
    }

    /// Dragging the photo right shows more of its left-hand side, so the part
    /// under the text moves the other way.
    @Test func draggingThePhotoMovesWhatIsUnderTheText() {
        func window(offsetX: Double) -> CGRect {
            PhotoWidgetImageLayer.normalizedImageRect(
                for: CGRect(x: 0, y: 0, width: 100, height: 100),
                in: CGSize(width: 100, height: 100),
                aspectRatio: 1.5,
                scale: 1,
                offsetX: offsetX,
                offsetY: 0
            )
        }
        #expect(window(offsetX: 1).minX < window(offsetX: 0).minX)
        #expect(window(offsetX: -1).minX > window(offsetX: 0).minX)
        // At the stop, the window sits flush with the picture's own edge.
        #expect(abs(window(offsetX: 1).minX) < 0.0001)
    }

    /// Zooming in narrows the part of the picture the widget shows.
    @Test func zoomingNarrowsTheWindow() {
        func window(scale: Double) -> CGRect {
            PhotoWidgetImageLayer.normalizedImageRect(
                for: CGRect(x: 0, y: 0, width: 100, height: 100),
                in: CGSize(width: 100, height: 100),
                aspectRatio: 1,
                scale: scale,
                offsetX: 0,
                offsetY: 0
            )
        }
        #expect(abs(window(scale: 2).width - 0.5) < 0.0001)
        #expect(window(scale: 2).width < window(scale: 1).width)
    }

    // MARK: Picking the colour

    /// White on dark, black on bright — and the crossover sits well above the
    /// contrast-neutral point, because the text carries a shadow.
    @Test func smartColourFollowsBrightness() {
        #expect(WidgetTextColor.smartColor(luma: 0) == .white)
        #expect(WidgetTextColor.smartColor(luma: 0.4) == .white)
        #expect(WidgetTextColor.smartColor(luma: 1) == .black)
        #expect(WidgetTextColor.smartCrossover > 0.5)
    }

    /// The sentinel is recognised whatever case it was written in, and no real
    /// swatch is mistaken for it.
    @Test func smartIsToldApartFromAHex() {
        #expect(WidgetTextColor.isSmart(hex: "smart"))
        #expect(WidgetTextColor.isSmart(hex: "Smart"))
        #expect(!WidgetTextColor.isSmart(hex: "#FFFFFF"))
        #expect(!WidgetTextColor.isValid(hex: WidgetTextColor.smartHex))
        // …but the store must still keep it: an "invalid hex" sweep is what
        // scrubbed Smart back to white the first time.
        #expect(WidgetTextColor.isStorable(hex: WidgetTextColor.smartHex))
        #expect(WidgetTextColor.isStorable(hex: "#FFFFFF"))
        #expect(!WidgetTextColor.isStorable(hex: "nonsense"))
    }

    /// With no picture to measure, Smart is white — the grey placeholder the
    /// preview draws wants white, and so does a widget whose photo failed to
    /// load.
    @Test func smartWithoutAPictureIsWhite() {
        #expect(WidgetTextColor.color(hex: WidgetTextColor.smartHex, luma: nil) == .white)
        #expect(WidgetTextColor.color(hex: "#000000", luma: 0.9) == WidgetTextColor.color(hex: "#000000"))
    }

    // MARK: Helpers

    private func makeImage(
        width: Int,
        height: Int,
        draw: (CGContext) -> Void
    ) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        draw(context)
        return context.makeImage()
    }
}
