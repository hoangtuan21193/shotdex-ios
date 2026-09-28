import CoreGraphics
import CoreImage
import Foundation
import Vision

/// Where a Red Eye tap lands (FS-03.15c §4): on the pupil Vision found near
/// the finger, sized by that eye's width, or — no face, no pupil near, or
/// Vision failing — exactly where the finger was, at a default size.
public enum RedEyeLocator {

    /// One pupil, in the photo's 0…1 top-left space; `eyeWidth` as a
    /// fraction of the frame's short edge.
    public struct Pupil: Equatable, Sendable {
        public var center: NormalizedPoint
        public var eyeWidth: Double

        public init(center: NormalizedPoint, eyeWidth: Double) {
            self.center = center
            self.eyeWidth = eyeWidth
        }
    }

    /// 1% of the short edge: the spot a tap makes with nothing to snap to.
    public static let defaultRadius = 0.01

    /// A spot for a tap at `point` given the pupils found. `aspect` is the
    /// photo's width over its height.
    public static func spot(forTapAt point: NormalizedPoint, pupils: [Pupil], aspect: Double) -> PhotoRedEyeSpot {
        let shortOverWidth = aspect >= 1 ? 1 / aspect : 1
        let shortOverHeight = aspect >= 1 ? 1 : aspect
        func distance(_ pupil: Pupil) -> Double {
            let dx = (pupil.center.x - point.x) / shortOverWidth
            let dy = (pupil.center.y - point.y) / shortOverHeight
            return (dx * dx + dy * dy).squareRoot()
        }
        if let nearest = pupils.min(by: { distance($0) < distance($1) }),
           distance(nearest) <= defaultRadius * 3 {
            // The circle takes in the eye; Pupil Size (default half) is the
            // part that is fixed.
            return PhotoRedEyeSpot(center: nearest.center, radius: max(defaultRadius, nearest.eyeWidth * 0.45))
        }
        return PhotoRedEyeSpot(center: point, radius: defaultRadius)
    }

    /// Every pupil Vision finds in `image`. Empty when there is no face or
    /// Vision cannot run — the caller falls back to the tap, never to an
    /// alert.
    public static func pupils(in image: CGImage) -> [Pupil] {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil, let faces = request.results else { return [] }
        let width = Double(image.width), height = Double(image.height)
        let shortEdge = min(width, height)
        var found: [Pupil] = []
        for face in faces {
            guard let landmarks = face.landmarks else { continue }
            let box = face.boundingBox
            func toPhoto(_ p: CGPoint) -> NormalizedPoint {
                // Landmark points are 0…1 inside the face box, bottom-left.
                let x = Double(box.minX + p.x * box.width), y = Double(box.minY + p.y * box.height)
                return NormalizedPoint(x: x, y: 1 - y)
            }
            for (pupil, eye) in [(landmarks.leftPupil, landmarks.leftEye), (landmarks.rightPupil, landmarks.rightEye)] {
                guard let point = pupil?.normalizedPoints.first else { continue }
                var eyeWidth = 0.0
                if let eyePoints = eye?.normalizedPoints, let minX = eyePoints.map(\.x).min(),
                   let maxX = eyePoints.map(\.x).max() {
                    eyeWidth = Double(maxX - minX) * Double(box.width) * width / shortEdge
                }
                found.append(Pupil(center: toPhoto(point), eyeWidth: eyeWidth))
            }
        }
        return found
    }
}
