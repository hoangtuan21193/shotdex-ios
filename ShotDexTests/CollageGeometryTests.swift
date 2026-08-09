import CoreGraphics
import Foundation
import Testing
@testable import ShotDex

struct CollageGeometryTests {
    private func isClose(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 0.001) -> Bool {
        abs(a - b) <= tolerance
    }

    // MARK: - Output size

    @Test func outputSizeRespectsAspectAndCap() {
        for aspect in CollageAspect.allCases {
            let size = CollageGeometry.outputSize(ratio: aspect.ratio, longEdge: 4096)
            #expect(max(size.width, size.height) <= 4096)
            #expect(max(size.width, size.height) >= 4094, "\(aspect.rawValue)")
            #expect(isClose(size.width / size.height, CGFloat(aspect.ratio), tolerance: 0.01))
            #expect(size.width.truncatingRemainder(dividingBy: 2) == 0)
            #expect(size.height.truncatingRemainder(dividingBy: 2) == 0)
        }
    }

    @Test func degenerateOutputSizeIsZero() {
        #expect(CollageGeometry.outputSize(ratio: 0, longEdge: 4096) == .zero)
        #expect(CollageGeometry.outputSize(ratio: 1, longEdge: 0) == .zero)
    }

    // MARK: - Cell frames

    /// With no gutter the pixel frames must reproduce the unit rects exactly —
    /// this is what makes the SwiftUI preview and the export bitmap agree.
    @Test func zeroGutterFramesTileCanvas() {
        let template = CollageTemplateCatalog.template(id: "4-grid")!
        let canvas = CGSize(width: 1000, height: 800)
        let frames = CollageGeometry.cellFrames(template: template, canvasSize: canvas, gutter: 0)
        for (index, cell) in template.cells.enumerated() {
            let expected = CGRect(
                x: cell.x * canvas.width,
                y: cell.y * canvas.height,
                width: cell.width * canvas.width,
                height: cell.height * canvas.height
            )
            #expect(isClose(frames[index].minX, expected.minX))
            #expect(isClose(frames[index].minY, expected.minY))
            #expect(isClose(frames[index].width, expected.width))
            #expect(isClose(frames[index].height, expected.height))
        }
    }

    /// Outer margin equals the gutter and the visible gap between neighbours
    /// equals the gutter too (half inset from each side).
    @Test func gutterProducesUniformGaps() {
        let template = CollageTemplateCatalog.template(id: "4-grid")!
        let canvas = CGSize(width: 1000, height: 1000)
        let gutter: CGFloat = 20
        let frames = CollageGeometry.cellFrames(
            template: template,
            canvasSize: canvas,
            gutter: gutter
        )
        // Outer margins.
        #expect(isClose(frames[0].minX, gutter))
        #expect(isClose(frames[0].minY, gutter))
        #expect(isClose(frames[3].maxX, canvas.width - gutter))
        #expect(isClose(frames[3].maxY, canvas.height - gutter))
        // Interior gaps: cells 0|1 share the vertical seam, 0|2 the horizontal.
        #expect(isClose(frames[1].minX - frames[0].maxX, gutter))
        #expect(isClose(frames[2].minY - frames[0].maxY, gutter))
    }

    @Test func extremeGutterKeepsFramesNonDegenerate() {
        let template = CollageTemplateCatalog.template(id: "9-grid")!
        let canvas = CGSize(width: 300, height: 300)
        let frames = CollageGeometry.cellFrames(
            template: template,
            canvasSize: canvas,
            gutter: 90
        )
        for frame in frames {
            #expect(frame.width >= 1)
            #expect(frame.height >= 1)
        }
    }

    // MARK: - Image placement

    @Test func imageFrameCoversCellAtBaseline() {
        let cell = CGRect(x: 100, y: 50, width: 400, height: 300)
        let sources = [
            CGSize(width: 4000, height: 3000),  // wide
            CGSize(width: 3000, height: 4000),  // tall
            CGSize(width: 2000, height: 2000),  // square
        ]
        for source in sources {
            let frame = CollageGeometry.imageFrame(
                imageSize: source,
                cellFrame: cell,
                scale: 1,
                offset: NormalizedPoint(x: 0, y: 0)
            )
            #expect(frame.minX <= cell.minX + 0.001)
            #expect(frame.minY <= cell.minY + 0.001)
            #expect(frame.maxX >= cell.maxX - 0.001)
            #expect(frame.maxY >= cell.maxY - 0.001)
        }
    }

    /// Whatever the gesture produced, the committed transform must leave the
    /// cell fully covered — the background never peeks through a cell.
    @Test func clampedContentNeverExposesBackground() {
        let cell = CGRect(x: 0, y: 0, width: 400, height: 300)
        let image = CGSize(width: 4000, height: 3000)
        let wild: [(Double, NormalizedPoint)] = [
            (1, NormalizedPoint(x: 5, y: -5)),
            (0.2, NormalizedPoint(x: 0.4, y: 0.4)),
            (9, NormalizedPoint(x: -12, y: 3)),
            (2, NormalizedPoint(x: 0.1, y: -0.05)),
        ]
        for (scale, offset) in wild {
            let clamped = CollageGeometry.clampedContent(
                imageSize: image,
                cellFrame: cell,
                scale: scale,
                offset: offset
            )
            #expect(clamped.scale >= CollageCell.minimumContentScale)
            #expect(clamped.scale <= CollageCell.maximumContentScale)
            let frame = CollageGeometry.imageFrame(
                imageSize: image,
                cellFrame: cell,
                scale: clamped.scale,
                offset: clamped.offset
            )
            #expect(frame.minX <= cell.minX + 0.001)
            #expect(frame.minY <= cell.minY + 0.001)
            #expect(frame.maxX >= cell.maxX - 0.001)
            #expect(frame.maxY >= cell.maxY - 0.001)
        }
    }

    @Test func inRangeContentSurvivesClampingUnchanged() {
        let cell = CGRect(x: 0, y: 0, width: 400, height: 400)
        let image = CGSize(width: 4000, height: 3000)
        // Scale 2 on a 4:3 source in a square cell leaves generous slack.
        let clamped = CollageGeometry.clampedContent(
            imageSize: image,
            cellFrame: cell,
            scale: 2,
            offset: NormalizedPoint(x: 0.1, y: 0.1)
        )
        #expect(clamped.scale == 2)
        #expect(isClose(CGFloat(clamped.offset.x), 0.1))
        #expect(isClose(CGFloat(clamped.offset.y), 0.1))
    }

    // MARK: - Hit test

    @Test func cellIndexHitTest() {
        let frames = [
            CGRect(x: 10, y: 10, width: 100, height: 100),
            CGRect(x: 130, y: 10, width: 100, height: 100),
        ]
        #expect(CollageGeometry.cellIndex(at: CGPoint(x: 50, y: 50), frames: frames) == 0)
        #expect(CollageGeometry.cellIndex(at: CGPoint(x: 140, y: 20), frames: frames) == 1)
        // The gutter between the two cells belongs to neither.
        #expect(CollageGeometry.cellIndex(at: CGPoint(x: 120, y: 50), frames: frames) == nil)
        #expect(CollageGeometry.cellIndex(at: CGPoint(x: 500, y: 500), frames: frames) == nil)
    }
}
