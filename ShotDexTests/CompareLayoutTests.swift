import CoreGraphics
import Testing
@testable import ShotDex

/// Compare's frame sizes against the boards (FS-01.08c §2, §4): stage areas
/// are the boards' — the space between the top bar and the bottom bar.
struct CompareLayoutTests {

    private func close(_ a: CGFloat, _ b: CGFloat, within tolerance: CGFloat = 1) -> Bool {
        abs(a - b) <= tolerance
    }

    /// `PH_Compare`: stage 402 × 600 → two 370 × 294 frames, photo 226 tall.
    @Test func phoneStacksTwo370x294() {
        let frame = CompareLayout.stacked(area: CGSize(width: 402, height: 600), metrics: .cullRow)
        #expect(frame.size == CGSize(width: 370, height: 294))
        #expect(frame.photo.height == 226)
    }

    /// `DC_Compare`: 382 beside the 84pt rail → 350 × 224, everything left
    /// of x = 366.
    @Test func coverKeepsEverythingLeftOf366() {
        let frame = CompareLayout.stacked(area: CGSize(width: 382, height: 456), metrics: .cover)
        #expect(frame.size == CGSize(width: 350, height: 224))
        #expect(CompareLayout.margin + frame.size.width <= 366)
        #expect(frame.photo.height == 176)
    }

    /// `IP_Compare`: 1376 × 832 → two 664 × 832 frames.
    @Test func iPadTwoUpFramesAre664x832() {
        let frame = CompareLayout.twoUp(area: CGSize(width: 1376, height: 832), metrics: .wide)
        #expect(frame.size == CGSize(width: 664, height: 832))
        #expect(frame.photo.height == 768)
    }

    /// `DI_Compare`: 951 × 453 → two 451 × 453 frames, photo 385 tall.
    @Test func duoInnerTwoUpFramesAre451x453() {
        let frame = CompareLayout.twoUp(area: CGSize(width: 951, height: 453), metrics: .cullRow)
        #expect(frame.size == CGSize(width: 451, height: 453))
        #expect(frame.photo.height == 385)
    }

    /// `IP_CompareSurvey`: six photos in 432 × 288 boxes, no scroll.
    @Test func sixFitWithoutScroll() {
        let survey = CompareLayout.survey(count: 6, area: CGSize(width: 1376, height: 832), metrics: .wide)
        #expect(survey.columns == 3)
        #expect(close(survey.photo.width, 432))
        #expect(close(survey.photo.height, 288))
        #expect(!survey.scrolls)
    }

    /// AC-21: twelve on an iPad shrink to the floor, 216 × 144, and scroll.
    @Test func twelveOnIPadShrinkTo216x144AndScroll() {
        let survey = CompareLayout.survey(count: 12, area: CGSize(width: 1376, height: 832), metrics: .wide)
        #expect(close(survey.photo.width, 216))
        #expect(close(survey.photo.height, 144))
        #expect(survey.scrolls)
    }

    /// Nine fit in three rows without reaching the floor.
    @Test func nineShrinkButFit() {
        let survey = CompareLayout.survey(count: 9, area: CGSize(width: 1376, height: 832), metrics: .wide)
        #expect(survey.photo.height < 288)
        #expect(survey.photo.height >= 144)
        #expect(!survey.scrolls)
    }

    /// `DI_CompareSurvey`: 264 × 176 on the Duo's inner display, floor 132 × 88.
    @Test func duoInnerSurveyIs264x176() {
        let area = CGSize(width: 951, height: 452)
        let six = CompareLayout.survey(count: 6, area: area, metrics: .duoInner)
        #expect(close(six.photo.width, 264))
        #expect(close(six.photo.height, 176))
        let many = CompareLayout.survey(count: 15, area: area, metrics: .duoInner)
        #expect(close(many.photo.width, 132))
        #expect(many.scrolls)
    }
}

struct CompareZoomTests {
    /// AC-4: 100% is one original pixel per screen pixel.
    @Test func hundredPercentIsOnePixelPerPixel() {
        // 6000 × 4000 in a 370 × 226 box at 3x: Fit shows 1017 px across.
        let scale = CompareZoom.actualPixelsScale(
            pixelSize: CGSize(width: 6000, height: 4000),
            box: CGSize(width: 370, height: 226),
            screenScale: 3
        )
        #expect(abs(scale - 6000.0 / (339 * 3)) < 0.01)
        #expect(CompareZoom.percent(zoomScale: scale, pixelSize: CGSize(width: 6000, height: 4000),
                                    box: CGSize(width: 370, height: 226), screenScale: 3) == 100)
        #expect(CompareZoom.percent(zoomScale: 1, pixelSize: CGSize(width: 6000, height: 4000),
                                    box: CGSize(width: 370, height: 226), screenScale: 3) == nil)
    }

    @Test func aSmallPhotoIsAlreadyPastFull() {
        let scale = CompareZoom.actualPixelsScale(
            pixelSize: CGSize(width: 300, height: 200),
            box: CGSize(width: 664, height: 768),
            screenScale: 2
        )
        #expect(scale == 1)
    }

    @Test func zTogglesFitAndFull() {
        #expect(CompareZoom.fit.toggled() == .actualPixels)
        #expect(CompareZoom.actualPixels.toggled() == .fit)
    }
}
