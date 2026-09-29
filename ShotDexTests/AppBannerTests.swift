import Foundation
import Testing
@testable import ShotDex

@MainActor
struct AppBannerTests {
    /// FS-03.14c §4 (E9). A banner with a button stays about four seconds;
    /// a plain line goes as fast as the action toast.
    @Test func actionBannerStaysAboutFourSeconds() throws {
        let model = AppBannerModel()
        model.show("Golden added to My Looks", actionTitle: "Undo") {}
        let banner = try #require(model.current)
        #expect(banner.actionTitle == "Undo")
        #expect(banner.duration == .seconds(4))
        model.show("Copied")
        #expect(model.current?.duration == .milliseconds(1600))
        #expect(model.current?.actionTitle == nil, "no action, no button")
    }

    /// The button runs its action once and the banner goes; a timer started
    /// for an older banner does not take a newer one down.
    @Test func actionRunsOnceAndStaleTimersDoNothing() throws {
        let model = AppBannerModel()
        var undone = 0
        model.show("Golden added to My Looks", actionTitle: "Undo") { undone += 1 }
        let first = try #require(model.current)
        model.show("Teal Look added to My Looks", actionTitle: "Undo") { undone += 10 }
        model.expire(first.id)
        #expect(model.current != nil, "the first banner's timer leaves the second")
        model.performAction()
        model.performAction()
        #expect(undone == 10)
        #expect(model.current == nil)
    }
}
