import Foundation
import Testing
@testable import ShotDex

/// FS-03.07b §5: every token, the missing ones left out with their
/// separator, and names any drive takes.
@Suite struct FileNameTemplateTests {
    static let utc = TimeZone(identifier: "UTC")!
    /// 2026-09-20 17:05:12 UTC.
    static let shot = Date(timeIntervalSince1970: 1_789_923_912)
    static let values = FileNameValues(original: "DSCF1000", captureDate: shot, camera: "X-T5", lens: "XF16-55mmF2.8 R LM WR")

    private func name(_ pattern: String, _ values: FileNameValues = Self.values, sequence: Int = 1, width: Int = 3) -> String {
        FileNameTemplate(pattern).baseName(for: values, sequence: sequence, sequenceWidth: width, timeZone: Self.utc)
    }

    @Test func everyToken() {
        #expect(name("{original}") == "DSCF1000")
        #expect(name("{date}") == "2026-09-20")
        #expect(name("{time}") == "170512")
        #expect(name("{camera}") == "X-T5")
        #expect(name("{lens}") == "XF16-55mmF2.8 R LM WR")
        #expect(name("{sequence}", sequence: 7) == "007")
        #expect(name("{date}_{camera}_{sequence}", sequence: 12) == "2026-09-20_X-T5_012")
        #expect(name("Trip {date} {original}") == "Trip 2026-09-20 DSCF1000")
        // Not a token: kept as typed, minus what a drive refuses.
        #expect(name("{foo}_{original}") == "{foo}_DSCF1000")
    }

    /// A screenshot has no camera: `{date}_{camera}_{sequence}` is
    /// `2026-09-21_003`, never `2026-09-21__003`.
    @Test func missingTokenTakesItsSeparator() {
        var screenshot = Self.values
        screenshot.camera = nil
        screenshot.lens = ""
        #expect(name("{date}_{camera}_{sequence}", screenshot, sequence: 3) == "2026-09-20_003")
        #expect(name("{camera}_{date}", screenshot) == "2026-09-20")
        #expect(name("{date}_{camera}_{lens}_{sequence}", screenshot, sequence: 3) == "2026-09-20_003")
        #expect(name("{date}_{camera}", screenshot) == "2026-09-20")
        #expect(name("{date}_Hoi-An_{camera}_{sequence}", screenshot, sequence: 1) == "2026-09-20_Hoi-An_001")
        // Nothing left: the original name.
        #expect(name("{camera}", screenshot) == "DSCF1000")
    }

    /// exFAT and FAT refuse `" * / : < > ? \ |` and control characters;
    /// no leading dot; 200 characters at most.
    @Test func namesAnyDriveTakes() {
        #expect(name("a\"b*c/d:e<f>g?h\\i|j") == "a-b-c-d-e-f-g-h-i-j")
        #expect(name("x\u{0007}y") == "x-y")
        #expect(name("..{original}") == "DSCF1000")
        var long = Self.values
        long.original = String(repeating: "A", count: 300)
        #expect(name("{original}", long).count == 200)
        var slashed = Self.values
        slashed.camera = "EOS R6/II"
        #expect(name("{camera}", slashed) == "EOS R6-II")
    }

    /// `{sequence}` is three digits up to 999, four from 1,000.
    @Test func sequenceWidthGrowsAtAThousand() {
        #expect(FileNameTemplate.sequenceWidth(count: 999) == 3)
        #expect(FileNameTemplate.sequenceWidth(count: 1_000) == 4)
        #expect(name("{sequence}", sequence: 1, width: FileNameTemplate.sequenceWidth(count: 1_000)) == "0001")
        #expect(name("{sequence}", sequence: 1_000, width: 4) == "1000")
    }

    @Test func emptyTemplateIsNotUsable() {
        #expect(!FileNameTemplate("  ").isUsable)
        #expect(FileNameTemplate.originalName.isUsable)
        #expect(FileNameTemplate.builtIns.map(\.pattern) == ["{original}", "{date}_{camera}_{sequence}", "{date}_{original}"])
    }

    /// FS-20 AC-25: `{originalNumber}` is the digits that end the original
    /// name — `IMG_6123` gives `6123` — and drops out like any token with no
    /// value when the name ends in a letter.
    @Test func originalNumberTakesTrailingDigits() {
        var values = Self.values
        values.original = "IMG_6123"
        #expect(name("{originalNumber}", values) == "6123")
        #expect(name("{date}_{originalNumber}", values) == "2026-09-20_6123")
        values.original = "DSCF0042"
        #expect(name("{originalNumber}", values) == "0042")
        values.original = "Panorama"
        #expect(name("{date}_{originalNumber}", values) == "2026-09-20")
    }

    /// `{sequence}` keeps the batch's width wherever it sits.
    @Test func sequenceKeepsWidth() {
        #expect(name("{sequence}_{original}", sequence: 42) == "042_DSCF1000")
        #expect(name("{original}-{sequence}", sequence: 42, width: 4) == "DSCF1000-0042")
    }
}
