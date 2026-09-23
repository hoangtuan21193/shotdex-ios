import Foundation

/// What the panorama will be when it is saved: how many pixels, how big the
/// file, how long the wait (FS-14.01 §4b).
///
/// Pixels and megapixels are not estimates — they come out of the geometry
/// that has already been solved, so the number on screen is the number the
/// photo will have. Bytes and seconds are measured on the preview that is
/// already on the stage and scaled up by pixel count, which is how the Resize
/// screen does it; both carry a `~` when they are shown.
public struct PanoramaSizeEstimate: Equatable, Sendable {
    /// What will actually be written, after the JPEG edge limit.
    public let width: Int
    public let height: Int
    /// What the Size control asked for. Equal to `width`/`height` unless the
    /// picture ran into the edge limit.
    public let requestedWidth: Int
    public let requestedHeight: Int
    public let bytes: Int
    public let seconds: Double

    public init(
        width: Int,
        height: Int,
        requestedWidth: Int,
        requestedHeight: Int,
        bytes: Int,
        seconds: Double
    ) {
        self.width = width
        self.height = height
        self.requestedWidth = requestedWidth
        self.requestedHeight = requestedHeight
        self.bytes = bytes
        self.seconds = seconds
    }

    public var megapixels: Double { Double(width) * Double(height) / 1_000_000 }

    /// True when the edge limit, not the Size control, decided the size.
    public var isClamped: Bool { width != requestedWidth || height != requestedHeight }
}

public enum PanoramaSizeEstimator {
    /// The scale the exporter can actually write at.
    ///
    /// `PanoramaExporter` refuses a side over `maximumEdge` rather than
    /// quietly writing a broken file, so a panorama wide enough to reach it
    /// has to come down — and the screen says so before Save is pressed,
    /// instead of failing afterwards.
    public static func writableScale(
        fullWidth: Int,
        fullHeight: Int,
        sizeScale: Double
    ) -> Double {
        guard fullWidth > 0, fullHeight > 0 else { return sizeScale }
        let scale = max(0, sizeScale)
        let longest = Double(max(fullWidth, fullHeight)) * scale
        guard longest > Double(PanoramaExporter.maximumEdge) else { return scale }
        return scale * Double(PanoramaExporter.maximumEdge) / longest
    }

    /// `fullWidth`/`fullHeight` are the picture at the frames' own resolution,
    /// with Auto Crop already taken off; `canvasWidth`/`canvasHeight` are the
    /// same picture *before* the crop, because that is what the renderer draws
    /// and therefore what the edge limit applies to. `bytesPerPixel` and
    /// `secondsPerMegapixel` come from the preview the screen already built.
    public static func estimate(
        fullWidth: Int,
        fullHeight: Int,
        canvasWidth: Int,
        canvasHeight: Int,
        sizeScale: Double,
        bytesPerPixel: Double,
        secondsPerMegapixel: Double
    ) -> PanoramaSizeEstimate? {
        guard fullWidth > 0, fullHeight > 0, sizeScale > 0 else { return nil }
        let requestedWidth = max(1, Int((Double(fullWidth) * sizeScale).rounded()))
        let requestedHeight = max(1, Int((Double(fullHeight) * sizeScale).rounded()))
        let writable = writableScale(
            fullWidth: max(canvasWidth, fullWidth),
            fullHeight: max(canvasHeight, fullHeight),
            sizeScale: sizeScale
        )
        let width = max(1, Int((Double(fullWidth) * writable).rounded()))
        let height = max(1, Int((Double(fullHeight) * writable).rounded()))
        let pixels = Double(width) * Double(height)
        return PanoramaSizeEstimate(
            width: width,
            height: height,
            requestedWidth: requestedWidth,
            requestedHeight: requestedHeight,
            bytes: Int((pixels * max(0, bytesPerPixel)).rounded()),
            seconds: pixels / 1_000_000 * max(0, secondsPerMegapixel)
        )
    }

    /// Free space the save needs: the picture, plus the scratch file it is
    /// written to before PhotoKit takes it. PhotoKit is handed the file with
    /// `shouldMoveFile`, so the two never quite coexist — but the estimate is
    /// the one number the user sees before committing, and rounding it in the
    /// app's favour is how a save fails at 98%.
    public static func requiredFreeBytes(for estimate: PanoramaSizeEstimate) -> Int64 {
        Int64(estimate.bytes) * 2
    }
}
