import Foundation
import Testing
import UIKit
@testable import ShotDex

/// The tile's title sits on the cover now, so whether that cover gets
/// darkened behind it is a decision made per photo. These pin the decision.
@Suite struct CoverTitleScrimTests {
    /// An image whose top half is `top` and bottom half is `bottom`, so the
    /// bottom strip the scrim measures can differ from the rest.
    private func image(top: UIColor, bottom: UIColor, side: CGFloat = 40) -> UIImage {
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size).image { context in
            top.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side / 2))
            bottom.setFill()
            context.fill(CGRect(x: 0, y: side / 2, width: side, height: side / 2))
        }
    }

    @Test func aWhiteBottomNeedsAScrim() {
        let cover = image(top: .black, bottom: .white)
        #expect(CoverTitleScrim.isNeeded(for: cover))
    }

    @Test func aBlackBottomDoesNot() {
        let cover = image(top: .white, bottom: .black)
        #expect(!CoverTitleScrim.isNeeded(for: cover))
    }

    /// The whole point of measuring only the bottom: a photo that is bright
    /// everywhere *except* where the title goes must not be darkened.
    @Test func onlyTheBottomStripIsMeasured() {
        let brightSkyOverDarkGround = image(top: .white, bottom: UIColor(white: 0.1, alpha: 1))
        #expect(!CoverTitleScrim.isNeeded(for: brightSkyOverDarkGround))

        let darkSkyOverSnow = image(top: UIColor(white: 0.05, alpha: 1), bottom: .white)
        #expect(CoverTitleScrim.isNeeded(for: darkSkyOverSnow))
    }

    /// Rec. 709, not a flat RGB mean. Pure blue and pure green have the same
    /// naive average; only one of them is bright enough to hide white text.
    @Test func luminanceIsWeightedByChannel() {
        let blue = CoverTitleScrim.bottomLuminance(of: image(top: .blue, bottom: .blue))
        let green = CoverTitleScrim.bottomLuminance(of: image(top: .green, bottom: .green))
        #expect(blue != nil && green != nil)
        #expect(blue! < green!, "a flat average would call these equal")
        #expect(!CoverTitleScrim.isNeeded(for: image(top: .blue, bottom: .blue)))
        #expect(CoverTitleScrim.isNeeded(for: image(top: .green, bottom: .green)))
    }

    @Test func midGreySitsOnTheBrightSideOfTheThreshold() {
        let grey = image(top: .gray, bottom: UIColor(white: 0.5, alpha: 1))
        let luminance = CoverTitleScrim.bottomLuminance(of: grey)
        #expect(luminance != nil)
        #expect(abs(luminance! - 0.5) < 0.02, "0.5 grey should read as 0.5")
        #expect(CoverTitleScrim.isNeeded(for: grey))
    }

    /// A cover that cannot be measured gets the scrim: an unreadable name is
    /// the worse of the two failures.
    @Test func anUnreadableImageFallsBackToScrimmed() {
        #expect(CoverTitleScrim.isNeeded(for: UIImage()))
    }
}
