import Foundation

/// A rectangle of the canvas, in pixels.
public struct PanoramaCropRect: Sendable, Equatable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var area: Int { width * height }
}

/// Finds the biggest rectangle with no empty corner in it.
///
/// A stitched panorama is never a rectangle: the frames were taken by a hand
/// turning, so the edges come out curved and stepped, and the bounding box has
/// wedges of nothing in it. Auto Crop is the answer that costs no invention —
/// it throws away real pixels rather than making up fake ones, which is why
/// Fill Edges is deliberately not in this app (FS-14 §2).
public enum PanoramaAutoCrop {

    /// The largest axis-aligned rectangle lying entirely inside the covered
    /// area.
    ///
    /// Solved by the histogram method: for each row, how far up the coverage
    /// runs unbroken in each column, then the largest rectangle under that
    /// skyline. That is linear in the number of pixels, where trying rectangles
    /// would be quartic — and this runs on a canvas that can be hundreds of
    /// megapixels.
    public static func largestRectangle(
        coverage: [Float],
        width: Int,
        height: Int
    ) -> PanoramaCropRect? {
        guard width > 0, height > 0, coverage.count >= width * height else { return nil }
        var heights = [Int](repeating: 0, count: width)
        var best: PanoramaCropRect?

        for y in 0..<height {
            for x in 0..<width {
                heights[x] = coverage[y * width + x] > 0 ? heights[x] + 1 : 0
            }
            if let candidate = largestUnderSkyline(heights, bottomRow: y),
               candidate.area > (best?.area ?? 0) {
                best = candidate
            }
        }
        return best
    }

    /// Largest rectangle under a histogram, by the usual stack of increasing
    /// bars: each bar is popped when a shorter one arrives, and that is the
    /// moment its widest possible rectangle is known.
    static func largestUnderSkyline(_ heights: [Int], bottomRow: Int) -> PanoramaCropRect? {
        var stack: [(index: Int, height: Int)] = []
        var best: PanoramaCropRect?

        func consider(left: Int, right: Int, height: Int) {
            guard height > 0, right >= left else { return }
            let rectangle = PanoramaCropRect(
                x: left,
                y: bottomRow - height + 1,
                width: right - left + 1,
                height: height
            )
            if rectangle.area > (best?.area ?? 0) { best = rectangle }
        }

        for (index, height) in heights.enumerated() {
            var start = index
            while let top = stack.last, top.height > height {
                stack.removeLast()
                consider(left: top.index, right: index - 1, height: top.height)
                start = top.index
            }
            if stack.last?.height != height {
                stack.append((start, height))
            }
        }
        while let top = stack.popLast() {
            consider(left: top.index, right: heights.count - 1, height: top.height)
        }
        return best
    }

    /// How much of the covered area a crop keeps. AC-10 asks for at least 80%.
    public static func retainedFraction(
        of crop: PanoramaCropRect,
        coverage: [Float],
        width: Int
    ) -> Double {
        let covered = coverage.reduce(into: 0) { $0 += $1 > 0 ? 1 : 0 }
        guard covered > 0 else { return 0 }
        return Double(crop.area) / Double(covered)
    }

    /// Cuts an image down to the rectangle.
    public static func crop(_ image: PanoramaRGBImage, to rect: PanoramaCropRect) -> PanoramaRGBImage? {
        guard rect.width > 0, rect.height > 0,
              rect.x >= 0, rect.y >= 0,
              rect.x + rect.width <= image.width, rect.y + rect.height <= image.height
        else { return nil }
        var output = PanoramaRGBImage(width: rect.width, height: rect.height)
        for y in 0..<rect.height {
            let sourceRow = (rect.y + y) * image.width + rect.x
            let targetRow = y * rect.width
            for x in 0..<rect.width {
                for channel in 0..<3 {
                    output.pixels[3 * (targetRow + x) + channel] =
                        image.pixels[3 * (sourceRow + x) + channel]
                }
                output.coverage[targetRow + x] = image.coverage[sourceRow + x]
            }
        }
        return output
    }
}
