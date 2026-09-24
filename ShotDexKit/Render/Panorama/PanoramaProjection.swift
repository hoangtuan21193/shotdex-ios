import Foundation

/// How the sphere of directions the camera swept is flattened into a picture.
public enum PanoramaProjectionKind: String, CaseIterable, Sendable {
    /// Equirectangular. Works for anything, including a full circle, at the
    /// cost of bending straight lines away from the centre.
    case spherical
    /// Keeps verticals vertical, which is what a row of buildings wants, but
    /// stretches towards the top and bottom and cannot take a tall sweep.
    case cylindrical
    /// A single flat photograph. Only possible across a narrow sweep; past
    /// that the edges run to infinity.
    case perspective
}

/// Why a projection cannot be built for a particular set of frames.
///
/// A reason code rather than a sentence: the sentence is user-visible copy and
/// belongs in the app, where it can be translated (FS-14.01 §3).
public enum PanoramaProjectionUnavailableReason: Sendable, Equatable {
    /// The sweep covers too much sky and ground for this projection.
    case verticalSweepTooWide(degrees: Double)
    /// The sweep covers too much left-to-right.
    case horizontalSweepTooWide(degrees: Double)
}

/// Where a projection stands for one particular set of frames.
public struct PanoramaProjectionAvailability: Sendable, Equatable {
    public var kind: PanoramaProjectionKind
    public var reason: PanoramaProjectionUnavailableReason?
    public var isAvailable: Bool { reason == nil }
}

/// The flattened picture's geometry: how big it is, and where each direction
/// lands on it.
public struct PanoramaCanvas: Sendable {
    public var kind: PanoramaProjectionKind
    public var width: Int
    public var height: Int
    /// Pixels per radian for the curved projections, pinhole focal length for
    /// the flat one.
    public var focal: Double
    /// Applied to a world direction before projecting.
    ///
    /// This is what makes a **vertical** panorama work: projected about the
    /// usual axis a column of frames comes out as an hourglass covering 59% of
    /// its own bounding box, and turned on its side it covers 93% (spike §2.4).
    public var frame: [Double]
    public var originU: Double
    public var originV: Double

    public init(
        kind: PanoramaProjectionKind,
        width: Int,
        height: Int,
        focal: Double,
        frame: [Double],
        originU: Double,
        originV: Double
    ) {
        self.kind = kind
        self.width = width
        self.height = height
        self.focal = focal
        self.frame = frame
        self.originU = originU
        self.originV = originV
    }

    /// Where a direction in the panorama's world frame lands, in canvas pixels.
    public func project(_ direction: (Double, Double, Double)) -> (x: Double, y: Double)? {
        let d = PanoramaRotation.apply(frame, to: direction)
        guard let uv = PanoramaProjection.project(d, kind: kind, focal: focal) else { return nil }
        return (uv.u - originU, uv.v - originV)
    }

    /// The same canvas at a fraction of the size.
    ///
    /// Every number in a canvas is in pixels — the focal length, the origin,
    /// the extent — so a smaller copy is one multiplication each. Rebuilding
    /// it from the cameras instead would apply `scale` to the *full* canvas
    /// rather than to this one, which is the difference between a small copy
    /// of a preview and something three times bigger than it.
    public func scaled(by factor: Double) -> PanoramaCanvas? {
        guard factor > 0, factor <= 1 else { return nil }
        let scaledWidth = Int((Double(width) * factor).rounded())
        let scaledHeight = Int((Double(height) * factor).rounded())
        guard scaledWidth > 1, scaledHeight > 1 else { return nil }
        return PanoramaCanvas(
            kind: kind,
            width: scaledWidth,
            height: scaledHeight,
            focal: focal * factor,
            frame: frame,
            originU: originU * factor,
            originV: originV * factor
        )
    }

    /// The direction a canvas pixel looks in — the question the renderer asks
    /// for every output pixel.
    public func direction(atX x: Double, y: Double) -> (Double, Double, Double)? {
        guard let d = PanoramaProjection.unproject(
            u: x + originU, v: y + originV, kind: kind, focal: focal
        ) else { return nil }
        return PanoramaRotation.apply(PanoramaRotation.transposed(frame), to: d)
    }
}

/// The projections themselves, and the rules for when each can be built.
public enum PanoramaProjection {

    /// Cylindrical runs out past this much sweep up and down: the projection
    /// divides by the horizontal distance, so a ray approaching straight up
    /// runs away to infinity (spike §2.4 measured the practical limit).
    public static let cylindricalVerticalLimit = 71.0
    /// Perspective runs out here. Past it the corners of the picture are
    /// further from the centre than the projection can place them, which is
    /// the same wall Lightroom's Perspective option hits.
    public static let perspectiveAngularLimit = 78.0

