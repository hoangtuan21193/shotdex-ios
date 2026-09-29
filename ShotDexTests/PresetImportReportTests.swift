import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

struct PresetImportReportTests {
    /// FS-03.14 AC-a7. Exposure +1.00 and an unknown crs:FutureSlider: the
    /// look is added with Exposure +1.00, the row is ≈, and the line names
    /// the tag.
    @Test func unknownTagsAreListedNotFatal() throws {
        let settings = try LightroomXMPReader.read(LightroomXMPReaderTests.preset(
            #"crs:Exposure2012="+1.00" crs:FutureSlider="40""#
        ))
        let result = LightroomMapping.map(settings)
        #expect(result.recipe.adjustments[.exposure] == 1)
        #expect(result.lines == [PresetReportLine(kind: .changed, text: "Unknown setting FutureSlider — ignored")])
        #expect(PresetImportReport.status(applied: result.appliedCount, lines: result.lines) == .addedWithChanges)
    }
}
