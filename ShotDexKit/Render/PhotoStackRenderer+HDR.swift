import CoreImage
import Foundation

/// An HDR series fitted and lined up on its reference, ready to merge any
/// number of times: changing Deghost or Strength re-merges it without
/// registering the frames again (FS-01.11 §3).
public struct PreparedHDR: @unchecked Sendable {
    /// The frames that lined up, darkest first, in the reference's geometry.
    public var series: HDRSeries
    /// Indices into the input frames that would not line up and were left out.
    public var excludedFrames: [Int]
    /// For each frame of `series`, its index among the input frames.
    public var inputIndices: [Int]
    /// For each frame of `series`, the Core Image transform that moved it onto
    /// the reference.
    public var maps: [CGAffineTransform]
}

extension PhotoStackRenderer {
    /// Fits every frame to the reference's extent and lines the series up on
    /// it (FS-01.11 §4).
    ///
    /// `images` are linear frames, darkest first, `stops` their exposure
    /// relative to `reference`. Each frame registers to its neighbour in
    /// exposure — neighbours share the most detail — along two chains that
    /// start at the reference, so a stray frame anywhere in the series breaks
    /// neither chain and the result keeps the reference's framing. Frames are
    /// compared at the reference's exposure, clipped as it would clip.
    public func prepareHDR(
        images: [CIImage],
        stops: [Double],
        reference: Int,
        noise: HDRNoiseModel,
        pixelScale: Double
    ) throws -> PreparedHDR {
        guard images.count >= 2, images.count == stops.count, images.indices.contains(reference)
        else { throw PhotoStackError.needsTwoImages }
        let extent = images[reference].extent
        guard extent.width > 0, extent.height > 0 else { throw PhotoStackError.renderFailed }
        let fitted = images.map { Self.fitted($0, to: extent) }
        let small: [CGImage] = zip(fitted, stops).compactMap { frame, stop in
            let level = frame.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -stop])
                .applyingFilter("CIColorClamp")
            return workingImage(of: level, extent: extent, context: renderingContext)
        }
        guard small.count == fitted.count else { throw PhotoStackError.renderFailed }

        // Try the reference first; if nothing lines up with it — the stray
        // frame landed in the middle — the nearest frame stands in.
        let candidates = images.indices.sorted { abs($0 - reference) < abs($1 - reference) }
        for anchor in candidates {
            let maps = Self.hdrMaps(working: small, anchor: anchor, extent: extent)
            let kept = maps.indices.filter { maps[$0] != nil }
            guard kept.count >= 2 else { continue }
            let frames = kept.map { index -> CIImage in
                let map = maps[index]!
                // Clamped before cropping, as in a focus stack: a shifted
                // frame's uncovered edge repeats its border instead of
                // compositing as black.
                return map == .identity ? fitted[index]
                    : fitted[index].transformed(by: map).clampedToExtent().cropped(to: extent)
            }
            let base = stops[anchor]
            return PreparedHDR(
                series: HDRSeries(frames: frames, stops: kept.map { stops[$0] - base },
                                  reference: kept.firstIndex(of: anchor)!, noise: noise, pixelScale: pixelScale),
                excludedFrames: maps.indices.filter { maps[$0] == nil },
                inputIndices: kept,
                maps: kept.map { maps[$0]! }
            )
        }
        throw PhotoStackError.framesDoNotLineUp
    }

    /// Maps onto frame `anchor` for every frame, nil where a frame would not
    /// line up: one chain walking down from the anchor, one walking up.
    static func hdrMaps(working small: [CGImage], anchor: Int, extent: CGRect) -> [CGAffineTransform?] {
        var maps = [CGAffineTransform?](repeating: nil, count: small.count)
        maps[anchor] = .identity
        for chain in [Array(stride(from: anchor, through: 0, by: -1)), Array(anchor..<small.count)] where chain.count > 1 {
            let chainMaps = alignedMaps(working: chain.map { small[$0] }, extent: extent)
            for (position, index) in chain.enumerated().dropFirst() {
                maps[index] = chainMaps[position]
            }
        }
        return maps
    }
}
