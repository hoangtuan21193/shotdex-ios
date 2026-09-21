import CoreGraphics
import SwiftUI

/// How bright the photo is, cell by cell, so the text drawn over it can pick a
/// colour that reads against *this* picture rather than against an average one.
///
/// Measured once when the picture is decoded — one Core Graphics draw into a
/// 16×16 context, the resampler doing the averaging — and then it is 256
/// doubles carried alongside the image. The same technique `CoverTitleScrim`
/// uses for album covers, at a grid instead of a single pixel, because a widget
/// puts its text wherever the user dragged it and the bottom strip is no longer
/// the answer.
struct PhotoWidgetLumaGrid: Equatable, Sendable {
    /// Cells per side. 16 is fine enough that a clock sitting over one bright
    /// cloud is measured on that cloud, and coarse enough that the whole grid
    /// is a rounding error next to the decoded image.
    static let side = 16

    /// Row-major, `side * side` values in 0…1.
    let values: [Double]

    init?(values: [Double]) {
        guard values.count == Self.side * Self.side else { return nil }
        self.values = values
    }

    /// Rec. 709 luma per cell — green carries most of perceived brightness, so
    /// a plain RGB mean calls a saturated blue sky darker than it reads.
    static func make(from cgImage: CGImage) -> PhotoWidgetLumaGrid? {
        let side = Self.side
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let success: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: side,
                      height: side,
                      bitsPerComponent: 8,
                      bytesPerRow: side * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard success else { return nil }

        var values = [Double](repeating: 0, count: side * side)
        for index in 0..<(side * side) {
            let red = Double(pixels[index * 4]) / 255
            let green = Double(pixels[index * 4 + 1]) / 255
            let blue = Double(pixels[index * 4 + 2]) / 255
            values[index] = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        }
        return PhotoWidgetLumaGrid(values: values)
    }

    /// Average brightness under a rectangle given in normalized image
    /// coordinates (0…1, origin top-left), weighted by how much of each cell
    /// the rectangle covers.
    ///
    /// A rectangle that misses the picture entirely — which a hard zoom and a
    /// dragged line can produce together — reads as the whole picture rather
    /// than as black.
    func luma(inNormalizedRect rect: CGRect) -> Double {
        let side = Self.side
        let clamped = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !clamped.isNull, clamped.width > 0, clamped.height > 0 else {
            return values.reduce(0, +) / Double(values.count)
        }

        var total = 0.0
        var weight = 0.0
        let firstColumn = max(0, Int(clamped.minX * Double(side)))
        let lastColumn = min(side - 1, Int(clamped.maxX * Double(side) - 1e-9))
        let firstRow = max(0, Int(clamped.minY * Double(side)))
        let lastRow = min(side - 1, Int(clamped.maxY * Double(side) - 1e-9))
        for row in firstRow...lastRow {
            for column in firstColumn...lastColumn {
                let cell = CGRect(
                    x: Double(column) / Double(side),
                    y: Double(row) / Double(side),
                    width: 1 / Double(side),
                    height: 1 / Double(side)
                )
                let overlap = cell.intersection(clamped)
                guard !overlap.isNull else { continue }
                let area = overlap.width * overlap.height
                guard area > 0 else { continue }
                total += values[row * side + column] * area
                weight += area
            }
        }
        guard weight > 0 else {
            return values.reduce(0, +) / Double(values.count)
        }
        return total / weight
    }
}

extension PhotoWidgetImageLayer {
    /// Where a rectangle of the widget lands on the picture, in normalized
    /// image coordinates.
    ///
    /// The inverse of what the layer draws: `scaledToFill` into the widget,
    /// then `scaleEffect`, then an offset of `slack × photoOffset`. Pure, so
    /// "which part of the photo is under the clock" is a test rather than a
    /// guess.
    static func normalizedImageRect(
        for widgetRect: CGRect,
        in size: CGSize,
        aspectRatio: Double,
        scale: Double,
        offsetX: Double,
        offsetY: Double
    ) -> CGRect {
        guard size.width > 0, size.height > 0, aspectRatio > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let scale = max(1, min(scale, PhotoWidgetSettings.maximumPhotoScale))
        let frameAspect = size.width / size.height
        let filled: CGSize = aspectRatio > frameAspect
            ? CGSize(width: size.height * aspectRatio, height: size.height)
            : CGSize(width: size.width, height: size.width / aspectRatio)
        let drawn = CGSize(width: filled.width * scale, height: filled.height * scale)
        guard drawn.width > 0, drawn.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let slack = PhotoWidgetImageLayer.slack(
            in: size, aspectRatio: aspectRatio, scale: scale
        )
        let origin = CGPoint(
            x: (size.width - drawn.width) / 2 + slack.width * offsetX,
            y: (size.height - drawn.height) / 2 + slack.height * offsetY
        )
        return CGRect(
            x: (widgetRect.minX - origin.x) / drawn.width,
            y: (widgetRect.minY - origin.y) / drawn.height,
            width: widgetRect.width / drawn.width,
            height: widgetRect.height / drawn.height
        )
    }
}
