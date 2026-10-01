import Foundation

/// The order, the reference and the warnings of an HDR series (FS-01.11 §4).
///
/// Frames run from darkest to brightest: alignment registers each frame to its
/// neighbour, and neighbours in exposure share the most detail. The reference
/// is the middle exposure — its content is kept where frames disagree, and its
/// EXIF goes on the result.
enum HDRBracketOrder {
    struct Frame<ID: Hashable>: Hashable {
        var id: ID
        var shutterSeconds: Double?
        var iso: Double?
        var aperture: Double?
        var exposureBias: Double?
        var isRAW: Bool
        /// log₂ of the median luminance after decoding, for a frame whose EXIF
        /// says nothing about its exposure.
        var measuredLog2Brightness: Double?
    }

    struct Series<ID: Hashable> {
        /// Darkest first.
        var order: [ID]
        /// Exposure of each frame in `order`, in stops relative to the reference.
        var stops: [Double]
        /// Index into `order`.
        var reference: Int
        /// Exposures spread less than `minimumSpread` — not a bracket.
        var isSameExposure: Bool
        /// Some frames are RAW and some are not: every frame is merged from its
        /// processed version (FS-01.11 §5).
        var isMixedRAW: Bool
        /// Every frame is RAW: the series merges from the RAW data.
        var mergesFromRAW: Bool
    }

    /// Below this spread a selection is not a bracket (FS-01.11 §4, AC-11).
    static let minimumSpread = 0.5

    /// Exposure of one frame in stops, on an absolute scale shared by the
    /// series: log₂(t · ISO / N²). The camera's Exposure Bias is *not* added on
    /// top — in a bracket the camera carries the bias out by changing the
    /// shutter (or ISO, or aperture), so it is already in those three. Bias is
    /// the fallback when the three are missing, and the measured brightness
    /// after that.
    static func stops<ID>(of frame: Frame<ID>) -> Double? {
        if let t = frame.shutterSeconds, t > 0, let iso = frame.iso, iso > 0, let n = frame.aperture, n > 0 {
            return log2(t * iso / (n * n))
        }
        if let bias = frame.exposureBias { return bias }
        return frame.measuredLog2Brightness
    }

    static func series<ID>(_ frames: [Frame<ID>]) -> Series<ID> {
        // One scale for the whole series: mixing an EXIF exposure with a bias
        // or a measurement would compare stops to nothing. Use the first
        // source every frame has.
        let absolute: [Double]
        if frames.allSatisfy({ ($0.shutterSeconds ?? 0) > 0 && ($0.iso ?? 0) > 0 && ($0.aperture ?? 0) > 0 }) {
            absolute = frames.map { log2($0.shutterSeconds! * $0.iso! / ($0.aperture! * $0.aperture!)) }
        } else if frames.allSatisfy({ $0.exposureBias != nil }) {
            absolute = frames.map { $0.exposureBias! }
        } else if frames.allSatisfy({ $0.measuredLog2Brightness != nil }) {
            absolute = frames.map { $0.measuredLog2Brightness! }
        } else {
            absolute = frames.map { _ in 0 }
        }
        let sorted = zip(frames, absolute).enumerated().sorted { lhs, rhs in
            lhs.element.1 != rhs.element.1 ? lhs.element.1 < rhs.element.1 : lhs.offset < rhs.offset
        }
        let order = sorted.map(\.element.0.id)
        let values = sorted.map(\.element.1)
        // Middle exposure; of two in the middle, the brighter.
        let reference = values.count / 2
        let referenceStops = values.isEmpty ? 0 : values[reference]
        let spread = (values.last ?? 0) - (values.first ?? 0)
        let rawCount = frames.filter(\.isRAW).count
        return Series(
            order: order,
            stops: values.map { $0 - referenceStops },
            reference: reference,
            isSameExposure: spread < minimumSpread,
            isMixedRAW: rawCount > 0 && rawCount < frames.count,
            mergesFromRAW: !frames.isEmpty && rawCount == frames.count
        )
    }
}
