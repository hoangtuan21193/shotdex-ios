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

    /// The rotation that levels the frame, as a `geoRotate` value. `aspect`
    /// is the frame's width over its height (see `levelTilt`).
    ///
    /// Takes the **median** angle of the near-horizontal and near-vertical
    /// lines, not the mean: one strong diagonal — a staircase, a shadow — would
    /// drag a mean off true, and the whole point is to agree with the majority
    /// of the edges.
    public static func levelRotation(from segments: [UprightSegment], aspect: Double = 1) -> Double {
        clamp(-levelTilt(from: segments, aspect: aspect) / 0.35)
    }

    /// The frame's tilt in radians, counter-clockwise positive: the weighted
    /// median of how far the near-level and near-upright lines sit off true.
    /// 0 when no line qualifies.
    ///
    /// Angles are read on the picture, not in the normalized space the
    /// segments are written in: `aspect` (width over height) stretches x back
    /// out, because a 3° horizon on a 3:2 frame is 4.5° in that space and a
    /// 3° upright only 2°. And an upright's lean is read with the building's
    /// convergence taken out of it (`keystoneSpread`): shot from the
    /// pavement, the edges on the left lean right and those on the right
    /// lean left, which is perspective, not a crooked camera — left in, the
    /// median lands on one side's lean and Level turns an upright frame by
    /// 1.3° (measured on a drawn 3:2 building with 4° a side, 2026-09-29).
    public static func levelTilt(from segments: [UprightSegment], aspect: Double = 1) -> Double {
        let spread = keystoneSpread(from: segments) ?? 0
        var offsets: [(value: Double, weight: Double)] = []
        for segment in segments {
            let dx = Double(segment.end.x - segment.start.x)
            let dy = Double(segment.end.y - segment.start.y)
            guard dx != 0 || dy != 0 else { continue }
            let candidate: Double
            if abs(dx) * aspect >= abs(dy) {
                // Near level: its angle from the horizontal, on the picture.
                candidate = atan(dy / (dx * aspect))
            } else {
                // Near upright: a counter-clockwise tilt leans the top left.
                let run = dx / dy + spread * centreOffset(of: segment)
                candidate = -atan(run * aspect)
            }
            // Past 20° the line is not a tilted horizon or upright, it is a
            // diagonal that belongs in the picture.
            guard abs(candidate) <= 20 * .pi / 180 else { continue }
            offsets.append((candidate, damped(segment.weight)))
        }
        // `applyGeo` rotates by `geoRotate * 0.35` radians, and the correction
        // runs against the tilt — `levelRotation` does that division.
        return weightedMedian(offsets) ?? 0
    }

    /// Where a segment's line crosses the frame's mid-height, as an offset
    /// from the centre in half-widths: −1 the left edge, 1 the right.
    static func centreOffset(of segment: UprightSegment) -> Double {
        let dx = Double(segment.end.x - segment.start.x)
        let dy = Double(segment.end.y - segment.start.y)
        guard abs(dy) > 1e-9 else { return Double(segment.start.x + segment.end.x) - 1 }
        let x = Double(segment.start.x) + (0.5 - Double(segment.start.y)) * dx / dy
        return 2 * x - 1
    }

    /// How far the keystone has to push the top corners out (and pull the
    /// bottom ones in), as a fraction of the half-width, for the photo's
    /// near-vertical lines to come out parallel. Positive for tops leaning
    /// in — a building shot from below. Nil without evidence on both sides.
    ///
    /// The keystone maps a line that crosses the bottom edge at offset `b`
    /// and the top at `t` (half-widths from the centre) to `b(1 − s)` and
    /// `t(1 + s)`, so it stands upright when `s = (b − t)/(b + t)` — which,
    /// with the line's run `r = dx/dy` in normalized space and its offset `a`
    /// at mid-height, is `s = −r/a`. Every line through one vanishing point
    /// gives the same `s`, while its *lean* grows with its distance from the
    /// centre. That is why this is not an angle times a constant: the old
    /// "26° per unit" read the lean of whichever lines the median landed on
    /// and Full undid only 19–34% of a drawn building's convergence
    /// (FS-03.15b AC-23, measured 2026-09-29). A uniform tilt adds the same run to every line, so the
    /// slope between a line on each side, not either side alone, is the
    /// answer: `s = −(r_right − r_left)/(a_right − a_left)`.
    static func keystoneSpread(from segments: [UprightSegment]) -> Double? {
        var left: [(run: Double, offset: Double, weight: Double)] = []
        var right: [(run: Double, offset: Double, weight: Double)] = []
        for segment in segments {
            let dx = Double(segment.end.x - segment.start.x)
            let dy = Double(segment.end.y - segment.start.y)
            guard abs(dy) > 1e-9 else { continue }
            let run = dx / dy
            // Only lines that are trying to be vertical: within 25°. A side
            // edge that really is vertical is evidence too — of no
            // convergence on that side.
            guard abs(atan(run)) < 25 * .pi / 180 else { continue }
            let offset = centreOffset(of: segment)
            let weight = damped(segment.weight)
            // The middle band says nothing about convergence — a line through
            // the centre leans the same way whichever side the camera was on.
            if offset < -0.2 {
                left.append((run, offset, weight))
            } else if offset > 0.2 {
                right.append((run, offset, weight))
            }
        }
        // Every left–right pair gives its own answer, and the weighted median
        // of those is the estimate: a median of runs and a separate median of
        // offsets can come from different lines and pair one line's lean with
        // another's position.
        var answers: [(value: Double, weight: Double)] = []
        for l in left {
            for r in right {
                answers.append((-(r.run - l.run) / (r.offset - l.offset), l.weight * r.weight))
            }
        }
        return weightedMedian(answers)
    }

    /// The keystone that makes the verticals parallel, as a `geoVertical`
    /// value: `keystoneSpread` over the corner shift one unit of
    /// `geoVertical` makes. Signed, so a building shot from below (tops
    /// leaning in) and one shot from above come out with opposite
    /// corrections.
    public static func verticalKeystone(from segments: [UprightSegment]) -> Double {
        guard let spread = keystoneSpread(from: segments) else { return 0 }
        return clamp(spread / PhotoRenderService.keystoneCornerShift)
    }

    /// Both halves at once, for the mode the user picked. `horizonTilt` is
    /// Vision's reading when it had one; the lines' own tilt otherwise.
    /// `aspect` is the frame's width over its height.
    ///
    /// The keystone needs no levelling first: a tilt leans every line by the
    /// same run, and `keystoneSpread` reads the difference between the sides.
    public static func suggestion(
        from segments: [UprightSegment],
        mode: UprightMode,
        horizonTilt: Double? = nil,
        aspect: Double = 1
    ) -> UprightSuggestion {
        var suggestion = UprightSuggestion()
        if mode.correctsRotation {
            let tilt = horizonTilt ?? levelTilt(from: segments, aspect: aspect)
            suggestion.rotate = clamp(-tilt / 0.35)
        }
        if mode.correctsKeystone {
            suggestion.vertical = verticalKeystone(from: segments) * mode.keystoneShare
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
        var edges: [EdgePixel] = []

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
                edges.append(EdgePixel(x: Double(x), y: Double(height - 1 - y), magnitude: magnitude, step: centre))
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
            var theta = Double(peak.step) * .pi / Double(angleSteps)
            var radius = Double(peak.bin) / radiusScale - diagonal
            if let refined = refinedLine(theta: theta, radius: radius, step: peak.step,
                                         angleSteps: angleSteps, edges: edges) {
                (theta, radius) = refined
            }
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
        let aspect = Double(image.extent.width / image.extent.height)
        let suggestion = suggestion(from: found, mode: mode, horizonTilt: horizon, aspect: aspect)
        return suggestion.isEmpty ? nil : suggestion
    }

    // MARK: Pieces

    /// One pixel over the gradient threshold, in the bottom-up space the
    /// accumulator uses, with the angle bin its gradient points into.
    private struct EdgePixel {
        var x: Double
        var y: Double
        var magnitude: Double
        var step: Int
    }

    /// A Hough peak fitted to the edge pixels that made it: the principal
    /// axis of those within a few pixels of the peak's line whose gradient
    /// agrees with it, weighted by the square of the gradient's strength so
    /// the texture that happens to sit in the band cannot hold the fit to the
    /// peak's own angle. Four passes, each in a band about the last fit:
    /// wide enough (±2.5px) to hold both edges of a thin line whole, since a
    /// band that clips one end holds the fit to the angle it started from —
    /// at ±1.5px the same building's edges still read up to 0.5° short
    /// (5.02° as 4.50°), at ±2.5px within 0.04°.
    ///
    /// The accumulator alone is too coarse for Vertical. Its bins are 1° and
    /// 1/90 of the diagonal (about 3.4px at 256), so a whole family of lines
    /// within a degree of the edge lands in one cell: on a drawn 1200×800
    /// building leaning 4° a side the peaks alone read a quarter of the
    /// convergence away before the keystone ever ran (2026-09-29).
    private static func refinedLine(
        theta: Double,
        radius: Double,
        step: Int,
        angleSteps: Int,
        edges: [EdgePixel]
    ) -> (theta: Double, radius: Double)? {
        var theta = theta, radius = radius
        for band in [3.0, 2.5, 2.5, 2.5] {
            let c = cos(theta), s = sin(theta)
            var weight = 0.0, sumX = 0.0, sumY = 0.0, sumXX = 0.0, sumYY = 0.0, sumXY = 0.0
            var count = 0
            for edge in edges {
                let apart = abs(edge.step - step)
                guard min(apart, angleSteps - apart) <= 8,
                      abs(edge.x * c + edge.y * s - radius) <= band else { continue }
                let strength = edge.magnitude * edge.magnitude
                weight += strength
                sumX += edge.x * strength
                sumY += edge.y * strength
                sumXX += edge.x * edge.x * strength
                sumYY += edge.y * edge.y * strength
                sumXY += edge.x * edge.y * strength
                count += 1
            }
            guard count >= 8, weight > 0 else { return nil }
            let meanX = sumX / weight, meanY = sumY / weight
            let xx = sumXX / weight - meanX * meanX
            let yy = sumYY / weight - meanY * meanY
            let xy = sumXY / weight - meanX * meanY
            // The line runs along the principal axis; theta is its normal.
            var fitted = 0.5 * atan2(2 * xy, xx - yy) + .pi / 2
            if fitted < 0 { fitted += .pi }
            if fitted >= .pi { fitted -= .pi }
            // A fit that swung past the vote's slack found something else.
            var swing = abs(fitted - theta)
            swing = min(swing, .pi - swing)
            guard swing <= 4 * .pi / 180 else { return nil }
            theta = fitted
            radius = meanX * cos(theta) + meanY * sin(theta)
        }
        return (theta, radius)
    }

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
