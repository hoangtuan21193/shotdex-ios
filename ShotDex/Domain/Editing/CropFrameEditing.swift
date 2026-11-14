import CoreGraphics
import Foundation
import ImageIO
import ShotDexKit

/// The Mac crop frame's arithmetic (FS-18.03 §1b): dragging a corner, an
/// edge or the whole frame, keeping a locked ratio, keeping the frame on the
/// photo once it is straightened, turning and mirroring the frame with the
/// photo, and the size line.
///
/// Every rect is normalized against the frame the crop renders over: the
/// photo after its quarter turns, flip and straighten — the straightened
/// photo's bounding box, y down (what `PhotoRenderService.applyCrop` reads).
struct CropFrameEditing {
    /// The photo after its quarter turns, in pixels (no straighten).
    var photoSize: CGSize
    /// `straightenDegrees`: counter-clockwise on screen.
    var degrees: Double

    static let minimumEdge = CropFrameGeometry.minimumEdge

    init(photoSize: CGSize, degrees: Double) {
        self.photoSize = CGSize(width: max(1, photoSize.width), height: max(1, photoSize.height))
        self.degrees = degrees
    }

    /// The source's pixel size as the crop sees it: the file's orientation
    /// and the recipe's quarter turns applied.
    static func photoSize(pixelWidth: Int, pixelHeight: Int, orientation: CGImagePropertyOrientation, quarterTurns: Int) -> CGSize {
        var size = CGSize(width: pixelWidth, height: pixelHeight)
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored: size = CGSize(width: size.height, height: size.width)
        default: break
        }
        if !quarterTurns.isMultiple(of: 2) { size = CGSize(width: size.height, height: size.width) }
        return size
    }

    private var radians: Double { degrees * .pi / 180 }

    /// The straightened photo's bounding box, in pixels.
    var frameSize: CGSize {
        let c = abs(cos(radians)), s = abs(sin(radians))
        return CGSize(width: photoSize.width * c + photoSize.height * s,
                      height: photoSize.width * s + photoSize.height * c)
    }

    /// Width over height of the frame the rect is normalized against.
    var frameAspect: Double { Double(frameSize.width / frameSize.height) }

    /// The photo's own width over height: what Original locks to.
    var photoAspect: Double { Double(photoSize.width / photoSize.height) }

    /// The ratio a locked aspect holds the crop to, in pixels.
    func ratio(of aspect: CropAspect) -> Double? {
        aspect == .original ? photoAspect : aspect.ratio
    }

    // MARK: On the photo

    /// The point lies on the photo, not in a corner the straighten left empty.
    func isOnPhoto(x: Double, y: Double) -> Bool {
        let frame = frameSize
        let px = (x - 0.5) * Double(frame.width)
        let up = -(y - 0.5) * Double(frame.height)
        let localX = px * cos(radians) + up * sin(radians)
        let localY = -px * sin(radians) + up * cos(radians)
        let slack = 0.5
        return abs(localX) <= Double(photoSize.width) / 2 + slack && abs(localY) <= Double(photoSize.height) / 2 + slack
    }

    func isOnPhoto(_ rect: NormalizedRect) -> Bool {
        rect.x >= -1e-9 && rect.y >= -1e-9 && rect.x + rect.width <= 1 + 1e-9 && rect.y + rect.height <= 1 + 1e-9
            && isOnPhoto(x: rect.x, y: rect.y) && isOnPhoto(x: rect.x + rect.width, y: rect.y)
            && isOnPhoto(x: rect.x, y: rect.y + rect.height) && isOnPhoto(x: rect.x + rect.width, y: rect.y + rect.height)
    }

    /// `rect` shrunk about its centre — the centre first pulled toward the
    /// photo's while it sits off the photo — until it lies on the photo.
    /// What a new angle does to the frame, as Lightroom keeps it.
    func fitted(_ rect: NormalizedRect) -> NormalizedRect {
        if isOnPhoto(rect) { return rect }
        var cx = rect.x + rect.width / 2, cy = rect.y + rect.height / 2
        if !isOnPhoto(x: cx, y: cy) {
            var low = 0.0, high = 1.0
            for _ in 0..<30 {
                let t = (low + high) / 2
                if isOnPhoto(x: cx + (0.5 - cx) * t, y: cy + (0.5 - cy) * t) { high = t } else { low = t }
            }
            cx += (0.5 - cx) * high
            cy += (0.5 - cy) * high
        }
        func scaled(_ s: Double) -> NormalizedRect {
            NormalizedRect(x: cx - rect.width * s / 2, y: cy - rect.height * s / 2, width: rect.width * s, height: rect.height * s)
        }
        var low = 0.0, high = 1.0
        for _ in 0..<30 {
            let s = (low + high) / 2
            if isOnPhoto(scaled(s)) { low = s } else { high = s }
        }
        return scaled(low)
    }

    /// The furthest a drag gets from `valid` toward `proposed` while the
    /// frame stays on the photo: an edge stops at the photo's, it does not
    /// jump.
    func clamped(from valid: NormalizedRect, to proposed: NormalizedRect) -> NormalizedRect {
        if isOnPhoto(proposed) { return proposed }
        guard isOnPhoto(valid) else { return fitted(proposed) }
        func lerp(_ t: Double) -> NormalizedRect {
            NormalizedRect(x: valid.x + (proposed.x - valid.x) * t, y: valid.y + (proposed.y - valid.y) * t,
                           width: valid.width + (proposed.width - valid.width) * t,
                           height: valid.height + (proposed.height - valid.height) * t)
        }
        var low = 0.0, high = 1.0
        for _ in 0..<30 {
            let t = (low + high) / 2
            if isOnPhoto(lerp(t)) { low = t } else { high = t }
        }
        return lerp(low)
    }

    // MARK: Dragging

    enum Handle: Equatable, Sendable {
        case corner(right: Bool, bottom: Bool)
        case edge(CropEdge)
        case move
    }

    /// The frame after `handle` moves by `dx`, `dy` (normalized) from where
    /// it was at the start of the drag. A corner keeps the opposite corner,
    /// an edge the opposite edge; a locked `ratio` (pixels) is held.
    func dragged(_ start: NormalizedRect, handle: Handle, dx: Double, dy: Double, ratio: Double?) -> NormalizedRect {
        let minimum = Self.minimumEdge
        let normalizedRatio = ratio.map { $0 / max(0.0001, frameAspect) }
        var rect = start
        switch handle {
        case .move:
            rect.x = min(1 - rect.width, max(0, rect.x + dx))
            rect.y = min(1 - rect.height, max(0, rect.y + dy))
        case let .corner(right, bottom):
            let anchorX = right ? start.x : start.x + start.width
            let anchorY = bottom ? start.y : start.y + start.height
            let maximumWidth = right ? 1 - anchorX : anchorX
            let maximumHeight = bottom ? 1 - anchorY : anchorY
            var width = min(maximumWidth, max(minimum, start.width + (right ? dx : -dx)))
            var height = min(maximumHeight, max(minimum, start.height + (bottom ? dy : -dy)))
            if let r = normalizedRatio {
                if width / max(0.0001, height) > r { height = width / r } else { width = height * r }
                let scale = min(1, min(maximumWidth / max(0.0001, width), maximumHeight / max(0.0001, height)))
                width *= scale
                height *= scale
            }
            rect = NormalizedRect(x: right ? anchorX : anchorX - width, y: bottom ? anchorY : anchorY - height,
                                  width: width, height: height)
        case let .edge(edge):
            switch edge {
            case .left:
                let x = min(start.x + start.width - minimum, max(0, start.x + dx))
                rect.x = x
                rect.width = start.x + start.width - x
            case .right:
                rect.width = min(1, max(start.x + minimum, start.x + start.width + dx)) - start.x
            case .top:
                let y = min(start.y + start.height - minimum, max(0, start.y + dy))
                rect.y = y
                rect.height = start.y + start.height - y
            case .bottom:
                rect.height = min(1, max(start.y + minimum, start.y + start.height + dy)) - start.y
            }
            if let r = normalizedRatio {
                // The other axis follows about its centre, then everything fits.
                if edge.isHorizontal {
                    var height = rect.width / r
                    var width = rect.width
                    if height > 1 { height = 1; width = r }
                    rect.height = height
                    rect.width = width
                    rect.y = min(1 - height, max(0, start.y + start.height / 2 - height / 2))
                    if edge == .left { rect.x = start.x + start.width - width }
                } else {
                    var width = rect.height * r
                    var height = rect.height
                    if width > 1 { width = 1; height = 1 / r }
                    rect.width = width
                    rect.height = height
                    rect.x = min(1 - width, max(0, start.x + start.width / 2 - width / 2))
                    if edge == .top { rect.y = start.y + start.height - height }
                }
            }
        }
        return clamped(from: start, to: rect)
    }

    /// `rect` reshaped to `ratio` (pixels) about its centre, keeping its area,
    /// then kept on the photo.
    func reshaped(_ rect: NormalizedRect, toRatio ratio: Double) -> NormalizedRect {
        fitted(CropFrameGeometry.rect(matchingRatio: ratio, keepingAreaOf: rect, imageAspect: frameAspect))
    }

    // MARK: Words

    /// "5712 × 3808 px" and how much of the photo it keeps.
    func pixelSize(of rect: NormalizedRect) -> (width: Int, height: Int, percent: Int) {
        let frame = frameSize
        let width = Int((Double(frame.width) * rect.width).rounded())
        let height = Int((Double(frame.height) * rect.height).rounded())
        let whole = Double(photoSize.width * photoSize.height)
        let percent = Int((Double(width * height) / max(1, whole) * 100).rounded())
        return (width, height, min(100, percent))
    }

    /// The preset a ratio reads as ("3:2"), when one matches within 1%.
    static func preset(matching ratio: Double) -> CropAspect? {
        CropAspect.allCases.first { aspect in
            guard let r = aspect.ratio else { return false }
            return abs(r - ratio) / r < 0.01
        }
    }

    // MARK: Turning and mirroring

    /// The frame turned with the photo a quarter turn (clockwise when `clockwise`).
    static func turned(_ rect: NormalizedRect, clockwise: Bool) -> NormalizedRect {
        clockwise
            ? NormalizedRect(x: 1 - (rect.y + rect.height), y: rect.x, width: rect.height, height: rect.width)
            : NormalizedRect(x: rect.y, y: 1 - (rect.x + rect.width), width: rect.height, height: rect.width)
    }

    static func mirroredHorizontally(_ rect: NormalizedRect) -> NormalizedRect {
        NormalizedRect(x: 1 - rect.x - rect.width, y: rect.y, width: rect.width, height: rect.height)
    }

    static func mirroredVertically(_ rect: NormalizedRect) -> NormalizedRect {
        NormalizedRect(x: rect.x, y: 1 - rect.y - rect.height, width: rect.width, height: rect.height)
    }
}