    // MARK: The maps

    public static func project(
        _ d: (Double, Double, Double),
        kind: PanoramaProjectionKind,
        focal: Double
    ) -> (u: Double, v: Double)? {
        switch kind {
        case .spherical:
            let horizontal = (d.0 * d.0 + d.2 * d.2).squareRoot()
            guard horizontal > 1e-12 || abs(d.1) > 1e-12 else { return nil }
            return (focal * Foundation.atan2(d.0, d.2), focal * Foundation.atan2(d.1, horizontal))
        case .cylindrical:
            let horizontal = (d.0 * d.0 + d.2 * d.2).squareRoot()
            guard horizontal > 1e-9 else { return nil }
            return (focal * Foundation.atan2(d.0, d.2), focal * d.1 / horizontal)
        case .perspective:
            guard d.2 > 1e-9 else { return nil }
            return (focal * d.0 / d.2, focal * d.1 / d.2)
        }
    }

    public static func unproject(
        u: Double,
        v: Double,
        kind: PanoramaProjectionKind,
        focal: Double
    ) -> (Double, Double, Double)? {
        guard focal > 0 else { return nil }
        switch kind {
        case .spherical:
            let theta = u / focal, phi = v / focal
            let c = Foundation.cos(phi)
            return (c * Foundation.sin(theta), Foundation.sin(phi), c * Foundation.cos(theta))
        case .cylindrical:
            let theta = u / focal
            return (Foundation.sin(theta), v / focal, Foundation.cos(theta))
        case .perspective:
            return (u / focal, v / focal, 1)
        }
    }

    // MARK: What the frames can support

    /// A ray through each corner and edge midpoint of every frame: enough to
    /// bound the sweep without walking whole images.
    static func boundaryDirections(
        cameras: [PanoramaCamera],
        focal: Double,
        imageWidth: Int,
        imageHeight: Int
    ) -> [(Double, Double, Double)] {
        let centreX = Double(imageWidth) / 2, centreY = Double(imageHeight) / 2
        var samples: [(Double, Double)] = []
        for row in 0...4 {
            for column in 0...4 where row == 0 || row == 4 || column == 0 || column == 4 {
                samples.append(
                    (
                        Double(column) / 4 * Double(imageWidth),
                        Double(row) / 4 * Double(imageHeight)
                    )
                )
            }
        }
        var directions: [(Double, Double, Double)] = []
        for camera in cameras {
            for point in samples {
                let ray = ((point.0 - centreX) / focal, (point.1 - centreY) / focal, 1.0)
                let length = (ray.0 * ray.0 + ray.1 * ray.1 + ray.2 * ray.2).squareRoot()
                let unit = (ray.0 / length, ray.1 / length, ray.2 / length)
                directions.append(PanoramaRotation.apply(PanoramaRotation.transposed(camera.rotation), to: unit))
            }
        }
        return directions
    }

    /// Which projections this set of frames can be built with, and why not
    /// where not.
    public static func availability(
        cameras: [PanoramaCamera],
        focal: Double,
        imageWidth: Int,
        imageHeight: Int
    ) -> [PanoramaProjectionAvailability] {
        let directions = boundaryDirections(
            cameras: cameras, focal: focal, imageWidth: imageWidth, imageHeight: imageHeight
        )
        guard !directions.isEmpty else {
            return PanoramaProjectionKind.allCases.map {
                PanoramaProjectionAvailability(kind: $0, reason: nil)
            }
        }

        var maximumVertical = 0.0
        var maximumFromCentre = 0.0
        var sumX = 0.0, sumY = 0.0, sumZ = 0.0
        for d in directions {
            sumX += d.0
            sumY += d.1
            sumZ += d.2
            let horizontal = (d.0 * d.0 + d.2 * d.2).squareRoot()
            maximumVertical = max(maximumVertical, abs(Foundation.atan2(d.1, horizontal)))
        }
        let centreLength = (sumX * sumX + sumY * sumY + sumZ * sumZ).squareRoot()
        let centre = centreLength > 1e-9
            ? (sumX / centreLength, sumY / centreLength, sumZ / centreLength)
            : (0.0, 0.0, 1.0)
        for d in directions {
            let dot = min(1, max(-1, d.0 * centre.0 + d.1 * centre.1 + d.2 * centre.2))
            maximumFromCentre = max(maximumFromCentre, Foundation.acos(dot))
        }

        let verticalDegrees = maximumVertical * 180 / .pi
        let fromCentreDegrees = maximumFromCentre * 180 / .pi

        return PanoramaProjectionKind.allCases.map { kind in
            switch kind {
            case .spherical:
                // Nothing to rule out: a sphere holds every direction there is,
                // which is why it is the one that always works.
                return PanoramaProjectionAvailability(kind: kind, reason: nil)
            case .cylindrical:
                return PanoramaProjectionAvailability(
                    kind: kind,
                    reason: verticalDegrees > cylindricalVerticalLimit
                        ? .verticalSweepTooWide(degrees: verticalDegrees * 2)
                        : nil
                )
            case .perspective:
                return PanoramaProjectionAvailability(
                    kind: kind,
                    reason: fromCentreDegrees > perspectiveAngularLimit
                        ? .horizontalSweepTooWide(degrees: fromCentreDegrees * 2)
                        : nil
                )
            }
        }
    }

