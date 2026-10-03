import Foundation
import Testing
@testable import ShotDex

/// FS-12.07 §1: an ordinary iPhone runs the Video Studio portrait only, and
/// the lock is the app's own — the iPhone orientation list in the built
/// Info.plist, which the unit tests read from the host app's bundle.
struct VideoStudioOrientationTests {
    /// FS-12.07 AC-1: turning the phone sideways leaves the studio upright,
    /// because portrait is the only orientation an iPhone is offered.
    @Test func anIPhoneRunsPortraitOnly() throws {
        let orientations = try #require(
            Bundle.main.object(forInfoDictionaryKey: "UISupportedInterfaceOrientations~iphone") as? [String]
        )
        #expect(orientations == ["UIInterfaceOrientationPortrait"])
    }
}
