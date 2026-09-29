import CoreGraphics
import CoreImage
import Foundation
import Vision

/// What an Upright pass is allowed to correct — Lightroom's buttons, less
/// Guided, which draws its own lines.
public enum UprightMode: String, CaseIterable, Identifiable, Sendable {
    /// Level, plus part of Vertical: a building is straightened most of the
    /// way, not pulled up into a false tower (FS-03.15b §4).
    case auto
    /// Rotation only: put the horizon back on the horizontal.
    case level
    /// Keystone only: make the verticals vertical, which is what a building
    /// shot from the pavement needs.
    case vertical
    /// Both.
    case full

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: "Auto"
        case .level: "Level"
        case .vertical: "Vertical"
        case .full: "Full"
        }
    }

    var correctsRotation: Bool { self != .vertical }
    var correctsKeystone: Bool { self != .level }

    /// How much of the measured convergence the mode straightens.
    var keystoneShare: Double { self == .auto ? 0.6 : 1 }
}

public extension UprightMode {
    /// The analysis a stored mode asks for; nil for Off and Guided, which
    /// draw no conclusion from the photo's own lines.
    init?(_ mode: PhotoUprightMode) {
        switch mode {
        case .auto: self = .auto
        case .level: self = .level
        case .vertical: self = .vertical
        case .full: self = .full
        case .off, .guided: return nil
        }
    }
}

public extension PhotoUprightRecipe {
    /// A mode that came from another photo — pasted, synced, a look — with
    /// no transform solved on this one yet.
    var needsSolving: Bool {
        UprightMode(mode) != nil && solved.isIdentity
    }
}

/// Solves a pasted Upright mode on the photo it landed on (FS-03.15b §4):
/// the mode travels with a look, the transform does not.
public enum UprightResolver {
    /// `recipe` with its Upright solved on `image` — the photo's own
    /// unedited pixels — or unchanged when nothing needs solving or the
    /// photo has no lines to solve from.
    public static func resolve(_ recipe: PhotoEditRecipe, on image: CIImage, context: CIContext) -> PhotoEditRecipe {
        guard recipe.upright.needsSolving, let mode = UprightMode(recipe.upright.mode),
              let suggestion = UprightAnalyzer.analyze(image, mode: mode, context: context)
        else { return recipe }
        var resolved = recipe
        resolved.upright.solved = suggestion.transform(for: mode)
        return resolved
    }
}

public extension PhotoUprightMode {
    /// The stored mode for an analysis pass.
    init(_ mode: UprightMode) {
        switch mode {
        case .auto: self = .auto
        case .level: self = .level
        case .vertical: self = .vertical
        case .full: self = .full
        }
    }
}

/// One straight edge found in the frame, in **normalized** coordinates: x and y
/// in 0…1 with the origin bottom-left, the same convention the geo adjustments
/// are written in.
public struct UprightSegment: Equatable, Sendable {
    public var start: CGPoint
    public var end: CGPoint
    /// How much evidence this line carries — Hough accumulator votes. Long,
    /// well-defined edges outvote short noisy ones rather than being averaged
    /// with them.
    public var weight: Double

    public init(start: CGPoint, end: CGPoint, weight: Double = 1) {
        self.start = start
        self.end = end
        self.weight = weight
    }

    /// Angle from the positive x axis, in radians, folded into −π/2…π/2 — a
    /// line has no direction, so 179° and −1° are the same line.
    public var angle: Double {
        let dx = Double(end.x - start.x)
        let dy = Double(end.y - start.y)
        var angle = atan2(dy, dx)
        if angle > .pi / 2 { angle -= .pi }
        if angle < -.pi / 2 { angle += .pi }
        return angle
    }
}

/// What an Upright pass wants to change, in the same units `PhotoAdjustments`
/// stores: −1…1 for each geo control.
public struct UprightSuggestion: Equatable, Sendable {
    public var rotate: Double
    public var vertical: Double
    public var horizontal: Double

    public init(rotate: Double = 0, vertical: Double = 0, horizontal: Double = 0) {
        self.rotate = rotate
        self.vertical = vertical
        self.horizontal = horizontal
    }

    public var isEmpty: Bool {
        abs(rotate) < 0.001 && abs(vertical) < 0.001 && abs(horizontal) < 0.001
    }

