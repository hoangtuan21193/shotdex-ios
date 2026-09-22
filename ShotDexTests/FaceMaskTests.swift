import CoreGraphics
import Foundation
import Testing
@testable import ShotDex
@testable import ShotDexKit

/// FS-03.11 AC-5 and AC-6 — face-part masks.
///
/// The builder is pure geometry, so these draw a face by hand: a box, two
/// eyes, two brows and a mouth where a frontal portrait would have them.
struct FaceMaskTests {
    private func ring(center: CGPoint, rx: CGFloat, ry: CGFloat, count: Int = 8) -> [CGPoint] {
        (0..<count).map { index in
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi
            return CGPoint(x: center.x + cos(angle) * rx, y: center.y + sin(angle) * ry)
        }
    }

    /// Bottom-left origin: the eyes are *above* the mouth, so larger y.
    private var face: FaceLandmarks {
        FaceLandmarks(
            boundingBox: CGRect(x: 0.3, y: 0.25, width: 0.4, height: 0.45),
            leftEye: ring(center: CGPoint(x: 0.42, y: 0.56), rx: 0.035, ry: 0.015),
            rightEye: ring(center: CGPoint(x: 0.58, y: 0.56), rx: 0.035, ry: 0.015),
            leftEyebrow: [CGPoint(x: 0.38, y: 0.62), CGPoint(x: 0.42, y: 0.635), CGPoint(x: 0.46, y: 0.62)],
            rightEyebrow: [CGPoint(x: 0.54, y: 0.62), CGPoint(x: 0.58, y: 0.635), CGPoint(x: 0.62, y: 0.62)],
            outerLips: ring(center: CGPoint(x: 0.5, y: 0.36), rx: 0.06, ry: 0.025)
        )
    }

    private let size = CGSize(width: 200, height: 200)

    /// Mask value 0…1 at a normalized, bottom-left-origin point.
    private func value(_ image: CGImage, at point: CGPoint) -> Double {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // CGContext memory is top row first; the point is bottom-left origin.
        let x = min(width - 1, Int(point.x * CGFloat(width)))
        let row = min(height - 1, Int((1 - point.y) * CGFloat(height)))
        return Double(pixels[row * width + x]) / 255
    }

    private let cheek = CGPoint(x: 0.40, y: 0.45)
    private let forehead = CGPoint(x: 0.5, y: 0.68)
    private let eye = CGPoint(x: 0.42, y: 0.56)
    private let brow = CGPoint(x: 0.42, y: 0.632)
    private let mouth = CGPoint(x: 0.5, y: 0.36)
    private let outside = CGPoint(x: 0.1, y: 0.1)

    /// AC-5. Skin covers cheek and forehead, and not the eyes, brows or lips.
    @Test func faceSkinCoversSkinOnly() throws {
        let mask = try #require(FaceLandmarkMaskBuilder.mask(.faceSkin, faces: [face], size: size))
        #expect(value(mask, at: cheek) > 0.9)
        #expect(value(mask, at: forehead) > 0.9)
        #expect(value(mask, at: eye) < 0.1)
        #expect(value(mask, at: brow) < 0.1)
        #expect(value(mask, at: mouth) < 0.1)
        #expect(value(mask, at: outside) < 0.1)
    }

    @Test func eyesAndLipsCoverTheirPartOnly() throws {
        let eyes = try #require(FaceLandmarkMaskBuilder.mask(.eyes, faces: [face], size: size))
        #expect(value(eyes, at: eye) > 0.9)
        #expect(value(eyes, at: CGPoint(x: 0.58, y: 0.56)) > 0.9)
        #expect(value(eyes, at: cheek) < 0.1)
        #expect(value(eyes, at: mouth) < 0.1)

        let lips = try #require(FaceLandmarkMaskBuilder.mask(.lips, faces: [face], size: size))
        #expect(value(lips, at: mouth) > 0.9)
        #expect(value(lips, at: eye) < 0.1)
        #expect(value(lips, at: cheek) < 0.1)
    }

    @Test func noFacesMeansAnEmptyMask() throws {
        let mask = try #require(FaceLandmarkMaskBuilder.mask(.faceSkin, faces: [], size: size))
        #expect(value(mask, at: CGPoint(x: 0.5, y: 0.5)) < 0.01)
    }

    /// AC-6. With no face found, the three face rows are greyed out and say
    /// why; while the check is still running they stay live.
    @Test func faceRowsAreGatedOnFaces() {
        let faceOptions: [EditorNewMaskOption] = [.faceSkin, .eyes, .lips]
        for option in faceOptions {
            #expect(option.unavailableReason(hasDepth: true, hasFaces: false) != nil, "\(option)")
            #expect(option.unavailableReason(hasDepth: true, hasFaces: true) == nil)
            #expect(option.unavailableReason(hasDepth: true, hasFaces: nil) == nil)
            #expect(option.componentKind.isFacePart)
        }
        for option in EditorNewMaskOption.allCases where !faceOptions.contains(option) {
            #expect(option.unavailableReason(hasDepth: true, hasFaces: false) == nil, "\(option)")
        }
    }

    /// A face-part mask read back from a saved recipe still decodes.
    @Test func facePartKindsRoundTrip() throws {
        for kind in [PhotoMaskComponentKind.faceSkin, .eyes, .lips] {
            let mask = PhotoMask(name: kind.displayName, component: PhotoMaskComponent(kind: kind))
            let decoded = try JSONDecoder().decode(PhotoMask.self, from: JSONEncoder().encode(mask))
            #expect(decoded.components.map(\.kind) == [kind])
        }
    }
}
