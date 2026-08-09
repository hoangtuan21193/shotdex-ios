import CoreGraphics
import Foundation

/// The shared geometry between the interactive collage canvas and the export
/// compositor. Both resolve cell frames and photo placement through these
/// functions, so preview-vs-export fidelity is a property of the math (pinned
/// by unit tests) rather than something a re-render has to maintain.
///
/// All frames are top-down (SwiftUI convention); the compositor flips once
/// when it draws into a bottom-up CGContext.
enum CollageGeometry {
    /// Output canvas for an aspect `ratio` (width/height), long edge capped.
    /// Dimensions round to even integers — video-adjacent encoders and some
    /// JPEG consumers dislike odd sizes, and one pixel is invisible at 4096.
    static func outputSize(ratio: Double, longEdge: CGFloat) -> CGSize {
        guard ratio > 0, longEdge > 0 else { return .zero }
        var width: CGFloat
        var height: CGFloat
        if ratio >= 1 {
            width = longEdge
            height = longEdge / ratio
        } else {
            height = longEdge
            width = longEdge * ratio
        }
        width = (width / 2).rounded() * 2
        height = (height / 2).rounded() * 2
        return CGSize(width: width, height: height)
    }

    /// `gutter`/`cornerRadius` recipe values are fractions of the short edge.
    static func gutterPixels(_ normalized: Double, canvasSize: CGSize) -> CGFloat {
        max(0, CGFloat(normalized) * min(canvasSize.width, canvasSize.height))
    }

    static func cornerRadiusPixels(_ normalized: Double, canvasSize: CGSize) -> CGFloat {
        max(0, CGFloat(normalized) * min(canvasSize.width, canvasSize.height))
    }

    /// Unit rects → pixel frames with the gutter applied. Sides on the canvas
    /// edge inset by the full gutter, interior sides by half — two neighbours
    /// then leave exactly one gutter of visible background between them, the
    /// same gap as the outer margin.
    static func cellFrames(
        template: CollageTemplate,
        canvasSize: CGSize,
        gutter: CGFloat
    ) -> [CGRect] {
        let epsilon = 1e-6
        return template.cells.map { cell in
            let raw = CGRect(
                x: cell.x * canvasSize.width,
                y: cell.y * canvasSize.height,
                width: cell.width * canvasSize.width,
                height: cell.height * canvasSize.height
            )
            let left = cell.x <= epsilon ? gutter : gutter / 2
            let right = cell.x + cell.width >= 1 - epsilon ? gutter : gutter / 2
            let top = cell.y <= epsilon ? gutter : gutter / 2
            let bottom = cell.y + cell.height >= 1 - epsilon ? gutter : gutter / 2
            return CGRect(
                x: raw.minX + left,
                y: raw.minY + top,
                width: max(1, raw.width - left - right),
                height: max(1, raw.height - top - bottom)
            )
        }
    }

    /// Where the photo's pixels sit for a cell: aspect-fill baseline scaled by
    /// `scale`, panned by `offset` in fractions of the cell's size.
    static func imageFrame(
        imageSize: CGSize,
        cellFrame: CGRect,
        scale: Double,
        offset: NormalizedPoint
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return cellFrame }
        let fill = max(cellFrame.width / imageSize.width, cellFrame.height / imageSize.height)
        let factor = fill * CGFloat(scale)
        let size = CGSize(width: imageSize.width * factor, height: imageSize.height * factor)
        let origin = CGPoint(
            x: cellFrame.midX - size.width / 2 + CGFloat(offset.x) * cellFrame.width,
            y: cellFrame.midY - size.height / 2 + CGFloat(offset.y) * cellFrame.height
        )
        return CGRect(origin: origin, size: size)
    }

    /// Clamps a gesture-end transform so the photo always covers its cell —
    /// the background must never peek through, whatever the drag did.
    static func clampedContent(
        imageSize: CGSize,
        cellFrame: CGRect,
        scale: Double,
        offset: NormalizedPoint
    ) -> (scale: Double, offset: NormalizedPoint) {
        let clampedScale = min(
            max(scale, CollageCell.minimumContentScale),
            CollageCell.maximumContentScale
        )
        guard imageSize.width > 0, imageSize.height > 0,
              cellFrame.width > 0, cellFrame.height > 0
        else { return (clampedScale, NormalizedPoint(x: 0, y: 0)) }

        let frame = imageFrame(
            imageSize: imageSize,
            cellFrame: cellFrame,
            scale: clampedScale,
            offset: NormalizedPoint(x: 0, y: 0)
        )
        let maxOffsetX = Double((frame.width - cellFrame.width) / 2 / cellFrame.width)
        let maxOffsetY = Double((frame.height - cellFrame.height) / 2 / cellFrame.height)
        let clampedOffset = NormalizedPoint(
            x: min(max(offset.x, -maxOffsetX), maxOffsetX),
            y: min(max(offset.y, -maxOffsetY), maxOffsetY)
        )
        return (clampedScale, clampedOffset)
    }

    /// Hit test for the swap-drop target; the gutter and outside return nil.
    static func cellIndex(at point: CGPoint, frames: [CGRect]) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }
}