    /// `rotate` in degrees, counter-clockwise positive — what Straighten's
    /// Auto writes into the crop angle (FS-03.13b §3). `applyGeo` turns by
    /// `geoRotate * 0.35` radians.
    public var rotationDegrees: Double {
        rotate * 0.35 * 180 / .pi
    }

    /// The part of the suggestion `mode` may use, as the solved transform a
    /// recipe keeps apart from the Geometry sliders (FS-03.15 D57): those add
    /// on top of it and are never overwritten by it.
    public func transform(for mode: UprightMode) -> PhotoUprightTransform {
        var transform = PhotoUprightTransform.identity
        if mode.correctsRotation { transform.rotate = rotate }
        if mode.correctsKeystone {
            transform.vertical = vertical
            transform.horizontal = horizontal
        }
        return transform
    }
}

/// Finds the rotation and keystone that put a photo's lines back where the eye
/// expects them — Lightroom's Upright.
///
/// Two halves, deliberately separated: a **pure** geometry core that turns a
/// set of line segments into a suggestion (unit-tested, no image needed), and a
/// detector that produces those segments from pixels. The detector is a plain
/// Hough transform over a downscaled gradient rather than Vision, because
/// Vision has no line-segment request — `VNDetectHorizonRequest` answers only
/// the horizon angle, which is half of Level and none of Vertical.
public enum UprightAnalyzer {

    /// The longest side the analysis image is scaled to. 256 is enough for the
    /// angles (a one-degree error at 256px is sub-pixel at 6000px) and keeps a
    /// full Hough pass in a few milliseconds.
    public static let analysisSide = 256

    // MARK: Geometry (pure)

    /// The rotation that levels the frame, as a `geoRotate` value.
    ///
    /// Takes the **median** angle of the near-horizontal and near-vertical
    /// lines, not the mean: one strong diagonal — a staircase, a shadow — would
    /// drag a mean off true, and the whole point is to agree with the majority
    /// of the edges.
    public static func levelRotation(from segments: [UprightSegment]) -> Double {
        clamp(-levelTilt(from: segments) / 0.35)
    }

    /// The frame's tilt in radians, counter-clockwise positive: the weighted
    /// median of how far the near-level and near-upright lines sit off true.
    /// 0 when no line qualifies.
    public static func levelTilt(from segments: [UprightSegment]) -> Double {
        // A vertical line says as much about tilt as a horizontal one, once its
        // angle is measured against the vertical instead.
        var offsets: [(value: Double, weight: Double)] = []
        for segment in segments {
            let angle = segment.angle
            let fromHorizontal = angle
            let fromVertical = angle > 0 ? angle - .pi / 2 : angle + .pi / 2
            let candidate = abs(fromHorizontal) <= abs(fromVertical) ? fromHorizontal : fromVertical
            // Past 20° the line is not a tilted horizon or upright, it is a
            // diagonal that belongs in the picture.
            guard abs(candidate) <= 20 * .pi / 180 else { continue }
            offsets.append((candidate, damped(segment.weight)))
        }
        // `applyGeo` rotates by `geoRotate * 0.35` radians, and the correction
        // runs against the tilt — `levelRotation` does that division.
        return weightedMedian(offsets) ?? 0
    }

    /// `segments` turned by `-tilt` about their own midpoints: the lines as
    /// they would sit once the frame is levelled.
    static func detilted(_ segments: [UprightSegment], by tilt: Double) -> [UprightSegment] {
        guard abs(tilt) > 1e-9 else { return segments }
        let c = cos(-tilt), s = sin(-tilt)
        return segments.map { segment in
            let mid = CGPoint(x: (segment.start.x + segment.end.x) / 2, y: (segment.start.y + segment.end.y) / 2)
            func turn(_ p: CGPoint) -> CGPoint {
                let dx = Double(p.x - mid.x), dy = Double(p.y - mid.y)
                return CGPoint(x: Double(mid.x) + dx * c - dy * s, y: Double(mid.y) + dx * s + dy * c)
            }
            return UprightSegment(start: turn(segment.start), end: turn(segment.end), weight: segment.weight)
        }
    }

    /// Convergence the keystone straightens per unit of `geoVertical`, in
    /// radians of lean on each side: `keystone` moves the corners by
    /// `geoVertical * 0.25` of the width, which undoes about 26° on a frame
    /// this shape.
    public static let convergencePerKeystoneUnit = 26 * Double.pi / 180

