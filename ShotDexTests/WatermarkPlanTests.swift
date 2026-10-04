import Foundation
import ShotDexKit
import Testing
@testable import ShotDex

/// FS-05.04 §5's per-photo rules, without a library.
struct WatermarkPlanTests {
    private var credit: WatermarkStamp {
        WatermarkStamp(preset: WatermarkFixture.credit(logo: nil), placement: WatermarkFixture.placementW)
    }

    @Test func tokensAreFilledPerPhoto() {
        guard case .stamp(let stamp) = WatermarkPlan.decide(credit, values: OverlayTokenValues(camera: "X-T5")) else {
            Issue.record("expected a stamp")
            return
        }
        #expect(stamp.layers.first?.text == "© Nguyen An · X-T5")
    }

    /// The line keeps its literal part when the token is empty — that is
    /// still something to stamp.
    @Test func aLiteralSurvivesAnEmptyToken() {
        guard case .stamp(let stamp) = WatermarkPlan.decide(credit, values: .empty) else {
            Issue.record("expected a stamp")
            return
        }
        #expect(stamp.layers.first?.text == "© Nguyen An")
    }

    /// Only tokens, all empty: nothing to stamp, and the tally names it.
    @Test func allTokensEmptyIsNamed() {
        var lensOnly = credit
        lensOnly.layers[0].text = "{lens} · {focal}"
        let decision = WatermarkPlan.decide(lensOnly, values: OverlayTokenValues(camera: "ILCE-7M4"))
        #expect(decision == .nothingToStamp)
        var tally = WatermarkTally(presetName: "Credit")
        tally.record(decision, filename: "DSC0001.JPG")
        tally.record(.stamp(lensOnly), filename: "DSC0002.JPG")
        #expect(tally.nothingToStamp == ["DSC0001.JPG"])
        #expect(tally.stamped == 1)
        #expect(tally.isWorthReporting)
        #expect(WatermarkCopy.savedWithoutWatermark(1, locale: Locale(identifier: "en")) == "1 photo saved without the watermark")
        #expect(WatermarkCopy.savedWithoutWatermark(2, locale: Locale(identifier: "en")) == "2 photos saved without the watermark")
    }
}