    // MARK: Laying out the canvas

    /// Works out how big the flattened picture is and where its origin sits.
    ///
    /// `scale` is the Size control, 0.25…1 of the frames' own resolution. It is
    /// applied here, to the canvas, rather than by shrinking a finished
    /// panorama: rendering a quarter-size picture costs about a sixteenth of
    /// rendering a full one, and rendering the full one first to throw most of
    /// it away is the difference between a minute and twenty seconds.
    public static func canvas(
        kind: PanoramaProjectionKind,
        cameras: [PanoramaCamera],
        focal: Double,
        imageWidth: Int,
        imageHeight: Int,
        scale: Double = 1
    ) -> PanoramaCanvas? {
        guard focal > 0, scale > 0, !cameras.isEmpty else { return nil }
        let directions = boundaryDirections(
            cameras: cameras, focal: focal, imageWidth: imageWidth, imageHeight: imageHeight
        )
        guard !directions.isEmpty else { return nil }

        let frame = projectionFrame(for: directions, kind: kind)
        let canvasFocal = focal * scale

        var minU = Double.infinity, maxU = -Double.infinity
        var minV = Double.infinity, maxV = -Double.infinity
        for direction in directions {
            let turned = PanoramaRotation.apply(frame, to: direction)
            guard let uv = project(turned, kind: kind, focal: canvasFocal) else { return nil }
            minU = min(minU, uv.u); maxU = max(maxU, uv.u)
            minV = min(minV, uv.v); maxV = max(maxV, uv.v)
        }
        guard minU.isFinite, maxU.isFinite, minV.isFinite, maxV.isFinite else { return nil }

        let width = Int((maxU - minU).rounded(.up))
        let height = Int((maxV - minV).rounded(.up))
        guard width > 0, height > 0 else { return nil }
        return PanoramaCanvas(
            kind: kind,
            width: width,
            height: height,
            focal: canvasFocal,
            frame: frame,
            originU: minU,
            originV: minV
        )
    }

    /// The axis the projection is built around.
    ///
    /// Usually the world's own: the sweep runs left to right and the y-axis is
    /// up. A **column** of frames is the case that needs turning — projected
    /// the usual way it comes out pinched in the middle like an hourglass,
    /// because the projection stretches hardest exactly where the pictures are.
    /// Turning the axis ninety degrees puts the sweep along the projection's
    /// generous direction, and the result is stood back up at render time.
    static func projectionFrame(
        for directions: [(Double, Double, Double)],
        kind: PanoramaProjectionKind
    ) -> [Double] {
        // Perspective has no axis to turn: it is a flat picture either way.
        guard kind != .perspective else { return PanoramaRotation.identity }
        var horizontal = 0.0, vertical = 0.0
        var minYaw = Double.infinity, maxYaw = -Double.infinity
        var minPitch = Double.infinity, maxPitch = -Double.infinity
        for d in directions {
            let yaw = Foundation.atan2(d.0, d.2)
            let pitch = Foundation.atan2(d.1, (d.0 * d.0 + d.2 * d.2).squareRoot())
            minYaw = min(minYaw, yaw); maxYaw = max(maxYaw, yaw)
            minPitch = min(minPitch, pitch); maxPitch = max(maxPitch, pitch)
        }
        horizontal = maxYaw - minYaw
        vertical = maxPitch - minPitch
        guard vertical > horizontal else { return PanoramaRotation.identity }
        // A quarter turn about the viewing direction: the tall sweep becomes a
        // wide one, and the canvas is rotated back when the picture is saved.
        return PanoramaRotation.matrix(fromAxisAngle: (0, 0, .pi / 2))
    }
}