    /// The keystone that makes the verticals parallel, as a `geoVertical`
    /// value.
    ///
    /// Measures how much the near-vertical lines on the left lean one way and
    /// the ones on the right lean the other: that difference *is* the
    /// convergence, and it is signed, so a building shot from below (tops
    /// leaning in) and one shot from above come out with opposite corrections.
    public static func verticalKeystone(from segments: [UprightSegment]) -> Double {
        var left: [(value: Double, weight: Double)] = []
        var right: [(value: Double, weight: Double)] = []
        for segment in segments {
            let angle = segment.angle
            let fromVertical = angle > 0 ? angle - .pi / 2 : angle + .pi / 2
            // Only lines that are trying to be vertical: 0.5°…25° off. The
            // floor was 3°, which threw away the spec's own 6° building (3° a
            // side) and any edge the 1°-binned detector read a degree or two
            // short. A side edge that really is near vertical is evidence
            // too — of little convergence on that side.
            let tilt = abs(fromVertical)
            guard tilt > 0.5 * .pi / 180, tilt < 25 * .pi / 180 else { continue }
            let midX = Double(segment.start.x + segment.end.x) / 2
            // The middle third says nothing about convergence — a line through
            // the centre leans the same way whichever side the camera was on.
            if midX < 0.4 {
                left.append((fromVertical, damped(segment.weight)))
            } else if midX > 0.6 {
                right.append((fromVertical, damped(segment.weight)))
            }
        }
        guard let leftLean = weightedMedian(left), let rightLean = weightedMedian(right) else {
            return 0
        }
        // Converging tops: the left line leans right and the right line leans
        // left, so their difference is the signal and their sum is the tilt
        // that Level deals with.
        let convergence = (rightLean - leftLean) / 2
        // `keystone` scales the corner offsets by `geoVertical * 0.25`, and a
        // quarter-width offset corresponds to roughly 26° of convergence on a
        // frame this shape — measured against the transform rather than
        // derived, because the transform is the thing that has to undo it.
        return clamp(convergence / convergencePerKeystoneUnit)
    }

    /// Both halves at once, for the mode the user picked. `horizonTilt` is
    /// Vision's reading when it had one; the lines' own tilt otherwise.
    ///
    /// When the mode also levels, the keystone is read off the lines as they
    /// will sit once levelled: a tilt as large as the lean leaves one edge
    /// dead vertical, where it cannot count, and the keystone would come out
    /// as half of itself or nothing.
    public static func suggestion(
        from segments: [UprightSegment],
        mode: UprightMode,
        horizonTilt: Double? = nil
    ) -> UprightSuggestion {
        var suggestion = UprightSuggestion()
        let tilt = mode.correctsRotation ? (horizonTilt ?? levelTilt(from: segments)) : 0
        if mode.correctsRotation {
            suggestion.rotate = clamp(-tilt / 0.35)
        }
        if mode.correctsKeystone {
            suggestion.vertical = verticalKeystone(from: detilted(segments, by: tilt)) * mode.keystoneShare
        }
        return suggestion
    }

    /// The horizon's tilt from Vision, in radians counter-clockwise, or nil
    /// when Vision finds none, cannot run (the simulator, often), or reads a
    /// tilt past 20° — a diagonal in the picture, not a crooked camera.
    public static func visionHorizonTilt(in image: CIImage) -> Double? {
        let request = VNDetectHorizonRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let horizon = request.results?.first
        else { return nil }
        // Vision's angle runs the other way from this file's: a horizon
        // rising 3° to the right reads −3° (measured on a drawn frame).
        let tilt = -Double(horizon.angle)
        return abs(tilt) <= 20 * .pi / 180 ? tilt : nil
    }

    // MARK: Detection

