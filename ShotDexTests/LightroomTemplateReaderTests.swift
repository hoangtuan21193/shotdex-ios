import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.14a — `.lrtemplate` read as data, never run. Written for the test
/// from the format's description.
struct LightroomTemplateReaderTests {
    /// FS-03.14 AC-a2. Title "Matte", Contrast −30, Blacks +25: a look named
    /// "Matte" with Contrast −30 and Blacks +25, ✓.
    @Test func readsSettingsAsData() throws {
        let template = Data("""
        s = {
        	id = "9D6D1F0C-0000-4000-8000-000000000001",
        	internalName = "Matte",
        	title = ZSTR "$$$/AgDevelop/Presets/User/Matte=Matte",
        	type = "Develop",
        	value = {
        		settings = {
        			Contrast2012 = -30,
        			Blacks2012 = 25,
        			ToneCurvePV2012 = { 0, 18, 128, 128, 255, 240, },
        			ProcessVersion = "11.0", -- comment
        		},
        		uuid = "9D6D1F0C-0000-4000-8000-000000000002",
        	},
        	version = 0,
        }
        """.utf8)
        let settings = try LightroomTemplateReader.read(template)
        #expect(settings.name == "Matte")
        #expect(settings.lists["ToneCurvePV2012"] == ["0, 18", "128, 128", "255, 240"])
        let result = LightroomMapping.map(settings)
        #expect(abs(result.recipe.adjustments[.contrast] + 0.3) < 1e-9)
        #expect(abs(result.recipe.adjustments[.blackPoint] - 0.25) < 1e-9)
        #expect(PresetImportReport.status(applied: result.appliedCount, lines: result.lines) == .added)
    }

    /// A call, a concatenation, a bare name: code, and the whole preset is
    /// refused rather than any of it run.
    @Test func functionCallsAreRejected() {
        for body in [
            #"s = { value = { settings = { Exposure2012 = os.execute("rm -rf /") } } }"#,
            #"s = { value = { settings = { Exposure2012 = "1" .. "2" } } }"#,
            #"s = { value = { settings = { Exposure2012 = somethingElse } } }"#,
            #"s = { value = { settings = { Exposure2012 = (1) } } }"#,
        ] {
            #expect(throws: LightroomTemplateReader.Failure.notData, "\(body)") {
                try LightroomTemplateReader.read(Data(body.utf8))
            }
        }
        let deep = "s = " + String(repeating: "{ ", count: 40) + String(repeating: "} ", count: 40)
        #expect(throws: LightroomTemplateReader.Failure.notData) { try LightroomTemplateReader.read(Data(deep.utf8)) }
    }
}
