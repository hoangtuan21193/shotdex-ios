import Testing
@testable import ShotDex
@testable import ShotDexKit

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

    @MainActor
    @Test func pickingAMethodResetsItsSliders() {
        let dependencies = AppDependencies.preview()
        let model = PhotoStackModel(purpose: .focusStack, assets: [], photoLibrary: dependencies.photoLibrary,
                                    indexPipeline: dependencies.indexPipeline)
        #expect(model.focusOptions == .standard)
        model.focusOptions = FocusStackOptions(method: .weighted, radius: 9, smoothing: 7)
        model.selectFocusMethod(.depthMap)
        #expect(model.focusOptions == .defaults(for: .depthMap))
        model.selectFocusMethod(.weighted)
        #expect(model.focusOptions == .defaults(for: .weighted))
    }

    @MainActor
    @Test func aFocusStackOpensOnWeighted() {
        let dependencies = AppDependencies.preview()
        let model = PhotoStackModel(purpose: .focusStack, assets: [], photoLibrary: dependencies.photoLibrary,
                                    indexPipeline: dependencies.indexPipeline)
        #expect(model.focusOptions == FocusStackOptions(method: .weighted, radius: 4, smoothing: 4))
        #expect(model.mode == .focusStack)
    }

    @MainActor
    @Test func withNoStrokesNewOptionsApplyAtOnce() {
        let dependencies = AppDependencies.preview()
        let model = PhotoStackModel(purpose: .focusStack, assets: [], photoLibrary: dependencies.photoLibrary,
                                    indexPipeline: dependencies.indexPipeline)
        model.requestFocusOptions(FocusStackOptions(method: .weighted, radius: 5, smoothing: 1))
        #expect(model.focusOptions.radius == 5)
        #expect(model.pendingFocusOptions == nil)
    }

    @MainActor
    @Test func retouchStartsOnAutoAndAFramePickTurnsItOff() {
        let dependencies = AppDependencies.preview()
        let model = PhotoStackModel(purpose: .focusStack, assets: [], photoLibrary: dependencies.photoLibrary,
                                    indexPipeline: dependencies.indexPipeline)
        #expect(model.picksFrameAutomatically)
        #expect(!model.canRetouch)   // nothing stacked yet
        model.pickRetouchFrame(3)
        #expect(!model.picksFrameAutomatically && model.retouchFrame == 3)
        model.pickRetouchFrame(nil)
        #expect(model.picksFrameAutomatically)
        #expect(!model.canUndoRetouch)
    }
}
