import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.16 §5 — Lightroom's lens-profile tags.
struct LightroomLensProfileMappingTests {

    static func tags(name: String) -> [String: String] {
        [
            "LensProfileEnable": "1",
            "LensProfileSetup": "Custom",
            "LensProfileName": name,
            "LensProfileDistortionScale": "80",
            "LensProfileVignettingScale": "120",
            "LensProfileChromaticAberrationScale": "100",
        ]
    }

    /// AC-4. Enable 1, Custom, "Adobe (Canon EF 24-70mm f/2.8L II USM)",
    /// 80/120/100: switch on, the Lensfun row of that name, the three
    /// strengths, a ✓ line.
    @Test func customNameMatchesLensfunRow() throws {
        let result = LightroomLensProfileMapping().map(Self.tags(name: "Adobe (Canon EF 24-70mm f/2.8L II USM)"))
        #expect(result.isEnabled == true)
        #expect(result.distortion == 0.8 && result.vignetting == 1.2 && result.chromaticAberration == 1)
        let lens = try #require(result.lens)
        #expect(lens.model.contains("24-70mm f/2.8L II USM"), "\(lens.model)")
        #expect(result.report == .matched("Canon EF 24-70mm f/2.8L II USM"))
    }

    /// AC-5. A name the table does not have: strengths kept, no lens (each
    /// photo resolves its own), a ≈ line naming it, no crash.
    @Test func unknownNameKeepsStrengthsAndReports() {
        let result = LightroomLensProfileMapping().map(Self.tags(name: "Adobe (Foo 13mm f/1.1)"))
        #expect(result.distortion == 0.8 && result.vignetting == 1.2)
        #expect(result.lens == nil)
        #expect(result.report == .approximate("Foo 13mm f/1.1"))
    }

    /// Setup Auto ignores any name: every photo resolves its own lens.
    @Test func autoSetupIgnoresTheName() {
        var tags = Self.tags(name: "Adobe (Canon EF 24-70mm f/2.8L II USM)")
        tags["LensProfileSetup"] = "Auto"
        let result = LightroomLensProfileMapping().map(tags)
        #expect(result.lens == nil && result.report == nil && result.isEnabled == true)
    }
}
