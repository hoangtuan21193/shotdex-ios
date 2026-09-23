import Testing
@testable import ShotDex

/// FS-01.09 AC-12: the alert says which step failed. A preview that could not
/// be built has nothing to save yet, so it must not say "Couldn't Save".
struct PhotoStackModelTests {

    @Test func aPreviewFailureIsNotCalledASaveFailure() {
        #expect(PhotoStackModel.Failure.load("x").title == "Couldn't Load Photos")
    }

    @Test func aSaveFailureSaysSave() {
        #expect(PhotoStackModel.Failure.save("x").title == "Couldn't Save")
    }

    @Test func theReasonIsShownAsIs() {
        #expect(PhotoStackModel.Failure.save("The disk is full.").message == "The disk is full.")
        #expect(PhotoStackModel.Failure.load("Pick at least two photos to combine.").message == "Pick at least two photos to combine.")
    }

    @Test func noAlertIsTitledCombine() {
        for failure in [PhotoStackModel.Failure.load(""), .save("")] {
            #expect(!failure.title.contains("Combine"))
        }
    }
}
