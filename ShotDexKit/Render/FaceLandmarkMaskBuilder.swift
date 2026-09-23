import CoreGraphics
import Foundation

/// One face's landmark geometry, in normalized image coordinates with the
/// origin at the **bottom left** — Vision's convention, and Core Image's, so
/// nothing flips between the request and the mask.
public struct FaceLandmarks: Equatable, Sendable {
    public var boundingBox: CGRect
    public var leftEye: [CGPoint]
    public var rightEye: [CGPoint]
    public var leftEyebrow: [CGPoint]
    public var rightEyebrow: [CGPoint]
    public var outerLips: [CGPoint]
    /// The jaw line, ear to chin to ear. Empty when Vision gave none.
    public var faceContour: [CGPoint]

    public init(
        boundingBox: CGRect,
        leftEye: [CGPoint],
        rightEye: [CGPoint],
        leftEyebrow: [CGPoint],
        rightEyebrow: [CGPoint],
        outerLips: [CGPoint],
        faceContour: [CGPoint] = []
    ) {
        self.boundingBox = boundingBox
        self.leftEye = leftEye
        self.rightEye = rightEye
        self.leftEyebrow = leftEyebrow
        self.rightEyebrow = rightEyebrow
        self.outerLips = outerLips
        self.faceContour = faceContour
    }
}

/// Rasterizes the three face-part masks from landmark polygons.
///
/// Pure geometry, no Vision: the renderer asks Vision for the polygons and
/// hands them here, so what each mask covers can be tested on a face drawn by
/// hand. Hard-edged; the renderer feathers.
///
/// - **Face Skin** is the jaw line closed across the face, with a half
///   ellipse on top for the forehead Vision's box stops short of, **minus** the
///   eyes, the brows and the lips — the parts a skin smoothing must not touch.
///   (An ellipse over the whole box, the first version, spilled past the
///   cheeks onto the background.) Without a jaw line it falls back to that
///   ellipse.
/// - **Eyes** are the two eye polygons grown about their centres, so the lids
///   and the whites' edge come with them.
/// - **Lips** is the outer lip polygon, grown slightly.
///
/// Hair, teeth and clothes are not offered: Vision has no parts segmentation
/// for them (FS-03.11 §3).
public enum FaceLandmarkMaskBuilder {
    /// How much the eye polygons grow about their centre.
    static let eyeGrowth: CGFloat = 1.6
    static let lipGrowth: CGFloat = 1.12
    /// The face box stops at the brows; skin continues up the forehead.
    static let foreheadLift: CGFloat = 0.18

    public static func mask(
        _ kind: PhotoMaskComponentKind,
        faces: [FaceLandmarks],
        size: CGSize
    ) -> CGImage? {
        let width = max(1, Int(size.width.rounded(.up)))
        let height = max(1, Int(size.height.rounded(.up)))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        func pixel(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * size.width, y: point.y * size.height)
        }

        for face in faces {
            let box = CGRect(
                x: face.boundingBox.minX * size.width,
                y: face.boundingBox.minY * size.height,
                width: face.boundingBox.width * size.width,
                height: face.boundingBox.height * size.height
            )
            switch kind {
            case .faceSkin:
                context.setFillColor(gray: 1, alpha: 1)
                let contour = face.faceContour.map(pixel)
                if contour.count >= 5, let first = contour.first, let last = contour.last {
                    fill(contour, in: context)
                    // Forehead: the upper half of an ellipse spanning the two
                    // ends of the jaw line, reaching the lifted top of the box.
                    let center = CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2)
                    let radiusX = abs(last.x - first.x) / 2
                    let top = box.maxY + box.height * foreheadLift
                    let radiusY = max(1, top - center.y)
                    context.saveGState()
                    // Starts a few pixels below the jaw line's ends so the two
                    // shapes overlap: butted edge to edge, antialiasing left a
                    // hairline seam across the cheeks.
                    let overlap = max(2, box.height * 0.01)
                    context.clip(to: CGRect(
                        x: center.x - radiusX, y: center.y - overlap,
                        width: radiusX * 2, height: radiusY + overlap
                    ))
                    context.fillEllipse(in: CGRect(
                        x: center.x - radiusX, y: center.y - radiusY,
                        width: radiusX * 2, height: radiusY * 2
                    ))
                    context.restoreGState()
                } else {
                    context.fillEllipse(in: CGRect(
                        x: box.minX,
                        y: box.minY,
                        width: box.width,
                        height: box.height * (1 + foreheadLift)
                    ))
                }
                context.setFillColor(gray: 0, alpha: 1)
                fill(grown(face.leftEye.map(pixel), by: eyeGrowth), in: context)
                fill(grown(face.rightEye.map(pixel), by: eyeGrowth), in: context)
                fill(grown(face.outerLips.map(pixel), by: lipGrowth), in: context)
                // Brows are open curves, so they are stroked, at a width that
                // scales with the face.
                context.setStrokeColor(gray: 0, alpha: 1)
                context.setLineWidth(max(2, box.width * 0.06))
                context.setLineCap(.round)
                context.setLineJoin(.round)
                stroke(face.leftEyebrow.map(pixel), in: context)
                stroke(face.rightEyebrow.map(pixel), in: context)
            case .eyes:
                context.setFillColor(gray: 1, alpha: 1)
                fill(grown(face.leftEye.map(pixel), by: eyeGrowth), in: context)
                fill(grown(face.rightEye.map(pixel), by: eyeGrowth), in: context)
            case .lips:
                context.setFillColor(gray: 1, alpha: 1)
                fill(grown(face.outerLips.map(pixel), by: lipGrowth), in: context)
            default:
                return nil
            }
        }
        return context.makeImage()
    }

    /// `points` scaled about their centroid.
    static func grown(_ points: [CGPoint], by factor: CGFloat) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        let count = CGFloat(points.count)
        let center = CGPoint(
            x: points.reduce(0) { $0 + $1.x } / count,
            y: points.reduce(0) { $0 + $1.y } / count
        )
        return points.map {
            CGPoint(
                x: center.x + ($0.x - center.x) * factor,
                y: center.y + ($0.y - center.y) * factor
            )
        }
    }

    private static func fill(_ points: [CGPoint], in context: CGContext) {
        guard points.count >= 3 else { return }
        context.beginPath()
        context.addLines(between: points)
        context.closePath()
        context.fillPath()
    }

    private static func stroke(_ points: [CGPoint], in context: CGContext) {
        guard points.count >= 2 else { return }
        context.beginPath()
        context.addLines(between: points)
        context.strokePath()
    }
}
