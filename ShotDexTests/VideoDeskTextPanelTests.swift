import Testing
@testable import ShotDex

/// FS-12.04b §4: the iPad's caption panel shows every section at once; a
/// command cell brings its own section up rather than replacing the panel.
@MainActor
struct VideoDeskTextPanelTests {
    /// AC-14: every text command of the row has a section to bring up, and
    /// no two share one — so no command is a dead tap on the iPad.
    @Test func everyTextCommandHasItsOwnSection() {
        let tools: [VideoStudioModel.TextTool] = [.edit, .font, .color, .align, .style, .animate]
        let sections = tools.map(VideoDeskTextPanel.Section.init)
        #expect(Set(sections).count == tools.count)
        #expect(VideoDeskTextPanel.Section(.transform) == .text)
        #expect(VideoDeskTextPanel.Section(.edit) == .text)
        // Spacing is the one section no command names: it is past the fold
        // and reached by scrolling.
        #expect(Set(VideoDeskTextPanel.Section.allCases).subtracting(sections) == [.spacing])
    }
}
