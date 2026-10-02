import CoreImage
import Foundation
import Testing
@testable import ShotDex

/// FS-03.04b §2: matching EXIF names to the decoder's list, and the three
/// steps that settle a camera.
struct RAWDecoderVerdictTests {
    /// Entries as `CIRAWFilter.supportedCameraModels` spells them on iOS
    /// 26.5 (M1, 2026-10-02).
    static let measured = [
        "Nikon Z 6 2", "Nikon Z5II", "Sony Alpha ILCE-7M3", "Sony Alpha ILCE-7M4",
        "Fujifilm X-T4", "Canon EOS R5", "Leica M11", "iPhone16,1 backwide",
    ]
    let matcher = RAWCameraMatcher(supportedModels: measured)

    /// AC-1: `NIKON Z 6_2` is the list's "Nikon Z 6 2".
    @Test func nikonUnderscoreMatchesSpacedName() {
        #expect(matcher.isListed(make: "NIKON CORPORATION", model: "NIKON Z 6_2"))
        #expect(matcher.isListed(make: "Nikon", model: "Z 6_2"))
    }

    @Test func sonyMatchesWithoutAlpha() {
        #expect(matcher.isListed(make: "SONY", model: "ILCE-7M4"))
        #expect(matcher.isListed(make: "Sony", model: "ILCE-7M3"))
    }

    @Test func otherMakersMatch() {
        #expect(matcher.isListed(make: "FUJIFILM", model: "X-T4"))
        #expect(matcher.isListed(make: "Canon", model: "Canon EOS R5"))
        #expect(matcher.isListed(make: "LEICA CAMERA AG", model: "LEICA M11"))
    }

    /// A miss is only a miss: the camera goes on to a file on the device.
    @Test func unlistedCamerasMiss() {
        #expect(!matcher.isListed(make: "FUJIFILM", model: "X-Q9"))
        #expect(!matcher.isListed(make: "SONY", model: "ILCE-7M5"))
        #expect(!matcher.isListed(make: "Apple", model: "iPhone 15 Pro"))
        #expect(!matcher.isListed(make: "SONY", model: nil))
        #expect(!matcher.isListed(make: nil, model: "  "))
    }

    /// Against the decoder of the simulator the test runs on.
    @Test func systemListKnowsTheMeasuredCameras() {
        let system = RAWCameraMatcher(supportedModels: CIRAWFilter.supportedCameraModels)
        #expect(system.isListed(make: "NIKON CORPORATION", model: "NIKON Z 6_2"))
        #expect(system.isListed(make: "SONY", model: "ILCE-7M3"))
        #expect(system.isListed(make: "FUJIFILM", model: "X-T4"))
        #expect(!system.isListed(make: "FUJIFILM", model: "X-Q9"))
    }

    @Test func listedIsReadableWithoutTryingAFile() async {
        var tried = 0
        let result = await RAWVerdictRules.judge(listed: true) { tried += 1; return false }
        #expect(result.verdict == .readable)
        #expect(result.source == .list)
        #expect(tried == 0)
    }

    @Test func editorSettlesUnknownOnly() {
        #expect(RAWVerdictRules.afterEditor(.unknown, decoded: false) == .unreadable)
        #expect(RAWVerdictRules.afterEditor(nil, decoded: false) == .unreadable)
        #expect(RAWVerdictRules.afterEditor(.unknown, decoded: true) == .readable)
        // One odd file of a readable camera reports itself; the camera stays.
        #expect(RAWVerdictRules.afterEditor(.readable, decoded: false) == nil)
        #expect(RAWVerdictRules.afterEditor(.unreadable, decoded: false) == nil)
        #expect(RAWVerdictRules.afterEditor(.unreadable, decoded: true) == .readable)
    }

    @Test func cameraKeyAndName() throws {
        let camera = try #require(RAWCamera(manufacturer: "Sony", model: "ILCE-7M5"))
        #expect(camera.key == "Sony|ILCE-7M5")
        #expect(camera.displayName == "Sony ILCE-7M5")
        #expect(RAWCamera(manufacturer: "Sony", model: " ") == nil)
        #expect(RAWCamera(manufacturer: nil, model: "X-Q9")?.key == "|X-Q9")
    }

    @Test func buildFromVersionString() {
        #expect(OSRelease.build(from: "Version 26.5 (Build 23F77)") == "23F77")
        #expect(OSRelease.build(from: "Version 27.0") == nil)
    }
}
