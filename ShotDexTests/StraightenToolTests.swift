import CoreGraphics
import Photos
import Testing
@testable import ShotDex

struct StraightenToolTests {
    /// FS-03.13 AC-22. A ruler from (60, 300) to (340, 318) sits 3.7° below
    /// level on its right: the photo turns 3.7° back. Drawn the other way it
    /// is the same line.
    @Test func aLineAtThreeDegreesLevelsThePhoto() throws {
        let correction = try #require(StraightenToolMath.correction(from: CGPoint(x: 60, y: 300), to: CGPoint(x: 340, y: 318)))
        #expect(abs(correction - atan(18.0 / 280) * 180 / .pi) < 0.0001)
        #expect(abs(correction - 3.7) < 0.1)
        let reversed = try #require(StraightenToolMath.correction(from: CGPoint(x: 340, y: 318), to: CGPoint(x: 60, y: 300)))
        #expect(abs(reversed - correction) < 0.0001)
    }

    /// FS-03.13 AC-22. More than 45° off level is a vertical: (200, 100) to
    /// (220, 400) leans 3.8° with its top to the left, so the photo turns
    /// 3.8° clockwise — a negative angle — to stand it up.
    @Test func aNearVerticalLineStandsUp() throws {
        let correction = try #require(StraightenToolMath.correction(from: CGPoint(x: 200, y: 100), to: CGPoint(x: 220, y: 400)))
        #expect(abs(correction + atan(20.0 / 300) * 180 / .pi) < 0.0001)
        #expect(abs(abs(correction) - 3.8) < 0.1)
    }

    /// A 6pt drag is a tap: no angle. At 2× zoom 4 stage points are 8 on
    /// screen, which is a ruler.
    @Test func aShortDragIsATap() {
        #expect(StraightenToolMath.correction(from: .zero, to: CGPoint(x: 6, y: 0)) == nil)
        #expect(StraightenToolMath.correction(from: .zero, to: CGPoint(x: 4, y: 0.2), zoom: 2) != nil)
    }

    /// The result stays inside Straighten's ±45°.
    @Test func theAngleStaysWithinFortyFive() {
        #expect(StraightenToolMath.angle(current: 40, adding: 10) == 45)
        #expect(StraightenToolMath.angle(current: -40, adding: -10) == -45)
        #expect(StraightenToolMath.angle(current: 2, adding: 3.5) == 5.5)
    }

    /// Lifting the ruler is one history step, and Undo puts 0° back.
    @MainActor @Test func aRulerIsOneStep() throws {
        let c = PhotoEditorController(asset: PHAsset(), sourceAlbum: nil, service: PhotoEditingService())
        let depth = c.historyTimeline.count
        let correction = try #require(StraightenToolMath.correction(from: CGPoint(x: 60, y: 300), to: CGPoint(x: 340, y: 318)))
        c.straighten(byRuler: correction)
        #expect(abs(c.recipe.crop.straightenDegrees - 3.68) < 0.01)
        #expect(c.historyTimeline.count == depth + 1)
        c.undo()
        #expect(c.recipe.crop.straightenDegrees == 0)
    }
}
