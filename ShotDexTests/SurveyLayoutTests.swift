import CoreGraphics
import Testing
@testable import ShotDex

/// How many columns a survey uses. The rule is "whichever fits the biggest
/// tile", so the tests are about area, not about taste.
struct SurveyLayoutTests {

    /// One photo is not a grid.
    @Test func onePhotoIsOneColumn() {
        #expect(
            SurveyLayout.columns(
                count: 1,
                canvas: CGSize(width: 1200, height: 800),
                aspectRatio: 1.5
            ) == 1
        )
    }

    /// Two landscape frames on a landscape iPad stack, because halving the
    /// width of a 3:2 frame costs more than halving the height it was not
    /// using — the same answer the reference pane gives.
    @Test func twoLandscapeFramesStackOnALandscapeCanvas() {
        #expect(
            SurveyLayout.columns(
                count: 2,
                canvas: CGSize(width: 1300, height: 900),
                aspectRatio: 3.0 / 2.0
            ) == 1
        )
    }

    /// Nine landscape frames on a wide canvas land on the square-ish grid.
    @Test func nineFramesOnAWideCanvasGoThreeAcross() {
        #expect(
            SurveyLayout.columns(
                count: 9,
                canvas: CGSize(width: 1300, height: 900),
                aspectRatio: 3.0 / 2.0
            ) == 3
        )
    }

    /// The same nine on a phone cannot go three across — a tile would be 120pt
    /// wide — so the layout goes tall and narrow instead.
    @Test func aPhoneTakesFewerColumnsForTheSamePhotos() {
        let columns = SurveyLayout.columns(
            count: 9,
            canvas: CGSize(width: 390, height: 780),
            aspectRatio: 3.0 / 2.0
        )
        #expect(columns <= 2)
    }

    /// The property the rule exists for: whatever it picks is genuinely the
    /// biggest tile available, checked against the area function directly.
    @Test func theChosenColumnCountIsNeverTheSmallerTile() {
        let canvases = [
            CGSize(width: 1300, height: 900),
            CGSize(width: 390, height: 780),
            CGSize(width: 1000, height: 1000),
            CGSize(width: 744, height: 1133),
        ]
        let aspects: [CGFloat] = [3.0 / 2.0, 2.0 / 3.0, 1, 16.0 / 9.0]

        for canvas in canvases {
            for aspect in aspects {
                for count in 2...12 {
                    let chosen = SurveyLayout.columns(
                        count: count,
                        canvas: canvas,
                        aspectRatio: aspect
                    )
                    let chosenArea = SurveyLayout.tileArea(
                        count: count,
                        columns: chosen,
                        canvas: canvas,
                        aspectRatio: aspect
                    )
                    let best = (1...count).map {
                        SurveyLayout.tileArea(
                            count: count,
                            columns: $0,
                            canvas: canvas,
                            aspectRatio: aspect
                        )
                    }.max() ?? 0
                    #expect(chosenArea >= best - 0.001, "\(count) photos in \(canvas) at \(aspect)")
                }
            }
        }
    }

    /// Spacing is not noise at tile sizes: twelve frames on a phone lose a
    /// third of the width to gaps, and ignoring them picks a column count that
    /// then does not fit.
    @Test func spacingChangesTheAnswer() {
        let canvas = CGSize(width: 400, height: 300)
        let tight = SurveyLayout.columns(count: 6, canvas: canvas, aspectRatio: 1, spacing: 0)
        let loose = SurveyLayout.columns(count: 6, canvas: canvas, aspectRatio: 1, spacing: 40)
        #expect(loose <= tight)
    }

    @Test func rowsCoverEveryPhoto() {
        #expect(SurveyLayout.rows(count: 9, columns: 3) == 3)
        #expect(SurveyLayout.rows(count: 10, columns: 3) == 4)
        #expect(SurveyLayout.rows(count: 1, columns: 3) == 1)
        #expect(SurveyLayout.rows(count: 0, columns: 3) == 0)
    }

    @Test func degenerateInputsFallBackRatherThanDivideByZero() {
        #expect(SurveyLayout.columns(count: 6, canvas: .zero, aspectRatio: 1.5) == 1)
        #expect(
            SurveyLayout.columns(
                count: 6,
                canvas: CGSize(width: 800, height: 600),
                aspectRatio: 0
            ) == 1
        )
        #expect(SurveyLayout.tileArea(count: 0, columns: 2, canvas: .zero, aspectRatio: 1) == 0)
    }

    /// A survey of eight landscapes and one portrait is a landscape survey.
    @Test func theAverageAspectFollowsTheMajority() {
        let ratios: [CGFloat] = Array(repeating: 1.5, count: 8) + [2.0 / 3.0]
        #expect(SurveyLayout.averageAspectRatio(ratios) > 1.3)
        #expect(SurveyLayout.averageAspectRatio([]) == 1)
        #expect(SurveyLayout.averageAspectRatio([0, 0]) == 1)
    }
}