    /// Straight edges in a greyscale buffer, strongest first.
    ///
    /// `luminance` is row-major, top row first, values 0…1. The Hough
    /// accumulator is quantised to 1° and to 1/180 of the diagonal: finer bins
    /// split one real edge across several cells and make every line look weak.
    public static func segments(
        luminance: [Float],
        width: Int,
        height: Int,
        maximumCount: Int = 64
    ) -> [UprightSegment] {
        guard width > 8, height > 8, luminance.count == width * height else { return [] }

        let angleSteps = 180
        let diagonal = (Double(width) * Double(width) + Double(height) * Double(height)).squareRoot()
        let radiusSteps = 180
        let radiusScale = Double(radiusSteps) / (2 * diagonal)
        var accumulator = [Double](repeating: 0, count: angleSteps * radiusSteps)

        var sines = [Double](repeating: 0, count: angleSteps)
        var cosines = [Double](repeating: 0, count: angleSteps)
        for step in 0..<angleSteps {
            let theta = Double(step) * .pi / Double(angleSteps)
            sines[step] = sin(theta)
            cosines[step] = cos(theta)
        }

        // Sobel magnitude, and the gradient direction with it: voting only in
        // the bins near a pixel's own edge direction is what keeps a 256×256
        // pass fast and the accumulator clean.
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let gx = gradientX(luminance, width: width, x: x, y: y)
                let gy = gradientY(luminance, width: width, x: x, y: y)
                let magnitude = (gx * gx + gy * gy).squareRoot()
                guard magnitude > 0.12 else { continue }

                // The edge runs perpendicular to the gradient; theta is the
                // normal's angle, which is the gradient's own.
                var theta = atan2(gy, gx)
                if theta < 0 { theta += .pi }
                let centre = Int((theta / .pi) * Double(angleSteps)) % angleSteps
                // ±4° of slack absorbs the quantisation of an 8-bit image.
                for offset in -4...4 {
                    let step = (centre + offset + angleSteps) % angleSteps
                    // y is flipped so the accumulator works in the same
                    // bottom-left space the segments are reported in.
                    let flippedY = Double(height - 1 - y)
                    let radius = Double(x) * cosines[step] + flippedY * sines[step]
                    let bin = Int((radius + diagonal) * radiusScale)
                    guard bin >= 0, bin < radiusSteps else { continue }
                    accumulator[step * radiusSteps + bin] += magnitude
                }
            }
        }

        // Peaks, with a small exclusion window so one strong edge does not fill
        // the result with its own neighbours.
        var peaks: [(step: Int, bin: Int, votes: Double)] = []
        let threshold = (accumulator.max() ?? 0) * 0.35
        guard threshold > 0 else { return [] }
        for step in 0..<angleSteps {
            for bin in 0..<radiusSteps {
                let votes = accumulator[step * radiusSteps + bin]
                guard votes >= threshold else { continue }
                if isLocalMaximum(accumulator, angleSteps: angleSteps, radiusSteps: radiusSteps,
                                  step: step, bin: bin, votes: votes) {
                    peaks.append((step, bin, votes))
                }
            }
        }
        peaks.sort { $0.votes > $1.votes }

        var result: [UprightSegment] = []
        for peak in peaks.prefix(maximumCount) {
            let theta = Double(peak.step) * .pi / Double(angleSteps)
            let radius = Double(peak.bin) / radiusScale - diagonal
            guard let segment = segment(
                theta: theta,
                radius: radius,
                width: width,
                height: height,
                weight: peak.votes
            ) else { continue }
            result.append(segment)
        }
        return result
    }

    /// Renders `image` small and grey, then reads its lines. The rendering is
    /// the only part that needs Core Image, so it is the only part that cannot
    /// be unit-tested.
    public static func segments(in image: CIImage, context: CIContext) -> [UprightSegment] {
        let extent = image.extent
        guard extent.width > 1, extent.height > 1 else { return [] }
        let scale = Double(analysisSide) / Double(max(extent.width, extent.height))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let width = max(Int(scaled.extent.width.rounded()), 1)
        let height = max(Int(scaled.extent.height.rounded()), 1)

        var bytes = [UInt8](repeating: 0, count: width * height)
        let space = CGColorSpaceCreateDeviceGray()
        bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            context.render(
                scaled,
                toBitmap: base,
                rowBytes: width,
                bounds: CGRect(x: scaled.extent.origin.x, y: scaled.extent.origin.y,
                               width: CGFloat(width), height: CGFloat(height)),
                format: .L8,
                colorSpace: space
            )
        }
        let luminance = bytes.map { Float($0) / 255 }
        return segments(luminance: luminance, width: width, height: height)
    }

    /// The whole pass: pixels in, geo values out. Nil when the frame has no
    /// usable straight edges — a sky, a close-up of fur — because moving the
    /// photo on no evidence is worse than leaving it alone.
    public static func analyze(
        _ image: CIImage,
        mode: UprightMode,
        context: CIContext
    ) -> UprightSuggestion? {
        let found = segments(in: image, context: context)
        // Level reads the horizon with Vision (FS-03.15b §4); the lines are
        // the fallback, and the only source for the verticals.
        let horizon = mode.correctsRotation ? visionHorizonTilt(in: image) : nil
        guard !found.isEmpty || horizon != nil else { return nil }
        let suggestion = suggestion(from: found, mode: mode, horizonTilt: horizon)
        return suggestion.isEmpty ? nil : suggestion
    }

    // MARK: Pieces

    private static func gradientX(_ pixels: [Float], width: Int, x: Int, y: Int) -> Double {
        func value(_ dx: Int, _ dy: Int) -> Double { Double(pixels[(y + dy) * width + (x + dx)]) }
        return (value(1, -1) + 2 * value(1, 0) + value(1, 1))
            - (value(-1, -1) + 2 * value(-1, 0) + value(-1, 1))
    }

    private static func gradientY(_ pixels: [Float], width: Int, x: Int, y: Int) -> Double {
        func value(_ dx: Int, _ dy: Int) -> Double { Double(pixels[(y + dy) * width + (x + dx)]) }
        // Rows run top-down while the segments are reported bottom-up, so this
        // is negated to keep both in the same space.
        return -((value(-1, 1) + 2 * value(0, 1) + value(1, 1))
            - (value(-1, -1) + 2 * value(0, -1) + value(1, -1)))
    }

    private static func isLocalMaximum(
        _ accumulator: [Double],
        angleSteps: Int,
        radiusSteps: Int,
        step: Int,
        bin: Int,
        votes: Double
    ) -> Bool {
        for dStep in -3...3 {
            for dBin in -3...3 where dStep != 0 || dBin != 0 {
                let s = (step + dStep + angleSteps) % angleSteps
                let b = bin + dBin
                guard b >= 0, b < radiusSteps else { continue }
                if accumulator[s * radiusSteps + b] > votes { return false }
            }
        }
        return true
    }

    /// Where a Hough line (theta, radius) crosses the frame, as a normalized
    /// segment. Nil when the line clips a corner and has nothing inside.
    private static func segment(
        theta: Double,
        radius: Double,
        width: Int,
        height: Int,
        weight: Double
    ) -> UprightSegment? {
        let w = Double(width - 1)
        let h = Double(height - 1)
        let cosT = cos(theta)
        let sinT = sin(theta)
        var points: [CGPoint] = []

        if abs(sinT) > 0.0001 {
            for x in [0.0, w] {
                let y = (radius - x * cosT) / sinT
                if y >= -0.5, y <= h + 0.5 { points.append(CGPoint(x: x / w, y: y / h)) }
            }
        }
        if abs(cosT) > 0.0001 {
            for y in [0.0, h] {
                let x = (radius - y * sinT) / cosT
                if x >= -0.5, x <= w + 0.5 { points.append(CGPoint(x: x / w, y: y / h)) }
            }
        }
        guard points.count >= 2 else { return nil }
        // Two crossings are the ends; a line through a corner reports the same
        // point twice, so take the pair that is furthest apart.
        var best = (a: points[0], b: points[1], distance: -1.0)
        for i in 0..<points.count {
            for j in (i + 1)..<points.count {
                let dx = Double(points[i].x - points[j].x)
                let dy = Double(points[i].y - points[j].y)
                let distance = dx * dx + dy * dy
                if distance > best.distance {
                    best = (points[i], points[j], distance)
                }
            }
        }
        guard best.distance > 0.01 else { return nil }
        return UprightSegment(start: best.a, end: best.b, weight: weight)
    }

    /// Hough votes grow with a line's length and contrast, so one long, hard
    /// edge can carry six times the votes of a shorter one. It is not six
    /// times the evidence about which way the frame is tilted, though — a
    /// staircase is one long line and disagrees with the three window sills
    /// that are right. The square root keeps a strong line ahead of a weak one
    /// while letting a consensus of several outvote it.
    private static func damped(_ weight: Double) -> Double {
        max(weight, 0).squareRoot()
    }

    /// Median by weight: the value where half the evidence sits on each side.
    static func weightedMedian(_ values: [(value: Double, weight: Double)]) -> Double? {
        let usable = values.filter { $0.weight > 0 }
        guard !usable.isEmpty else { return nil }
        let sorted = usable.sorted { $0.value < $1.value }
        let total = sorted.reduce(0) { $0 + $1.weight }
        var running = 0.0
        for entry in sorted {
            running += entry.weight
            if running >= total / 2 { return entry.value }
        }
        return sorted.last?.value
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(-1, value))
    }
}
