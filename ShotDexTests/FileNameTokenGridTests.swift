import Foundation
import Testing
@testable import ShotDex

/// FS-20 AC-25: Export's File Name screen and Import's inspector read their
/// token chips from one list, so they offer the same eight in the same words.
@Suite struct FileNameTokenGridTests {
    @Test func eightChipsSameWords() {
        #expect(FileNameChip.all.map(ExportCopy.chipTitle) == [
            "Original Name", "Original Number", "Date", "Time", "Camera", "Lens", "Sequence", "Text",
        ])
        // Every token the template understands has a chip, and only Text is not a token.
        let tokens = FileNameChip.all.compactMap { if case .token(let token) = $0 { token } else { nil } }
        #expect(Set(tokens) == Set(FileNameTemplate.Token.allCases))
    }

    /// A token chip appends its placeholder; Text appends `_Text` with the
    /// word marked for typing over, and stays plain text in the pattern.
    @Test func chipsAppendToTheTemplate() {
        #expect(FileNameChip.token(.sequence).appended(to: "{date}_").pattern == "{date}_{sequence}")
        let text = FileNameChip.text.appended(to: "{date}")
        #expect(text.pattern == "{date}_Text")
        #expect(text.typedRange.map { String(text.pattern[$0]) } == "Text")
        #expect(FileNameChip.text.appended(to: "").pattern == "Text")
        #expect(FileNameChip.text.appended(to: "{date}_").pattern == "{date}_Text")
    }
}
