import CoreGraphics
import Foundation

/// What the scoring pass measured on one grouped photo (FS-06.06 §6), as
/// stored in `duplicate_quality`. Numbers only: no pixels, no faces.
struct DuplicateQualityScore: Equatable, Sendable {
    /// Variance of the Laplacian on the 512px thumbnail; only comparable
    /// within one group. `nil` when the thumbnail could not be read.
    var sharpness: Double?
    /// 0…1, the least-open pair of eyes among the faces Vision trusted.
    /// `nil` when there was no face, or none Vision was sure of.
    var eyesOpen: Double?
    var eyeConfidence: Double?
    /// Share of pixels at ≥ 250 and ≤ 5 luma.
    var highlightClip: Double = 0
    var shadowClip: Double = 0
    /// Largest face, normalized to the image (origin top left), for Zoom to face.
    var faceRect: CGRect?

    /// The thumbnail was read and measured.
    var isScored: Bool { sharpness != nil }

    /// Eyes read as closed, by a face Vision was sure enough of.
    var hasEyesClosed: Bool {
        guard let eyesOpen, let eyeConfidence, eyeConfidence >= DuplicateQuality.eyeConfidenceThreshold else { return false }
        return eyesOpen < DuplicateQuality.eyesOpenThreshold
    }

    var hasTrustedEyes: Bool {
        guard eyesOpen != nil, let eyeConfidence else { return false }
        return eyeConfidence >= DuplicateQuality.eyeConfidenceThreshold
    }
}

/// Pure measures behind the scores — fed an 8-bit luma buffer, so the tests
/// run on generated images and the scanner on PhotoKit thumbnails alike.
enum DuplicateQuality {
    /// A photo ≥ 35% less sharp than the group's sharpest is *Soft*.
    static let softRatio = 0.65
    /// Sharpness within 10% of another is a tie: the next rule decides.
    static let sharpnessTieRatio = 0.9
    /// *Blown highlights* / *Too dark*: over 2% clipped while the keeper is
    /// at most 0.5%.
    static let clipCaption = 0.02
    static let clipKeeperMax = 0.005
    static let highlightLuma: UInt8 = 250
    static let shadowLuma: UInt8 = 5
    /// Below this Vision confidence nothing is said about eyes (§6). Set
    /// before the device spike (§12) on the safe side; the spike may lower it.
    static let eyeConfidenceThreshold = 0.8
    static let eyesOpenThreshold = 0.35
    /// Long edge of the thumbnail the pass measures.
    static let thumbnailEdge = 512

    /// Sharpness and clipping of one luma image (row-major, `width` × `height`).
    static func measure(luma: [UInt8], width: Int, height: Int) -> DuplicateQualityScore {
        guard width >= 3, height >= 3, luma.count >= width * height else {
            return DuplicateQualityScore(sharpness: nil)
        }
        var highlights = 0, shadows = 0
        for value in luma.prefix(width * height) {
            if value >= highlightLuma { highlights += 1 } else if value <= shadowLuma { shadows += 1 }
        }
        // 4-neighbour Laplacian over the interior; Welford-free two sums is
        // exact enough in Double for 512px images.
        var sum = 0.0, sumSquares = 0.0
        let count = Double((width - 2) * (height - 2))
        luma.withUnsafeBufferPointer { pixels in
            for y in 1..<(height - 1) {
                let row = y * width
                for x in 1..<(width - 1) {
                    let center = Int(pixels[row + x]) * 4
                    let laplacian = Double(Int(pixels[row + x - 1]) + Int(pixels[row + x + 1])
                        + Int(pixels[row - width + x]) + Int(pixels[row + width + x]) - center)
                    sum += laplacian
                    sumSquares += laplacian * laplacian
                }
            }
        }
        let mean = sum / count
        let total = Double(width * height)
        return DuplicateQualityScore(
            sharpness: max(0, sumSquares / count - mean * mean),
            highlightClip: Double(highlights) / total,
            shadowClip: Double(shadows) / total
        )
    }

    /// `left` is the better frame to keep by what was measured: no closed
    /// eyes first, then clearly sharper, then less clipping. `nil` when the
    /// scores do not tell them apart — the file rule decides.
    static func better(_ left: DuplicateQualityScore, than right: DuplicateQualityScore) -> Bool? {
        if left.hasEyesClosed != right.hasEyesClosed { return !left.hasEyesClosed }
        if let a = left.sharpness, let b = right.sharpness, max(a, b) > 0, min(a, b) / max(a, b) < sharpnessTieRatio {
            return a > b
        }
        let clipLeft = left.highlightClip + left.shadowClip
        let clipRight = right.highlightClip + right.shadowClip
        if abs(clipLeft - clipRight) > clipKeeperMax { return clipLeft < clipRight }
        return nil
    }
}
