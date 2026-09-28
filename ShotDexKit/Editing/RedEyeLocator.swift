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

    /// The pupils that really are red (FS-03.15c §5): the same red-dominant
    /// test the kernel uses, averaged over the middle of the pupil. Fixing a
    /// dark brown pupil would only darken it more, wrongly.
    public static func redPupils(_ pupils: [Pupil], in picture: HealingSourceFinder.Picture) -> [Pupil] {
        let shortEdge = Double(min(picture.width, picture.height))
        return pupils.filter { pupil in
            let radius = max(1.5, pupil.eyeWidth * 0.45 * 0.5 * 0.6 * shortEdge)
            let cx = pupil.center.x * Double(picture.width), cy = pupil.center.y * Double(picture.height)
            var redness = 0.0, count = 0.0
            let minX = max(0, Int(cx - radius)), maxX = min(picture.width - 1, Int(cx + radius))
            let minY = max(0, Int(cy - radius)), maxY = min(picture.height - 1, Int(cy + radius))
            guard minX <= maxX, minY <= maxY else { return false }
            for y in minY...maxY {
                for x in minX...maxX where hypot(Double(x) + 0.5 - cx, Double(y) + 0.5 - cy) <= radius {
                    let index = (y * picture.width + x) * 3
                    let r = Double(picture.rgb[index]), g = Double(picture.rgb[index + 1]), b = Double(picture.rgb[index + 2])
                    redness += r - max(g, b)
                    count += 1
                }
            }
            return count > 0 && redness / count > 0.16
        }
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
